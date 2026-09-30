/// Backend API endpoint paths, centralized the same way `AppRoutes`
/// centralizes in-app navigation routes — so a path only needs correcting
/// in one place (as `list_department` already needed, once corrected to
/// the real `searchDept`).
class ApiRoutes {
  const ApiRoutes._();

  static const String login = '/auth/verifyUser';
  static const String listDepartments = '/attendance/searchDept';
  static const String serverTimeDepartment = 'attendance/department_data';
  static const String deptTasks = '/attendance/dept_task';
  static const String serverTimeTasks = '/attendance/task_data';
  static const String syncWorker = '/attendance/sync-worker';
  static const String serverTimeWorkers = '/attendance/worker_data';
  static const String workerList = '/attendance/list';
  static const String count = '/attendance/updated-counts';
  static const String assignTask = '/attendance/assigntask';
  static const String checkIn = '/attendance/check-in';
  static const String workerTaskCompletion =
      '/attendance/worker-task-completion';
  static const String submitAttendance = '/attendance/submit-attendance';
}
