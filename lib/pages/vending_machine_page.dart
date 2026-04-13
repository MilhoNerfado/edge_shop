import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../app_strings.dart';
import '../models/item_config.dart';
import '../models/vending_item.dart';
import '../services/item_config_service.dart';
import '../services/uart_service.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bgColor = Color(0xFF041B38);
const _nfcIconBg = Color(0xFF153C6B);
const _cardDefaultBg = Color(0xFF0D2444);
const _successGreen = Color(0xFF4CAF50);

enum _VendingState { idle, confirming, waitingPayment, done }

class VendingMachinePage extends StatefulWidget {
  const VendingMachinePage({super.key});

  @override
  State<VendingMachinePage> createState() => _VendingMachinePageState();
}

class _VendingMachinePageState extends State<VendingMachinePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _uart = UartChannelService();
  bool _portOpen = false;
  int _stateBits = 0x00;

  _VendingState _state = _VendingState.idle;
  VendingItem? _selectedItem;
  DateTime? _lastNfcScan;

  Timer? _doneTimer;
  int _doneSecondsLeft = 5;

  late AppStrings _strings;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late PageController _pageController;
  int _currentPageIndex = 0;
  List<ItemConfig> _itemConfigs = List.filled(3, const ItemConfig());

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pageController = PageController(viewportFraction: 0.70);
    _openPort();
    _startNfcSession(); // pre-warm session so it's ready before first tap
    _loadItemConfigs();
  }

  Future<void> _loadItemConfigs() async {
    try {
      await ItemConfigService.instance.importSetupBundleIfChanged();
    } catch (e, st) {
      dev.log(
        'Item setup auto-import failed: $e',
        name: 'EdgeShop.Items',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }

    final configs = await Future.wait([
      ItemConfigService.instance.load(1),
      ItemConfigService.instance.load(2),
      ItemConfigService.instance.load(3),
    ]);
    if (!mounted) return;
    setState(() => _itemConfigs = configs);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    _strings = AppStrings.of(locale.languageCode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _pageController.dispose();
    _doneTimer?.cancel();
    NfcManager.instance.stopSession();
    if (_portOpen) _uart.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_portOpen) {
        _uart.close();
        setState(() => _portOpen = false);
      }
      NfcManager.instance.stopSession();
      dev.log(
        'NFC: session stopped (app paused/detached)',
        name: 'EdgeShop.NFC',
      );
    } else if (state == AppLifecycleState.resumed) {
      dev.log('NFC: restarting session (app resumed)', name: 'EdgeShop.NFC');
      _loadItemConfigs();
      _startNfcSession();
    }
  }

  // ── Hardware ───────────────────────────────────────────────────────────────

  Future<void> _openPort() async {
    final result = await _uart.open();
    if (result['success'] as bool) {
      setState(() => _portOpen = true);
      await Future.delayed(const Duration(milliseconds: 500));
      await _pushState(0x00);
    }
  }

  Future<void> _pushState(int bits) async {
    bits &= 0x0F;
    final hex = '0x${bits.toRadixString(16).padLeft(2, '0')}\n';
    final result = await _uart.write(hex);
    if (result['success'] as bool) {
      setState(() => _stateBits = bits);
    }
  }

  Future<void> _openGpio(int channel) =>
      _pushState(_stateBits | (1 << channel));

  Future<void> _closeGpio(int channel) =>
      _pushState(_stateBits & ~(1 << channel));

  // ── NFC ───────────────────────────────────────────────────────────────────

  void _startNfcSession() {
    dev.log(
      'NFC: startSession (always-on) — current state=$_state',
      name: 'EdgeShop.NFC',
    );
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final now = DateTime.now();
        final techs = tag.data.keys.toList();
        dev.log(
          'NFC: tag discovered — techs=$techs state=$_state ts=${now.millisecondsSinceEpoch}',
          name: 'EdgeShop.NFC',
        );

        if (_state != _VendingState.waitingPayment) {
          dev.log(
            'NFC: tag ignored — state is $_state (not waitingPayment)',
            name: 'EdgeShop.NFC',
          );
          return;
        }

        if (_lastNfcScan != null &&
            now.difference(_lastNfcScan!) < const Duration(seconds: 1)) {
          dev.log(
            'NFC: debounced — ${now.difference(_lastNfcScan!).inMilliseconds}ms since last scan',
            name: 'EdgeShop.NFC',
          );
          return;
        }
        _lastNfcScan = now;

        final tagId = _extractTagId(tag);
        dev.log(
          'NFC: accepting tag for payment — id=$tagId slot=${_selectedItem?.slot}',
          name: 'EdgeShop.NFC',
        );
        await _onPaymentTagScanned(tagId);
      },
      onError: (e) async {
        dev.log(
          'NFC: session error — ${e.message} (type=${e.type}) state=$_state',
          name: 'EdgeShop.NFC',
          level: 1000,
        );
        // Auto-restart session on error so reader stays active
        if (mounted) {
          dev.log('NFC: restarting session after error', name: 'EdgeShop.NFC');
          _startNfcSession();
        }
      },
    );
  }

  String _extractTagId(NfcTag tag) {
    for (final entry in tag.data.entries) {
      final tech = entry.value;
      if (tech is Map) {
        final id = tech['identifier'];
        if (id is Uint8List) {
          final hex = id
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':')
              .toUpperCase();
          dev.log(
            'NFC: identifier found in tech "${entry.key}" → $hex',
            name: 'EdgeShop.NFC',
          );
          return hex;
        }
      }
    }
    dev.log(
      'NFC: no identifier found in any tech — data keys: ${tag.data.keys}',
      name: 'EdgeShop.NFC',
      level: 900,
    );
    return 'UNKNOWN';
  }

  // ── Vending flow ──────────────────────────────────────────────────────────

  void _selectItem(VendingItem item) {
    dev.log(
      'NFC: item selected — slot=${item.slot} gpio=${item.gpioChannel}',
      name: 'EdgeShop.NFC',
    );
    setState(() {
      _selectedItem = item;
      _state = _VendingState.confirming;
      _lastNfcScan = null;
    });
    // NFC session already running — no startSession needed here
  }

  void _confirmItem() {
    if (_selectedItem == null) return;
    setState(() => _state = _VendingState.waitingPayment);
  }

  void _cancelConfirmation() {
    dev.log('NFC: confirmation cancelled', name: 'EdgeShop.NFC');
    _resetToIdle(pageIndex: _currentPageIndex);
  }

  Future<void> _onPaymentTagScanned(String tagId) async {
    if (_state != _VendingState.waitingPayment || _selectedItem == null) return;
    dev.log(
      'NFC: payment confirmed — tag=$tagId slot=${_selectedItem!.slot} gpio=${_selectedItem!.gpioChannel}',
      name: 'EdgeShop.NFC',
    );
    // NOTE: do NOT call stopSession() here — calling it from inside the
    // onDiscovered callback causes an Android NFC deadlock. Session stays running.
    setState(() {
      _state = _VendingState.done;
      _doneSecondsLeft = 5;
    });
    _startDoneTimer();

    // 1-second GPIO pulse
    await _openGpio(_selectedItem!.gpioChannel);
    dev.log(
      'GPIO: channel ${_selectedItem!.gpioChannel} OPENED (pulse)',
      name: 'EdgeShop.GPIO',
    );
    await Future.delayed(const Duration(seconds: 1));
    await _closeGpio(_selectedItem!.gpioChannel);
    dev.log(
      'GPIO: channel ${_selectedItem!.gpioChannel} CLOSED (pulse end)',
      name: 'EdgeShop.GPIO',
    );
  }

  void _startDoneTimer() {
    _doneTimer?.cancel();
    _doneTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _doneSecondsLeft--);
      if (_doneSecondsLeft <= 0) {
        timer.cancel();
        _resetToIdle();
      }
    });
  }

  void _resetToIdle({int? pageIndex}) {
    _doneTimer?.cancel();
    _doneTimer = null;
    if (mounted) {
      setState(() {
        _state = _VendingState.idle;
        _selectedItem = null;
        _lastNfcScan = null;
        _doneSecondsLeft = 5;
        if (pageIndex != null) {
          _currentPageIndex = pageIndex;
        }
      });
    }
    if (pageIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(pageIndex);
      });
    }
  }

  Future<void> _cancelSelection() async {
    dev.log('NFC: cancel — state=$_state', name: 'EdgeShop.NFC');
    // Session keeps running — no stopSession needed
    _resetToIdle();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          if (_state == _VendingState.idle)
            SafeArea(child: _buildProductGrid()),
          if (_state == _VendingState.confirming) _buildConfirmationScreen(),
          if (_state == _VendingState.waitingPayment) _buildPaymentScreen(),
          if (_state == _VendingState.done) _buildSuccessScreen(),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            // Top-left glow ellipse (partially off-screen)
            Positioned(
              top: -h * 0.12,
              left: -w * 0.22,
              child: _glowEllipse(w * 0.58, h * 0.30),
            ),
            // Bottom-left glow ellipse
            Positioned(
              bottom: -h * 0.06,
              left: 0,
              child: _glowEllipse(w * 0.58, h * 0.30),
            ),
            // Right glow ellipse (rotated)
            Positioned(
              top: h * 0.33,
              right: -w * 0.18,
              child: Transform.rotate(
                angle: -pi / 2,
                child: _glowEllipse(w * 0.58, h * 0.30),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glowEllipse(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.elliptical(w / 2, h / 2)),
        gradient: RadialGradient(
          colors: [
            const Color(0xFF1A5096).withValues(alpha: 0.45),
            _bgColor.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeLogo() {
    return SvgPicture.asset(
      'assets/edge.svg',
      height: 48,
      colorFilter: ColorFilter.mode(
        Colors.white.withValues(alpha: 0.7),
        BlendMode.srcIn,
      ),
    );
  }

  ButtonStyle _confirmationButtonStyle({
    required Color backgroundColor,
    required Color foregroundColor,
    Color? borderColor,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: 0,
      side: borderColor == null
          ? null
          : BorderSide(color: borderColor, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildConfirmationActionButton({
    required VoidCallback onPressed,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    Color? borderColor,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: _confirmationButtonStyle(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          borderColor: borderColor,
        ),
        child: Text(label),
      ),
    );
  }

  // ── Gift selection screen (idle) ───────────────────────────────────────────

  Widget _buildProductGrid() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(alignment: Alignment.centerLeft, child: _buildEdgeLogo()),
                const Center(
                  child: Text(
                    'Choose your gift',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: _portOpen
                            ? const Color(0xFF00FF88)
                            : Colors.orange,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _portOpen ? _strings.ready : _strings.connecting,
                        style: TextStyle(
                          color: _portOpen
                              ? const Color(0xFF00FF88)
                              : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white24,
                          size: 20,
                        ),
                        onPressed: () async {
                          dev.log(
                            'NFC: stopping session for debug navigation',
                            name: 'EdgeShop.NFC',
                          );
                          final navigator = Navigator.of(context);
                          await NfcManager.instance.stopSession();
                          await navigator.pushNamed('/debug');
                          if (mounted) {
                            dev.log(
                              'NFC: restarting session after debug return',
                              name: 'EdgeShop.NFC',
                            );
                            _loadItemConfigs();
                            _startNfcSession();
                          }
                        },
                        tooltip: 'Debug tools',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Snapping vertical PageView — each card ~70 % of viewport height
        Expanded(
          child: PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _pageController,
            itemCount: vendingItems.length,
            onPageChanged: (index) => _currentPageIndex = index,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: _buildProductCard(vendingItems[index]),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildProductCard(VendingItem item) {
    final config = _itemConfigs[item.giftIndex - 1];
    final name = config.customName ?? _strings.giftNames[item.giftIndex - 1];
    return GestureDetector(
      onTap: () => _selectItem(item),
      child: Container(
        decoration: BoxDecoration(
          color: _cardDefaultBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Expanded(child: _buildProductVisual(config)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemIcon(ItemConfig config, double size) {
    switch (config.iconType) {
      case IconType.image:
        final path = config.imagePath;
        if (path == null) {
          return Icon(Icons.card_giftcard, color: Colors.white, size: size);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.15),
          child: SizedBox(
            width: size,
            height: size,
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        );
      case IconType.material:
        return Icon(
          resolveCuratedItemIcon(config.materialIconCode),
          color: Colors.white,
          size: size,
        );
      case IconType.defaultIcon:
        return Icon(Icons.card_giftcard, color: Colors.white, size: size);
    }
  }

  Widget _buildProductVisual(ItemConfig config) {
    if (config.iconType == IconType.image && config.imagePath != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SizedBox.expand(
          child: Image.file(
            File(config.imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Center(child: _buildItemIcon(const ItemConfig(), 140)),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxHeight * 0.82).clamp(
          24.0,
          double.infinity,
        );
        return Center(child: _buildItemIcon(config, iconSize));
      },
    );
  }

  Widget _buildConfirmationScreen() {
    final item = _selectedItem;
    if (item == null) {
      return const SizedBox.shrink();
    }

    final config = _itemConfigs[item.giftIndex - 1];
    final name = config.customName ?? _strings.giftNames[item.giftIndex - 1];
    final description = config.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      right: 0,
                      child: _buildConfirmationMedia(config),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 152),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w600,
                              height: 1.05,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (hasDescription) ...[
                            const SizedBox(height: 24),
                            Expanded(
                              child: Text(
                                description,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w400,
                                  height: 1.35,
                                ),
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildConfirmationActionButton(
                onPressed: _confirmItem,
                label: _strings.confirm,
                backgroundColor: const Color(0xFF1A5096),
                foregroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              _buildConfirmationActionButton(
                onPressed: _cancelConfirmation,
                label: '\u2190 ${_strings.goBack}',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A5096),
                borderColor: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationMedia(ItemConfig config) {
    if (config.iconType == IconType.image && config.imagePath != null) {
      return SizedBox(
        width: 132,
        height: 220,
        child: Opacity(
          opacity: 0.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(config.imagePath!), fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        _bgColor.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: 0.35,
      child: SizedBox(
        width: 132,
        height: 220,
        child: Align(
          alignment: Alignment.topRight,
          child: _buildItemIcon(config, 132),
        ),
      ),
    );
  }

  // ── NFC waiting screen ─────────────────────────────────────────────────────

  Widget _buildPaymentScreen() {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing NFC icon with concentric rings
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                return SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _nfcIconBg.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      // Middle ring
                      Transform.scale(
                        scale: (_pulseAnimation.value * 0.6 + 0.7),
                        child: Container(
                          width: 192,
                          height: 192,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _nfcIconBg.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      // Core circle
                      Container(
                        width: 156,
                        height: 156,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _nfcIconBg,
                        ),
                        child: const Icon(
                          Icons.sensors,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 52),
            const Text(
              'Tap NFC card to confirm',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: _cancelSelection,
              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
              label: Text(
                _strings.cancel,
                style: const TextStyle(color: Colors.white38, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Success screen ─────────────────────────────────────────────────────────

  Widget _buildSuccessScreen() {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(Icons.task_alt, color: _successGreen, size: 120),
            const SizedBox(height: 32),
            const Text(
              'Enjoy your gift!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Thank you for your participation.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _resetToIdle,
              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
              label: Text(
                '${_strings.close}  ($_doneSecondsLeft)',
                style: const TextStyle(color: Colors.white38, fontSize: 15),
              ),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}
