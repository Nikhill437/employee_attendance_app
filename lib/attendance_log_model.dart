class AttendanceLog {
  final int? id;
  final String employeeId;
  final String employeeName;
  final String loginTime;

  AttendanceLog({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.loginTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'loginTime': loginTime,
    };
  }

  factory AttendanceLog.fromMap(Map<String, dynamic> map) {
    return AttendanceLog(
      id: map['id'],
      employeeId: map['employeeId'],
      employeeName: map['employeeName'],
      loginTime: map['loginTime'],
    );
  }
}
