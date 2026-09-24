import 'package:employee_attendance_app/presentation/auth/view/pin_screen.dart';
import 'package:employee_attendance_app/presentation/auth/view/splash_screen.dart';
import 'package:flutter/material.dart';

import '../../presentation/attendance/view/attendance_summary_screen.dart';
import '../../presentation/auth/view/login_screen.dart';
import '../../presentation/auth/view/mark_attendance_screen.dart';
import '../../presentation/employee/view/create_employee_screen.dart';
import '../../presentation/employee/view/enrollment_form_screen.dart';
import '../../presentation/dashboard/view/dashboard_screen.dart';
import '../../presentation/dashboard/view/worker_list_screen.dart';
import '../../presentation/history/view/worker_history_screen.dart';
import '../../presentation/settings/view/settings_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const String dashboard = '/';
  static const String workerList = '/worker-list';
  static const String settings = '/settings';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String pin = '/pin';
  static const String markAttendance = '/mark-attendance';
  static const String createAttendance = '/create-attendance';
  static const String enrollmentForm = '/enrollment-form';
  static const String attendanceSummary = '/attendance-summary';
  static const String workerHistory = '/worker-history';

  static Map<String, WidgetBuilder> get routes => {
    splash: (_) => SplashScreen(),
    dashboard: (_) => const DashboardScreen(),
    workerList: (_) => const WorkerListScreen(),
    settings: (_) => const SettingsScreen(),
    login: (_) => const LoginScreen(),
    pin: (_) => const PinScreen(pin: "0123"),
    markAttendance: (_) => const MarkAttendanceScreen(),
    createAttendance: (_) => const CreateAttendanceScreen(),
    enrollmentForm: (_) => const EnrollmentFormScreen(),
    attendanceSummary: (_) => const AttendanceSummaryScreen(),
    workerHistory: (_) => const WorkerHistoryScreen(),
  };
}
