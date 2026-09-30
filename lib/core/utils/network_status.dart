import 'dart:async';
import 'dart:io';

/// Quick, dependency-free "is there internet right now" probe — a real DNS
/// lookup (short-circuited by a timeout), not just the device's Wi-Fi/mobile
/// radio state, which can report "connected" to a network with no actual
/// route to the internet.
class NetworkStatus {
  static Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
