import 'package:flutter/material.dart';

import 'core/routes/app_routes.dart';

/// Root widget: theme and routing table only — every screen is reached
/// through [AppRoutes].
class EmployeeAttendanceApp extends StatelessWidget {
  const EmployeeAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: AppRoutes.login,
      routes: AppRoutes.routes,
    );
  }
}
