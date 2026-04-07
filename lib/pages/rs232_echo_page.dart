import 'package:flutter/material.dart';
import '../services/uart_service.dart';

/// Log entry for the RS-232 debug log panel.
class _LogEntry {
  final DateTime timestamp;
  final String message;
  final _LogLevel level;

  _LogEntry(this.message, this.level) : timestamp = DateTime.now();
}

enum _LogLevel { info, success, error }

/// RS-232 Echo Test page.
///
/// Provides controls to open/close the UART port, send text,
/// read echoed data, and view a scrollable timestamped debug log.
class RS232EchoPage extends StatefulWidget {
  const RS232EchoPage({super.key});

  @override
  State<RS232EchoPage> createState() => _RS232EchoPageState();
}

class _RS232EchoPageState extends State<RS232EchoPage> {
  final UartChannelService _uart = UartChannelService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_LogEntry> _logs = [];

  bool _portOpen = false;
  bool _busy = false;

  // ── Logging ──

  void _log(String message, _LogLevel level) {
    setState(() {
      _logs.add(_LogEntry(message, level));
    });
    // Auto-scroll to bottom after frame renders
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

  // ── UART operations ──

  Future<void> _openPort() async {
    setState(() => _busy = true);
    _log('Opening RS-232 port (ttyHS1, 9600/8N1)...', _LogLevel.info);

    final result = await _uart.open();
    final success = result['success'] as bool;
    final message = result['message'] as String;

    if (success) {
      _portOpen = true;
      _log(message, _LogLevel.success);
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

  Future<void> _sendData() async {
    final data = _inputController.text;
    if (data.isEmpty) {
      _log('Nothing to send — enter some text first', _LogLevel.error);
      return;
    }

    setState(() => _busy = true);
    _log('Sending ${data.length} bytes: "$data"', _LogLevel.info);

    final result = await _uart.write(data);
    final success = result['success'] as bool;
    final message = result['message'] as String;

    if (success) {
      _log(message, _LogLevel.success);
    } else {
      _log('WRITE FAILED: $message', _LogLevel.error);
    }
    setState(() => _busy = false);
  }

  Future<void> _readData() async {
    setState(() => _busy = true);
    _log('Reading from RS-232 port (max 256 bytes)...', _LogLevel.info);

    final result = await _uart.read(maxLen: 256);
    final success = result['success'] as bool;
    final message = result['message'] as String;

    if (success) {
      final data = result['data'] as String? ?? '';
      final bytesRead = result['bytesRead'] as int? ?? 0;
      if (data.isEmpty) {
        _log('Read completed — no data received (0 bytes)', _LogLevel.info);
      } else {
        _log('Received $bytesRead bytes: "$data"', _LogLevel.success);
      }
    } else {
      _log('READ FAILED: $message', _LogLevel.error);
    }
    setState(() => _busy = false);
  }

  /// Convenience: write then immediately read (echo test).
  Future<void> _echoTest() async {
    await _sendData();
    // Small delay to let data traverse the loopback
    await Future.delayed(const Duration(milliseconds: 100));
    await _readData();
  }

  void _clearLog() {
    setState(() => _logs.clear());
  }

  // ── UI ──

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
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RS-232 Echo Test'),
        actions: [
          // Connection status indicator
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
      body: Column(
        children: [
          // ── Connection controls ──
          Padding(
            padding: const EdgeInsets.all(12),
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

          // ── Data input + send ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    labelText: 'Data to send',
                    hintText: 'Enter text to echo...',
                    border: OutlineInputBorder(),
                  ),
                  enabled: _portOpen && !_busy,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy || !_portOpen ? null : _sendData,
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy || !_portOpen ? null : _readData,
                        icon: const Icon(Icons.download),
                        label: const Text('Read'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy || !_portOpen ? null : _echoTest,
                        icon: const Icon(Icons.repeat),
                        label: const Text('Echo Test'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
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
                const Text(
                  'Debug Log',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

          // ── Scrollable log panel ──
          Expanded(
            child: Container(
              color: Colors.grey.shade900,
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No log entries yet.\nOpen the port and send some data!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final entry = _logs[index];
                        final color = _colorForLevel(entry.level);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _iconForLevel(entry.level),
                                size: 14,
                                color: color,
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
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),

          // ── Loading indicator ──
          if (_busy)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
