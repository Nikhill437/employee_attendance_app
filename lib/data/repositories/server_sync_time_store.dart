import 'package:shared_preferences/shared_preferences.dart';

/// A UTC server-time checkpoint kept in SharedPreferences under [_key].
///
/// Each feature that does incremental server fetches owns its own key, so
/// one feature's checkpoint never moves another's.
class ServerSyncTimeStore {
  final String _key;

  const ServerSyncTimeStore(this._key);

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> save(String serverTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, serverTime);
  }
}
