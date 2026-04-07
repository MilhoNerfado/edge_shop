import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcReaderPage extends StatefulWidget {
  const NfcReaderPage({super.key});

  @override
  State<NfcReaderPage> createState() => _NfcReaderPageState();
}

class _NfcReaderPageState extends State<NfcReaderPage> {
  bool _nfcAvailable = false;
  bool _scanning = false;

  final List<_NfcLogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  @override
  void dispose() {
    if (_scanning) NfcManager.instance.stopSession();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkNfc() async {
    final available = await NfcManager.instance.isAvailable();
    setState(() => _nfcAvailable = available);
    _log(
      available ? 'NFC is available on this device.' : 'NFC is not available.',
      available ? _LogLevel.success : _LogLevel.error,
    );
  }

  void _log(String message, _LogLevel level) {
    setState(() => _logs.add(_NfcLogEntry(message, level)));
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

  Future<void> _startScan() async {
    if (!_nfcAvailable || _scanning) return;
    setState(() => _scanning = true);
    _log('Waiting for NFC tag...', _LogLevel.info);

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        _log('── Tag detected ──', _LogLevel.info);
        _parseTag(tag);
      },
      onError: (e) async {
        _log('Session error: $e', _LogLevel.error);
        setState(() => _scanning = false);
      },
    );
  }

  Future<void> _stopScan() async {
    if (!_scanning) return;
    await NfcManager.instance.stopSession();
    setState(() => _scanning = false);
    _log('Scan stopped.', _LogLevel.info);
  }

  void _parseTag(NfcTag tag) {
    final data = tag.data;

    // ── Tag ID ──
    final id = _extractId(data);
    if (id != null) {
      _log('ID: ${_bytesToHex(id)}', _LogLevel.success);
    }

    // ── Tech list ──
    final techs = data.keys.toList();
    _log('Techs: ${techs.join(', ')}', _LogLevel.info);

    // ── NDEF ──
    final ndef = Ndef.from(tag);
    if (ndef != null) {
      _log(
        'NDEF: ${ndef.additionalData['isWritable'] == true ? 'writable' : 'read-only'}'
        ', capacity: ${ndef.additionalData['maxSize']} bytes'
        ', type: ${ndef.additionalData['type'] ?? 'unknown'}',
        _LogLevel.info,
      );

      final cachedMessage = ndef.cachedMessage;
      if (cachedMessage != null && cachedMessage.records.isNotEmpty) {
        for (int i = 0; i < cachedMessage.records.length; i++) {
          _parseNdefRecord(i, cachedMessage.records[i]);
        }
      } else {
        _log('NDEF message is empty.', _LogLevel.info);
      }
    } else {
      _log('No NDEF data found on tag.', _LogLevel.info);
    }
  }

  void _parseNdefRecord(int index, NdefRecord record) {
    final tnf = record.typeNameFormat;
    final type = record.type;
    final payload = record.payload;

    final typeStr = String.fromCharCodes(type);
    _log('Record[$index] TNF: ${_tnfName(tnf)}, type: $typeStr', _LogLevel.info);

    // Well-known Text (TNF=1, type=T)
    if (tnf == NdefTypeNameFormat.nfcWellknown && typeStr == 'T') {
      _log('  Text: ${_decodeTextRecord(payload)}', _LogLevel.success);
      return;
    }

    // Well-known URI (TNF=1, type=U)
    if (tnf == NdefTypeNameFormat.nfcWellknown && typeStr == 'U') {
      _log('  URI: ${_decodeUriRecord(payload)}', _LogLevel.success);
      return;
    }

    // MIME type (TNF=2)
    if (tnf == NdefTypeNameFormat.media) {
      _log('  MIME payload: ${String.fromCharCodes(payload)}', _LogLevel.success);
      return;
    }

    // Fallback: raw hex
    _log('  Payload (hex): ${_bytesToHex(payload)}', _LogLevel.success);
  }

  // ── Helpers ──

  Uint8List? _extractId(Map<String, dynamic> data) {
    for (final tech in data.values) {
      if (tech is Map) {
        final id = tech['identifier'];
        if (id is Uint8List) return id;
      }
    }
    return null;
  }

  String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

  String _tnfName(NdefTypeNameFormat tnf) {
    switch (tnf) {
      case NdefTypeNameFormat.empty:
        return 'Empty';
      case NdefTypeNameFormat.nfcWellknown:
        return 'Well-Known';
      case NdefTypeNameFormat.media:
        return 'MIME';
      case NdefTypeNameFormat.absoluteUri:
        return 'Absolute URI';
      case NdefTypeNameFormat.nfcExternal:
        return 'External';
      case NdefTypeNameFormat.unknown:
        return 'Unknown';
      case NdefTypeNameFormat.unchanged:
        return 'Unchanged';
    }
  }

  /// NDEF Text record: [status byte][lang][text]
  String _decodeTextRecord(Uint8List payload) {
    if (payload.isEmpty) return '';
    final langLen = payload[0] & 0x3F;
    return String.fromCharCodes(payload.sublist(1 + langLen));
  }

  /// NDEF URI record: [prefix byte][uri]
  String _decodeUriRecord(Uint8List payload) {
    const prefixes = [
      '', 'http://www.', 'https://www.', 'http://', 'https://',
      'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.',
      'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
      'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:',
      'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://',
      'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:',
      'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
    ];
    if (payload.isEmpty) return '';
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    return prefix + String.fromCharCodes(payload.sublist(1));
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

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}.'
      '${dt.millisecond.toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Reader'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: _scanning ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  _scanning ? 'Scanning' : 'Idle',
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
          // ── Controls ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (!_nfcAvailable || _scanning) ? null : _startScan,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Start Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? _stopScan : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Card(
                color: Colors.deepPurple.shade900,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.nfc, size: 32),
                      SizedBox(width: 12),
                      Text(
                        'Hold a tag near the device',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const Divider(height: 1),

          // ── Log header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Tag Log',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${_logs.length} entries',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _logs.clear()),
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
                'No tags scanned yet.\nPress Start Scan and hold an NFC tag near the device.',
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

          if (_scanning) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

enum _LogLevel { info, success, error }

class _NfcLogEntry {
  final DateTime timestamp;
  final String message;
  final _LogLevel level;

  _NfcLogEntry(this.message, this.level) : timestamp = DateTime.now();
}
