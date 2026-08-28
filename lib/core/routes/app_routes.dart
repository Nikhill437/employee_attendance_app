import 'package:flutter/material.dart';

import '../../presentation/attendance/view/attendance_summary_screen.dart';
import '../../presentation/auth/view/login_screen.dart';
import '../../presentation/employee/view/create_employee_screen.dart';
import '../../presentation/home/view/home_screen.dart';

/// Named routes for the screens that are pushed without arguments.
///
/// Screens that need a constructed argument (the face scan screen, the
/// attendance detail screen) are still pushed directly with a
/// [MaterialPageRoute], since their arguments aren't representable as route
/// names.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String createAttendance = '/create-attendance';
  static const String attendanceSummary = '/attendance-summary';

  static Map<String, WidgetBuilder> get routes => {
    home: (_) => const HomeScreen(),
    login: (_) => const LoginScreen(),
    createAttendance: (_) => const CreateAttendanceScreen(),
    attendanceSummary: (_) => const AttendanceSummaryScreen(),
  };
}
