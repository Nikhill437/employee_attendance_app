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

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// The Task download's stored server time. Sent as `date` to the task
/// count and task data calls, and saved only after tasks are stored.
const ServerSyncTimeStore lastTaskServerTime = ServerSyncTimeStore(
  'last_task_server_time',
);

/// The Department download's stored server time, kept separate from
/// [lastTaskServerTime] and handled the same way.
const ServerSyncTimeStore lastDepartmentServerTime = ServerSyncTimeStore(
  'last_department_server_time',
);

/// The Employee Attendance button's last successful call time, sent as
/// `date` on the next incremental call. Saved only after the rows are stored.
const ServerSyncTimeStore lastDepartmentAttendanceCallTime =
    ServerSyncTimeStore('last_department_attendance_call_time');

/// The Worker Tasks download's stored server time. Kept separate from the
/// Worker List time. Saved only after tasks are stored locally.
const ServerSyncTimeStore lastWorkerTaskServerTime = ServerSyncTimeStore(
  'last_worker_task_server_time',
);
