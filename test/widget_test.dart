import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:employee_attendance_app/app.dart';

void main() {
  testWidgets('landing screen shows both entry points', (tester) async {
    await tester.pumpWidget(const EmployeeAttendanceApp());

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create Attendance'), findsOneWidget);
    expect(find.text('Forget Password?'), findsOneWidget);
  });

  testWidgets('Login opens the attendance marking screen', (tester) async {
    await tester.pumpWidget(const EmployeeAttendanceApp());

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Employee ID'), findsOneWidget);
  });

  testWidgets('Create Attendance opens the enrollment form', (tester) async {
    await tester.pumpWidget(const EmployeeAttendanceApp());

    await tester.tap(find.text('Create Attendance'));
    await tester.pumpAndSettle();

    expect(find.text('Employee Name'), findsOneWidget);
  });
}
