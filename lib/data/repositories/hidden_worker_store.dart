import 'package:shared_preferences/shared_preferences.dart';

/// Local ids of workers whose department change has synced to the server.
/// The worker list leaves them out of its display. The rows stay in the
/// `workers` table, and nothing is deleted.
class HiddenWorkerStore {
  static const String _key = 'workers_hidden_after_department_change';

  Future<Set<int>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key) ?? const <String>[];
    return {
      for (final value in values)
        if (int.tryParse(value) != null) int.parse(value),
    };
  }

  Future<void> add(int offlineWorkerId) async {
    final prefs = await SharedPreferences.getInstance();
    final values = {
      ...(prefs.getStringList(_key) ?? const <String>[]),
      '$offlineWorkerId',
    };
    await prefs.setStringList(_key, values.toList());
  }
}
