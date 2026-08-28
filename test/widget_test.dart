import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance_app/app.dart';

void main() {
  testWidgets('home screen offers login and enrollment', (tester) async {
    await tester.pumpWidget(const EmployeeAttendanceApp());

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create Attendance'), findsOneWidget);
  });
}
