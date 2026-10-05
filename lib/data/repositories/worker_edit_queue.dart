import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Field-level changes made to a worker's enrollment since their last
/// successful sync, keyed by local `offline_worker_id`. Kept outside the
/// database so `workers` needs no extra column — a later sync sends only
/// these fields (plus the backend's worker_id), then clears them.
class WorkerEditQueue {
  static const String _key = 'worker_pending_edits';

  Future<Map<String, Map<String, String>>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        entry.key: Map<String, String>.from(entry.value as Map),
    };
  }

  Future<void> _writeAll(Map<String, Map<String, String>> all) async {
    final prefs = await SharedPreferences.getInstance();
    if (all.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(all));
    }
  }

  /// The pending field changes for [offlineWorkerId] — empty if none.
  Future<Map<String, String>> pendingFor(int offlineWorkerId) async {
    final all = await _readAll();
    return all[offlineWorkerId.toString()] ?? {};
  }

  /// Merges [changes] into what's already pending for [offlineWorkerId] —
  /// a later edit to the same field replaces the earlier one.
  Future<void> record(int offlineWorkerId, Map<String, String> changes) async {
    if (changes.isEmpty) return;
    final all = await _readAll();
    final key = offlineWorkerId.toString();
    all[key] = {...?all[key], ...changes};
    await _writeAll(all);
  }

  /// Clears everything pending for [offlineWorkerId] — call only after the
  /// backend has confirmed the sync.
  Future<void> clear(int offlineWorkerId) async {
    final all = await _readAll();
    if (all.remove(offlineWorkerId.toString()) != null) {
      await _writeAll(all);
    }
  }
}
