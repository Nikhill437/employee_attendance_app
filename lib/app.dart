import 'package:flutter/material.dart';

import 'core/routes/app_routes.dart';

/// Root widget: theme and routing table only — every screen is reached
/// through [AppRoutes].
class EmployeeAttendanceApp extends StatelessWidget {
  /// Where the app opens. Defaults to the splash screen; [main] passes the
  /// dashboard instead when a supervisor session is already persisted.
  final String initialRoute;

  const EmployeeAttendanceApp({super.key, this.initialRoute = AppRoutes.splash});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
    );
  }
}
