import 'package:flutter/material.dart';
import '../services/uart_service.dart';

/// Controls 4 Arduino GPIO pins over RS-232 using a single-byte bitfield.
///
/// The master sends one byte where bits 0-3 map to pins 2-5.
/// The Arduino echoes the applied state byte back as ACK.
class GpioControlPage extends StatefulWidget {
  const GpioControlPage({super.key});

  @override
  State<GpioControlPage> createState() => _GpioControlPageState();
}

class _GpioControlPageState extends State<GpioControlPage>
    with WidgetsBindingObserver {
  final UartChannelService _uart = UartChannelService();

  bool _portOpen = false;
  bool _busy = false;

  /// Current bitfield state (bits 0-3 → GPIOs 1-4).
  int _stateBits = 0x00;

  final List<_LogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();

  static const int _numChannels = 4;
  static const List<String> _channelLabels = [
    'GPIO 1 (pin 2)',
    'GPIO 2 (pin 3)',
    'GPIO 3 (pin 4)',
    'GPIO 4 (pin 5)',
  ];

  bool _bitOn(int bit) => (_stateBits >> bit) & 1 == 1;

  int _withBit(int bits, int bit, bool on) {
    if (on) {
      return bits | (1 << bit);
    } else {
      return bits & ~(1 << bit);
    }
  }

  // ── Logging ──

  void _log(String message, _LogLevel level) {
    setState(() => _logs.add(_LogEntry(message, level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _bitsToString(int bits) =>
      bits.toRadixString(2).padLeft(_numChannels, '0');

  // ── UART operations ──

  Future<void> _openPort() async {
    setState(() => _busy = true);
    _log('Opening RS-232 port...', _LogLevel.info);

    final result = await _uart.open();
    final success = result['success'] as bool;
    final message = result['message'] as String;

    if (success) {
      _portOpen = true;
      _log(message, _LogLevel.success);
      // Give Arduino reset time, then push current (all-off) state
      await Future.delayed(const Duration(milliseconds: 500));
      await _pushState(0x00);
    } else {
      _log('OPEN FAILED: $message', _LogLevel.error);
    }
    setState(() => _busy = false);
  }

  Future<void> _closePort() async {
    setState(() => _busy = true);
    _log('Closing RS-232 port...', _LogLevel.info);

    final result = await _uart.close();
    final success = result['success'] as bool;
    final message = result['message'] as String;

    if (success) {
      _portOpen = false;
      _log(message, _LogLevel.success);
    } else {
      _log('CLOSE FAILED: $message', _LogLevel.error);
    }
    setState(() => _busy = false);
  }

  /// Send the bitfield as `"0xHH\n"` — fire-and-forget, no ACK expected.
  Future<bool> _pushState(int bits) async {
    bits &= 0x0F;
    final hexStr = '0x${bits.toRadixString(16).padLeft(2, '0')}\n';
    _log('TX: ${hexStr.trim()} (${_bitsToString(bits)})', _LogLevel.info);

    final writeResult = await _uart.write(hexStr);
    if (!(writeResult['success'] as bool)) {
      _log('WRITE FAILED: ${writeResult['message']}', _LogLevel.error);
      return false;
    }

    setState(() => _stateBits = bits);
    return true;
  }

  /// Toggle a single GPIO channel.
  Future<void> _toggleGpio(int channel) async {
    if (!_portOpen || _busy) return;
    setState(() => _busy = true);
    final newBits = _withBit(_stateBits, channel, !_bitOn(channel));
    await _pushState(newBits);
    setState(() => _busy = false);
  }

  /// Set a specific GPIO channel.
  Future<void> _setGpio(int channel, bool on) async {
    if (!_portOpen || _busy) return;
    setState(() => _busy = true);
    final newBits = _withBit(_stateBits, channel, on);
    await _pushState(newBits);
    setState(() => _busy = false);
  }

  Future<void> _allOn() async {
    if (!_portOpen || _busy) return;
    setState(() => _busy = true);
    await _pushState(0x0F);
    setState(() => _busy = false);
  }

  Future<void> _allOff() async {
    if (!_portOpen || _busy) return;
    setState(() => _busy = true);
    await _pushState(0x00);
    setState(() => _busy = false);
  }

  void _clearLog() => setState(() => _logs.clear());

  // ── UI helpers ──

  Color _colorForLevel(_LogLevel level) {
    switch (level) {
      case _LogLevel.info:
        return Colors.blue;
      case _LogLevel.success:
        return Colors.green;
      case _LogLevel.error:
        return Colors.red;
    }
  }

  IconData _iconForLevel(_LogLevel level) {
    switch (level) {
      case _LogLevel.info:
        return Icons.info_outline;
      case _LogLevel.success:
        return Icons.check_circle_outline;
      case _LogLevel.error:
        return Icons.error_outline;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Close the port when the app is backgrounded, paused, or detached
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_portOpen) {
        _uart.close();
        _portOpen = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_portOpen) {
      _uart.close();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPIO Control'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: _portOpen ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _portOpen ? 'Connected' : 'Disconnected',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          // ── Connection controls ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy || _portOpen ? null : _openPort,
                    icon: const Icon(Icons.power),
                    label: const Text('Open Port'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy || !_portOpen ? null : _closePort,
                    icon: const Icon(Icons.power_off),
                    label: const Text('Close Port'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── GPIO toggle cards ──
          for (int i = 0; i < _numChannels; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    _bitOn(i) ? Icons.lightbulb : Icons.lightbulb_outline,
                    color: _bitOn(i) ? Colors.amber : Colors.grey,
                    size: 28,
                  ),
                  title: Text(_channelLabels[i]),
                  subtitle: Text(_bitOn(i) ? 'HIGH' : 'LOW'),
                  trailing: Switch(
                    value: _bitOn(i),
                    onChanged: _portOpen && !_busy
                        ? (val) => _setGpio(i, val)
                        : null,
                  ),
                  onTap: _portOpen && !_busy
                      ? () => _toggleGpio(i)
                      : null,
                ),
              ),
            ),

          // ── Bulk actions ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _portOpen && !_busy ? _allOn : null,
                    icon: const Icon(Icons.flash_on, size: 18),
                    label: const Text('All ON'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _portOpen && !_busy ? _allOff : null,
                    icon: const Icon(Icons.flash_off, size: 18),
                    label: const Text('All OFF'),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Log header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 18),
                const SizedBox(width: 6),
                Text(
                  'State: ${_bitsToString(_stateBits)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  '${_logs.length} entries',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _clearLog,
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  tooltip: 'Clear log',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // ── Log entries ──
          if (_logs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No log entries yet.\nOpen the port to start controlling GPIOs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            for (final entry in _logs)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _iconForLevel(entry.level),
                      size: 14,
                      color: _colorForLevel(entry.level),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '[${_formatTime(entry.timestamp)}] ',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _colorForLevel(entry.level),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

          if (_busy)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

// ── Log model ──

enum _LogLevel { info, success, error }

class _LogEntry {
  final DateTime timestamp;
  final String message;
  final _LogLevel level;

  _LogEntry(this.message, this.level) : timestamp = DateTime.now();
}
