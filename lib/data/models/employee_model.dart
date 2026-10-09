import 'dart:convert';

import 'department_model.dart';
import 'worker_model.dart';

class Employee {
  final int? id;
  final String name;
  final String number;
  final String employeeId;
  final String attendanceTime;
  final bool faceVerified;

  /// One embedding per enrolled pose (front/left/right/up/down), so
  /// matching can compare against whichever angle is closest to the live
  /// capture instead of a single front-on shot.
  final List<List<double>> faceEmbeddings;

  /// ISO-8601 date, or null for records enrolled before this field existed.
  final String? dateOfBirth;

  final Gender gender;
  final String? address;

  /// The department name, for display — read back from the `departments`
  /// join (see `Employee.fromMap`), or set directly right after enrollment
  /// from whatever the dropdown selection was.
  final String? department;

  /// FK into the local `departments` table (mirrors the backend's
  /// `workers.department_id`). Required to actually persist a worker — null
  /// only transiently, before the enrollment form's department dropdown has
  /// a selection.
  final int? departmentId;

  /// Local file path of the captured National ID photo (see
  /// AppImageCaptureField / EnrollmentFormViewModel), copied into permanent
  /// app storage at capture time. Required at enrollment — null only for
  /// records saved before this field existed.
  final String? nationalIdImage;

  /// Whether `POST attendance/sync-worker` has succeeded for this worker —
  /// local-only bookkeeping (see DatabaseHelper.markWorkerSynced), not
  /// something the backend's own `workers` table tracks.
  final bool isSynced;

  /// When [isSynced] was last set true — null until the first successful
  /// sync. Kept even after a later local change (check-in/out, task
  /// assignment) sets [isSynced] back to false, so "last synced at" can
  /// still be shown.
  final DateTime? syncedAt;

  /// The backend's approval status ('pending' / 'approved' / 'rejected').
  /// Only authoritative once [isSynced] is true and this row came from a
  /// real backend response (`POST attendance/list` sets the real value;
  /// `POST attendance/sync-worker` doesn't return one, so a sync-only
  /// worker keeps whatever this already was). A worker enrolled locally
  /// and never synced defaults to 'pending' — the schema's own default,
  /// not a claim about real approval — since nothing here gates on it.
  final String status;

  /// Why the backend rejected this worker, when [status] is 'rejected'.
  final String? rejectionReason;

  /// The backend's `employee_id` for this worker (`workers.employee_id`) —
  /// distinct from [employeeId] (their National ID) and from the local
  /// [id]. Only set once this worker has been imported/synced from the
  /// server (see DatabaseHelper.upsertRemoteWorkers); null otherwise. This
  /// is what the attendance login flow matches on instead of National ID
  /// (see AuthRepository).
  final int? remoteEmployeeId;

  /// The backend's own worker id (`workers.worker_id`) — null until this
  /// worker has been synced or imported. Drives the worker list's sort order.
  final int? remoteWorkerId;

  /// When this worker's enrollment details were last edited
  /// (`workers.modified_date`) — null until the first edit.
  final String? modifiedDate;

  /// The task picked on the enrollment form's Task dropdown, stored in
  /// `workers.task_id` — null if none was picked. Once this worker syncs
  /// back from the server as 'approved', [DatabaseHelper.upsertRemoteWorkers]
  /// uses this to actually assign the task in `worker_tasks`.
  final int? taskId;

  /// The assigned task's own type (`tasks.task_type`), joined in via
  /// [taskId] — null if no task is assigned yet.
  final TaskType? taskType;

  Employee({
    this.id,
    required this.name,
    required this.number,
    required this.employeeId,
    required this.attendanceTime,
    required this.faceVerified,
    required this.faceEmbeddings,
    this.dateOfBirth,
    this.gender = Gender.other,
    this.address,
    this.department,
    this.departmentId,
    this.nationalIdImage,
    this.isSynced = false,
    this.syncedAt,
    this.status = 'pending',
    this.rejectionReason,
    this.remoteEmployeeId,
    this.remoteWorkerId,
    this.modifiedDate,
    this.taskId,
    this.taskType,
  });

  Employee copyWith({
    int? id,
    String? name,
    String? number,
    String? employeeId,
    String? attendanceTime,
    bool? faceVerified,
    List<List<double>>? faceEmbeddings,
    String? dateOfBirth,
    Gender? gender,
    String? address,
    String? department,
    int? departmentId,
    String? nationalIdImage,
    bool? isSynced,
    DateTime? syncedAt,
    String? status,
    String? rejectionReason,
    int? remoteEmployeeId,
    int? remoteWorkerId,
    int? taskId,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      employeeId: employeeId ?? this.employeeId,
      attendanceTime: attendanceTime ?? this.attendanceTime,
      faceVerified: faceVerified ?? this.faceVerified,
      faceEmbeddings: faceEmbeddings ?? this.faceEmbeddings,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      address: address ?? this.address,
      department: department ?? this.department,
      departmentId: departmentId ?? this.departmentId,
      nationalIdImage: nationalIdImage ?? this.nationalIdImage,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      remoteEmployeeId: remoteEmployeeId ?? this.remoteEmployeeId,
      remoteWorkerId: remoteWorkerId ?? this.remoteWorkerId,
      taskId: taskId ?? this.taskId,
      taskType: taskType,
    );
  }

