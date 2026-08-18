import 'dart:convert';

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

  Employee({
    this.id,
    required this.name,
    required this.number,
    required this.employeeId,
    required this.attendanceTime,
    required this.faceVerified,
    required this.faceEmbeddings,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'number': number,
      'employeeId': employeeId,
      'attendanceTime': attendanceTime,
      'faceVerified': faceVerified ? 1 : 0,
      'faceEmbedding': jsonEncode(faceEmbeddings),
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
    );
  }
}
