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

  /// Free-text department the supervisor typed on the enrollment form, or
  /// null for records enrolled before this field existed.
  final String? department;

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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'number': number,
      'employeeId': employeeId,
      'attendanceTime': attendanceTime,
      'faceVerified': faceVerified ? 1 : 0,
      'faceEmbedding': jsonEncode(faceEmbeddings),
      'dateOfBirth': dateOfBirth,
      'gender': gender.name,
      'address': address,
      'payType': payType.name,
      'department': department,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      name: map['name'],
      number: map['number'],
      employeeId: map['employeeId'],
      attendanceTime: map['attendanceTime'],
      faceVerified: map['faceVerified'] == 1,
      faceEmbeddings: map['faceEmbedding'] != null
          ? (jsonDecode(map['faceEmbedding']) as List)
                .map((e) => List<double>.from(e))
                .toList()
          : [],
      dateOfBirth: map['dateOfBirth'] as String?,
      // Records enrolled before these columns existed have null here —
      // fall back to a neutral default rather than throwing.
      gender: _enumOrDefault(Gender.values, map['gender'], Gender.other),
      address: map['address'] as String?,
      payType: _enumOrDefault(PayType.values, map['payType'], PayType.daily),
      department: map['department'] as String?,
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
