import 'package:flutter/material.dart';

import 'app.dart';
import 'core/routes/app_routes.dart';
import 'core/utils/app_time.dart';
import 'data/repositories/supervisor_session_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads the tz database and activates whichever IANA timezone was saved
  // from the last login (see AppTime), so every timestamp shown anywhere
  // in the app is already in the user's own timezone from the first frame.
  await AppTime.init();

  // A supervisor who logged in on a previous run stays signed in — reopening
  // the app goes straight to the dashboard instead of asking them to log in
  // again; only Settings > Logout ends the session.
  final isSupervisorLoggedIn = await SupervisorSessionRepository()
      .isLoggedIn();

  runApp(
    EmployeeAttendanceApp(
      initialRoute: isSupervisorLoggedIn
          ? AppRoutes.dashboard
          : AppRoutes.splash,
    ),
  );
}
