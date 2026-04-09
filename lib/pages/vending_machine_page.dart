import 'dart:developer' as dev;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../app_strings.dart';
import '../models/vending_item.dart';
import '../services/uart_service.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bgColor = Color(0xFF041B38);
const _nfcIconBg = Color(0xFF153C6B);
const _cardDefaultBg = Color(0xFF0D2444);
const _successGreen = Color(0xFF4CAF50);

enum _VendingState { idle, waitingPayment, dispensing, done }

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
  String? _lastTagId;
  DateTime? _lastNfcScan;

  late AppStrings _strings;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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
    _openPort();
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
    dev.log('NFC: startSession — state=$_state item=${_selectedItem?.slot}',
        name: 'EdgeShop.NFC');
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final now = DateTime.now();
        final techs = tag.data.keys.toList();
        dev.log('NFC: tag discovered — techs=$techs state=$_state',
            name: 'EdgeShop.NFC');

        if (_lastNfcScan != null &&
            now.difference(_lastNfcScan!) < const Duration(seconds: 1)) {
          dev.log('NFC: debounced (too fast)', name: 'EdgeShop.NFC');
          return;
        }
        _lastNfcScan = now;

        final tagId = _extractTagId(tag);
        dev.log('NFC: tag ID = $tagId', name: 'EdgeShop.NFC');

        if (_state == _VendingState.waitingPayment) {
          dev.log('NFC: accepting tag for payment', name: 'EdgeShop.NFC');
          await _onPaymentTagScanned(tagId);
        } else {
          dev.log('NFC: tag ignored — wrong state ($_state)',
              name: 'EdgeShop.NFC');
        }
      },
      onError: (e) async {
        dev.log('NFC: session error — ${e.message} (type=${e.type})',
            name: 'EdgeShop.NFC', level: 1000);
        if (mounted && _state != _VendingState.idle) {
          setState(() => _state = _VendingState.idle);
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
          dev.log('NFC: identifier found in tech "${entry.key}" → $hex',
              name: 'EdgeShop.NFC');
          return hex;
        }
      }
    }
    dev.log(
        'NFC: no identifier found in any tech — data keys: ${tag.data.keys}',
        name: 'EdgeShop.NFC',
        level: 900);
    return 'UNKNOWN';
  }

  // ── Vending flow ──────────────────────────────────────────────────────────

  void _selectItem(VendingItem item) {
    setState(() {
      _selectedItem = item;
      _state = _VendingState.waitingPayment;
      _lastNfcScan = null;
    });
    _startNfcSession();
  }

  Future<void> _onPaymentTagScanned(String tagId) async {
    if (_state != _VendingState.waitingPayment || _selectedItem == null) return;
    dev.log(
        'NFC: payment accepted — tag=$tagId slot=${_selectedItem!.slot} gpio=${_selectedItem!.gpioChannel}',
        name: 'EdgeShop.NFC');
    await NfcManager.instance.stopSession();
    dev.log('NFC: session stopped', name: 'EdgeShop.NFC');
    setState(() {
      _lastTagId = tagId;
      _state = _VendingState.dispensing;
    });
    await _openGpio(_selectedItem!.gpioChannel);
    dev.log('GPIO: channel ${_selectedItem!.gpioChannel} OPENED',
        name: 'EdgeShop.GPIO');
  }

  Future<void> _closeSlot() async {
    debugPrint('_closeSlot called — state=$_state item=${_selectedItem?.slot}');
    if (_state != _VendingState.dispensing || _selectedItem == null) return;
    dev.log('GPIO: closing channel ${_selectedItem!.gpioChannel}',
        name: 'EdgeShop.GPIO');
    await _closeGpio(_selectedItem!.gpioChannel);
    dev.log('GPIO: channel ${_selectedItem!.gpioChannel} CLOSED',
        name: 'EdgeShop.GPIO');
    setState(() => _state = _VendingState.done);
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() {
        _state = _VendingState.idle;
        _selectedItem = null;
        _lastTagId = null;
        _lastNfcScan = null;
      });
    }
  }

  Future<void> _cancelSelection() async {
    dev.log('NFC: cancel — stopping session, state=$_state',
        name: 'EdgeShop.NFC');
    if (_selectedItem != null) {
      await _closeGpio(_selectedItem!.gpioChannel);
    }
    await NfcManager.instance.stopSession();
    setState(() {
      _state = _VendingState.idle;
      _selectedItem = null;
      _lastNfcScan = null;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          if (_state == _VendingState.idle) SafeArea(child: _buildProductGrid()),
          if (_state == _VendingState.waitingPayment) _buildPaymentScreen(),
          if (_state == _VendingState.dispensing) _buildDispensingScreen(),
          if (_state == _VendingState.done) _buildSuccessScreen(),
          // Edge logo always at bottom — IgnorePointer so it never eats taps
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: IgnorePointer(child: _buildEdgeLogo()),
          ),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    return LayoutBuilder(builder: (context, constraints) {
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
    });
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
    return Center(
      child: SvgPicture.asset(
        'assets/edge.svg',
        height: 32,
        colorFilter: ColorFilter.mode(
          Colors.white.withValues(alpha: 0.7),
          BlendMode.srcIn,
        ),
      ),
    );
  }

  // ── Gift selection screen (idle) ───────────────────────────────────────────

  Widget _buildProductGrid() {
    return Column(
      children: [
        // Status row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                Icons.circle,
                size: 7,
                color: _portOpen ? const Color(0xFF00FF88) : Colors.orange,
              ),
              const SizedBox(width: 5),
              Text(
                _portOpen ? _strings.ready : _strings.connecting,
                style: TextStyle(
                  color: _portOpen ? const Color(0xFF00FF88) : Colors.orange,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: Colors.white24, size: 20),
                onPressed: () => Navigator.of(context).pushNamed('/debug'),
                tooltip: 'Debug tools',
              ),
            ],
          ),
        ),
        // Title
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 20),
          child: Text(
            'Choose your gift',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // 2×2 grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildProductCard(vendingItems[0])),
                      const SizedBox(width: 16),
                      Expanded(child: _buildProductCard(vendingItems[1])),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildProductCard(vendingItems[2])),
                      const SizedBox(width: 16),
                      Expanded(child: _buildProductCard(vendingItems[3])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 56), // space above logo
      ],
    );
  }

  Widget _buildProductCard(VendingItem item) {
    return GestureDetector(
      onTap: () => _selectItem(item),
      child: Container(
        decoration: BoxDecoration(
          color: _cardDefaultBg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: Colors.white, size: 60),
            const SizedBox(height: 14),
            Text(
              _strings.giftNames[item.giftIndex - 1],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
                fontSize: 26,
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

  // ── Dispensing screen ──────────────────────────────────────────────────────

  Widget _buildDispensingScreen() {
    final item = _selectedItem!;
    const green = Color(0xFF00FF88);
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, _) => Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: green.withValues(alpha: 0.12),
                              border: Border.all(color: green, width: 2),
                            ),
                            child: const Icon(Icons.check, color: green, size: 40),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _strings.paymentConfirmed,
                        style: const TextStyle(color: green, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _strings.giftNames[item.giftIndex - 1],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Slot ${item.slot} • GPIO ${item.gpioChannel + 1} is OPEN',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                      if (_lastTagId != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Card: $_lastTagId',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _strings.takeItemToClose,
                      style: const TextStyle(color: Colors.white60, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _closeSlot,
                      icon: const Icon(Icons.lock_outline, size: 24),
                      label: Text(_strings.closeSlot.replaceAll('\n', ' ')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _nfcIconBg,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(160, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                          side: const BorderSide(color: Colors.white54, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),
            ],
          ),
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
            const Icon(
              Icons.task_alt,
              color: _successGreen,
              size: 130,
            ),
            const SizedBox(height: 36),
            const Text(
              'Enjoy your gift!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Thank you for your participation.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}
