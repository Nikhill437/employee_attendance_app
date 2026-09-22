import 'dart:convert';

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
  final PayType payType;

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
    this.payType = PayType.daily,
    this.department,
    this.departmentId,
    this.nationalIdImage,
    this.isSynced = false,
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
    PayType? payType,
    String? department,
    int? departmentId,
    String? nationalIdImage,
    bool? isSynced,
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
      payType: payType ?? this.payType,
      department: department ?? this.department,
      departmentId: departmentId ?? this.departmentId,
      nationalIdImage: nationalIdImage ?? this.nationalIdImage,
      isSynced: isSynced ?? this.isSynced,
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
      'enrollment_type': payType.name,
      'face_detection': jsonEncode(faceEmbeddings),
      'status': status,
      'created_by': createdBy,
      'created_date': attendanceTime,
    };
  }

  /// Reads back a `workers` row, left-joined with `departments` so
  /// `department` carries the name rather than just the FK id.
  factory Employee.fromMap(Map<String, dynamic> map) {
    final embeddings = map['face_detection'] != null
        ? (jsonDecode(map['face_detection'] as String) as List)
              .map((e) => List<double>.from(e))
              .toList()
        : <List<double>>[];
    return Employee(
      id: map['worker_id'] as int?,
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
      payType: _enumOrDefault(
        PayType.values,
        map['enrollment_type'],
        PayType.daily,
      ),
      department: map['department_name'] as String?,
      departmentId: map['department_id'] as int?,
      nationalIdImage: map['national_id_image'] as String?,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
    );
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
}
