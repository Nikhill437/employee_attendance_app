/// A department, as cached locally from the backend's
/// `POST attendance/searchDept` response (`{"data": [{"department_id":
/// ..., "department_name": ...}, ...]}`) and re-read from the local
/// `departments` table for the enrollment form's dropdown.
class Department {
  final int id;
  final String name;

  const Department({required this.id, required this.name});

  factory Department.fromRemote(Map<String, dynamic> json) {
    return Department(
      id: _asInt(json['department_id'] ?? json['id']),
      name: (json['department_name'] ?? json['name']).toString(),
    );
  }

  factory Department.fromMap(Map<String, dynamic> map) {
    return Department(
      id: map['department_id'] as int,
      name: map['department_name'] as String,
    );
  }

  // Equality by id — DropdownButtonFormField compares its current value
  // against its item list by ==, and both are expected to come from the
  // same cached list, but this keeps that safe even if they don't.
  @override
  bool operator ==(Object other) => other is Department && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How a task is worked/paid — a property of the task catalog itself
/// (`tasks.task_type`), carried along automatically whenever that task is
/// picked (enrollment_form_screen.dart, assign_task_screen.dart). Replaces
/// the old per-worker `PayType` that used to be chosen separately on the
/// enrollment form (`workers.enrollment_type`), with `shiftBased` dropped
/// and `hourBased` added.
enum TaskType {
  daily('Daily'),
  monthly('Monthly'),
  taskBased('Task Based'),
  hourBased('Hour Based');

  const TaskType(this.label);

  final String label;
}

TaskType? _taskTypeOrNull(dynamic value) {
  if (value == null) return null;
  final raw = value.toString();
  for (final type in TaskType.values) {
    if (type.name.toLowerCase() == raw.toLowerCase()) return type;
  }
  return null;
}

/// A task within a department, as cached locally from the backend's
/// `POST attendance/list_task` response. Field names/envelope aren't
/// confirmed yet (unlike Department, whose shape is confirmed against the
/// real `searchDept` response) — adjust [fromRemote] once they are.
class Task {
  final int id;
  final int departmentId;
  final String name;

  /// A per-task daily quantity goal and hourly/piece rate — both
  /// backend-defined and read-only here, null when the backend hasn't set
  /// one. Shown alongside the task wherever it's picked or already
  /// assigned (enrollment_form_screen.dart, assign_task_screen.dart) —
  /// hidden rather than shown as blank/zero when either is null.
  final int? target;
  final int? rate;

  /// See [TaskType] — null when the backend hasn't set one.
  final TaskType? taskType;

  /// The scheduled clock time for an [TaskType.hourBased] task
  /// (`tasks.working_hours`) — "HH:mm", 24-hour. Null for every other
  /// task type, or when the backend hasn't set one.
  final String? workingHours;

  const Task({
    required this.id,
    required this.departmentId,
    required this.name,
    this.target,
    this.rate,
    this.taskType,
    this.workingHours,
  });

  factory Task.fromRemote(Map<String, dynamic> json) {
    return Task(
      id: _asInt(json['task_id'] ?? json['id']),
      departmentId: _asInt(json['department_id']),
      name: (json['task_name'] ?? json['name']).toString(),
      target: _asIntOrNull(json['target']),
      rate: _asIntOrNull(json['rate']),
      taskType: _taskTypeOrNull(json['task_type']),
      workingHours: json['working_hours'] as String?,
    );
  }

  /// Reads back a local `tasks` row (see DatabaseHelper.getTasksByDepartment).
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['task_id'] as int,
      departmentId: map['department_id'] as int,
      name: map['task_name'] as String,
      target: map['target'] as int?,
      rate: map['rate'] as int?,
      taskType: _taskTypeOrNull(map['task_type']),
      workingHours: map['working_hours'] as String?,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException(
    'Expected an int id, got $value (${value.runtimeType})',
  );
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