  /// Serializes to a `workers` table row (see DatabaseHelper). Throws if
  /// [departmentId] wasn't set — the enrollment form's dropdown is expected
  /// to guarantee a selection before this is ever called.
  Map<String, dynamic> toWorkerRow({
    required int createdBy,
    required String status,
  }) {
    final resolvedDepartmentId = departmentId;
    if (resolvedDepartmentId == null) {
      throw StateError(
        'Employee.departmentId is required to save a worker row',
      );
    }
    return {
      'worker_id': id,
      'full_name': name,
      'birth_date': dateOfBirth,
      'gender': gender.name,
      'national_id': employeeId,
      'national_id_image': nationalIdImage,
      'phone_number': number,
      'department_id': resolvedDepartmentId,
      'address': address,
      'face_detection': jsonEncode(faceEmbeddings),
      'status': status,
      'created_by': createdBy,
      'created_date': attendanceTime,
      'task_id': taskId,
    };
  }

  /// Reads back a `workers` row, left-joined with `departments` and `tasks`
  /// so `department` carries the name rather than just the FK id, and
  /// `taskType` carries the assigned task's own type.
  ///
  /// `id` comes from `offline_worker_id` (the always-populated local row
  /// id), not `worker_id` (the backend's real id, null until this worker's
  /// been synced or imported) — see the class doc comment above
  /// DatabaseHelper._createWorkerTables.
  factory Employee.fromMap(Map<String, dynamic> map) {
    final embeddings = _decodeEmbeddings(map['face_detection']);
    return Employee(
      id: map['offline_worker_id'] as int?,
      name: map['full_name'] as String,
      number: map['phone_number'] as String? ?? '',
      employeeId: map['national_id'] as String,
      attendanceTime: map['created_date'] as String,
      // Derived rather than a stored column: a worker row is only ever
      // created once a face has been captured (see CreateEmployeeViewModel),
      // so "has embeddings" and "verified" are the same fact.
      faceVerified: embeddings.isNotEmpty,
      faceEmbeddings: embeddings,
      dateOfBirth: map['birth_date'] as String?,
      // Records enrolled before these columns existed have null here —
      // fall back to a neutral default rather than throwing.
      gender: _enumOrDefault(Gender.values, map['gender'], Gender.other),
      address: map['address'] as String?,
      department: map['department_name'] as String?,
      departmentId: map['department_id'] as int?,
      nationalIdImage: map['national_id_image'] as String?,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      syncedAt: DateTime.tryParse((map['synced_at'] as String?) ?? ''),
      status: map['status'] as String? ?? 'pending',
      rejectionReason: map['rejection_reason'] as String?,
      remoteEmployeeId: map['employee_id'] as int?,
      remoteWorkerId: map['worker_id'] as int?,
      modifiedDate: map['modified_date'] as String?,
      taskId: map['task_id'] as int?,
      taskType: _enumOrNull(TaskType.values, map['task_type']),
    );
  }

  /// `face_detection` isn't always real embeddings — a worker imported via
  /// `POST attendance/list` (see WorkerImportRepository) can carry a
  /// non-JSON placeholder string (e.g. "embedding_data_009") rather than
  /// the actual feature vector, since the backend doesn't return real
  /// biometric data over that endpoint. Failing closed to "no embeddings"
  /// here (instead of letting jsonDecode throw) is correct either way: a
  /// worker without a real, usable face profile should read as
  /// unverified/not face-matchable, not crash the app.
  static List<List<double>> _decodeEmbeddings(Object? raw) {
    if (raw is! String) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => List<double>.from(e as List)).toList();
    } on FormatException {
      return const [];
    }
  }

  static T _enumOrDefault<T extends Enum>(
    List<T> values,
    Object? storedName,
    T fallback,
  ) {
    if (storedName is! String) return fallback;
    for (final value in values) {
      if (value.name == storedName) return value;
    }
    return fallback;
  }

  static T? _enumOrNull<T extends Enum>(List<T> values, Object? storedName) {
    if (storedName is! String) return null;
    for (final value in values) {
      if (value.name == storedName) return value;
    }
    return null;
  }
}
