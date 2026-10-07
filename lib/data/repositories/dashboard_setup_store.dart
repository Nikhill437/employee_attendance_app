import 'package:shared_preferences/shared_preferences.dart';

/// How many of the dashboard's first-time setup steps have succeeded, in
/// order: 1 Worker List, 2 Worker Tasks, 3 Employee Attendance. Stored in
/// SharedPreferences, so it survives restarts. Once all three are done the
/// steps are no longer gated.
class DashboardSetupStore {
  static const int stepCount = 3;
  static const String _key = 'dashboard_setup_completed_steps';

  Future<int> completedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  /// Records [step] as done. Only moves the count forward, so re-running an
  /// earlier step never undoes later progress.
  Future<void> markCompleted(int step) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key) ?? 0;
    if (step > current) await prefs.setInt(_key, step);
  }
}
