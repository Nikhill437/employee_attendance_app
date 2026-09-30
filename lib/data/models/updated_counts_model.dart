/// How many worker/department/task records have changed on the server —
/// from `POST attendance/updated-counts` (see UpdatedCountsApi) — shown as
/// badges on the dashboard so a supervisor knows there's something worth
/// tapping Refresh/Fetch for, without having to guess.
class UpdatedCounts {
  final int workerCount;
  final int departmentCount;
  final int taskCount;

  const UpdatedCounts({
    required this.workerCount,
    required this.departmentCount,
    required this.taskCount,
  });

  static const zero = UpdatedCounts(
    workerCount: 0,
    departmentCount: 0,
    taskCount: 0,
  );

  factory UpdatedCounts.fromJson(Map<String, dynamic> json) {
    return UpdatedCounts(
      workerCount: (json['worker_count'] as num?)?.toInt() ?? 0,
      departmentCount: (json['department_count'] as num?)?.toInt() ?? 0,
      taskCount: (json['task_count'] as num?)?.toInt() ?? 0,
    );
  }
}
