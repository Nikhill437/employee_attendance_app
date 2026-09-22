/// Backend API endpoint paths, centralized the same way `AppRoutes`
/// centralizes in-app navigation routes — so a path only needs correcting
/// in one place (as `list_department` already needed, once corrected to
/// the real `searchDept`).
class ApiRoutes {
  const ApiRoutes._();

  static const String login = '/auth/verifyUser';
  static const String listDepartments = 'attendance/searchDept';
  static const String listTasks = 'attendance/list_task';
  static const String syncWorker = '/attendance/sync-worker';
}
