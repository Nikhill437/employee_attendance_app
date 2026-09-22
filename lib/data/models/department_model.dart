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

/// A task within a department, as cached locally from the backend's
/// `POST attendance/list_task` response. Field names/envelope aren't
/// confirmed yet (unlike Department, whose shape is confirmed against the
/// real `searchDept` response) — adjust [fromRemote] once they are.
class Task {
  final int id;
  final int departmentId;
  final String name;

  const Task({required this.id, required this.departmentId, required this.name});

  factory Task.fromRemote(Map<String, dynamic> json) {
    return Task(
      id: _asInt(json['task_id'] ?? json['id']),
      departmentId: _asInt(json['department_id']),
      name: (json['task_name'] ?? json['name']).toString(),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException('Expected an int id, got $value (${value.runtimeType})');
}
