import 'package:flutter/services.dart';

/// Dart client for the native UART platform channel.
///
/// Communicates with [UartService] on the Android side via
/// MethodChannel `com.example.edge_shop/uart`.
class UartChannelService {
  static const _channel = MethodChannel('com.example.edge_shop/uart');

  /// Opens the RS-232 UART port (ttyHS1) with default 9600/8N1 config.
  Future<Map<String, dynamic>> open() async {
    try {
      final result = await _channel.invokeMethod('uartOpen');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'PlatformException: ${e.message} (${e.code})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Closes the RS-232 UART port.
  Future<Map<String, dynamic>> close() async {
    try {
      final result = await _channel.invokeMethod('uartClose');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'PlatformException: ${e.message} (${e.code})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  /// Writes [data] string to the RS-232 port.
  Future<Map<String, dynamic>> write(String data) async {
    try {
      final result = await _channel.invokeMethod('uartWrite', {'data': data});
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'PlatformException: ${e.message} (${e.code})',
        'bytesWritten': 0,
      };
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e', 'bytesWritten': 0};
    }
  }

  /// Reads up to [maxLen] characters from the RS-232 port.
  Future<Map<String, dynamic>> read({int maxLen = 256}) async {
    try {
      final result = await _channel.invokeMethod('uartRead', {'maxLen': maxLen});
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': 'PlatformException: ${e.message} (${e.code})',
        'data': '',
        'bytesRead': 0,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error: $e',
        'data': '',
        'bytesRead': 0,
      };
    }
  }
}
