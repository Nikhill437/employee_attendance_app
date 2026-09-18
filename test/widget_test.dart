import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:employee_attendance_app/core/routes/app_routes.dart';
import 'package:employee_attendance_app/core/utils/date_time_formatter.dart';
import 'package:employee_attendance_app/presentation/auth/view/splash_screen.dart';
import 'package:employee_attendance_app/presentation/auth/view/login_screen.dart';
import 'package:employee_attendance_app/presentation/face_scan/view/face_scan_screen.dart';
import 'package:employee_attendance_app/presentation/auth/view/pin_screen.dart';
import 'package:employee_attendance_app/data/models/attendance_log_model.dart';
import 'package:employee_attendance_app/data/models/employee_model.dart';
import 'package:employee_attendance_app/data/repositories/attendance_repository.dart';
import 'package:employee_attendance_app/data/repositories/employee_repository.dart';
import 'package:employee_attendance_app/presentation/dashboard/view/dashboard_screen.dart';
import 'package:employee_attendance_app/presentation/dashboard/viewmodel/dashboard_viewmodel.dart';
import 'package:employee_attendance_app/presentation/dashboard/view/worker_list_screen.dart';
import 'package:employee_attendance_app/presentation/dashboard/viewmodel/worker_list_viewmodel.dart';
import 'package:employee_attendance_app/presentation/employee/view/enrollment_form_screen.dart';
import 'package:employee_attendance_app/presentation/employee/viewmodel/create_employee_viewmodel.dart';
import 'package:employee_attendance_app/presentation/face_scan/view/face_capture_screen.dart';
import 'package:employee_attendance_app/data/models/worker_model.dart';
import 'package:employee_attendance_app/presentation/employee/view/enrollment_complete_screen.dart';
import 'package:employee_attendance_app/presentation/common/widgets/app_bottom_nav_bar.dart';
import 'package:employee_attendance_app/presentation/settings/view/settings_screen.dart';
import 'package:employee_attendance_app/data/repositories/supervisor_session_repository.dart';

/// Stand-ins so the dashboard can be laid out without a sqflite plugin.
class _FakeEmployeeRepository extends EmployeeRepository {
  final int count;
  final Set<String> takenEmployeeIds;
  _FakeEmployeeRepository(this.count, {this.takenEmployeeIds = const {}});

  @override
  Future<List<Employee>> getUnique() async => List.generate(
    count,
    (i) => Employee(
      name: 'Employee $i',
      number: '0',
      employeeId: 'E$i',
      attendanceTime: DateTime.now().toIso8601String(),
      faceVerified: true,
      faceEmbeddings: const [],
    ),
  );

  @override
  Future<bool> isEmployeeIdTaken(String employeeId) async =>
      takenEmployeeIds.contains(employeeId);
}

class _FakeAttendanceRepository extends AttendanceRepository {
  final int present;
  _FakeAttendanceRepository(this.present);

  @override
  Future<List<AttendanceLog>> getAllLogs() async => const [];

  @override
  Future<int> countPresentOn(DateTime day) async => present;
}

/// The default 800x600 test window is shorter than any phone these screens
/// target, so lay them out on a phone-sized surface instead.
void usePhoneSurface(WidgetTester tester, {double logicalHeight = 844}) {
  tester.view.physicalSize = Size(390 * 3, logicalHeight * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  // SupervisorLoginViewModel and SettingsViewModel read/write shared
  // preferences; without a mocked backend the plugin has no platform
  // channel to talk to under test.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('splash shows both entry points', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashScreen(),
        routes: Map.of(AppRoutes.routes)..remove(AppRoutes.dashboard),
      ),
    );

    expect(find.text('Mark Attendance'), findsOneWidget);
    expect(find.text('Supervisor Login'), findsOneWidget);
    expect(find.text('Forget Password?'), findsOneWidget);
  });

  testWidgets('Mark Attendance opens the employee ID screen', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashScreen(),
        routes: Map.of(AppRoutes.routes)..remove(AppRoutes.dashboard),
      ),
    );

    await tester.tap(find.text('Mark Attendance'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter the National ID your supervisor assigned you, to continue'),
      findsOneWidget,
    );
    expect(find.text('National ID'), findsOneWidget);
  });

  testWidgets('Supervisor Login opens the login form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashScreen(),
        routes: Map.of(AppRoutes.routes)..remove(AppRoutes.dashboard),
      ),
    );

    await tester.tap(find.text('Supervisor Login'));
    await tester.pumpAndSettle();

    expect(find.text('Username or Email'), findsOneWidget);
  });

  group('login screen', () {
    Future<void> pumpLogin(WidgetTester tester) {
      usePhoneSurface(tester);
      return tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    }

    testWidgets('shows a username field, a password field and a login button', (
      tester,
    ) async {
      await pumpLogin(tester);

      expect(find.text('Username or Email'), findsOneWidget);
      expect(find.text('Password'), findsWidgets);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
    });

    testWidgets('rejects an empty form', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pump();

      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('rejects the wrong credentials', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextFormField).first, 'sanket');
      await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pump();

      expect(find.text('Incorrect username or password'), findsOneWidget);
    });
  });

  testWidgets('face scan screen renders its chrome without a camera', (
    tester,
  ) async {
    usePhoneSurface(tester);
    // availableCameras() has no plugin under test, so the view model lands in
    // its error state — the surrounding chrome must still render.
    await tester.pumpWidget(
      const MaterialApp(home: FaceScanScreen(mode: FaceScanMode.enroll)),
    );
    await tester.pump();

    expect(find.text('SMART ATTENDANCE SYSTEM'), findsOneWidget);
    expect(find.text('Face Verification'), findsOneWidget);
    expect(find.text('Cancel Scan'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('pin screen renders one box per digit', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: PinScreen(pin: '4728')));

    expect(find.text('Attendance Marked!'), findsOneWidget);
    expect(find.text('YOUR DAILY PIN'), findsOneWidget);
    for (final digit in ['4', '7', '2', '8']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.widgetWithText(ElevatedButton, 'Done'), findsOneWidget);
  });

  testWidgets('dashboard shows the counts it loaded', (tester) async {
    usePhoneSurface(tester, logicalHeight: 1400);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          viewModel: DashboardViewModel(
            employees: _FakeEmployeeRepository(48),
            attendance: _FakeAttendanceRepository(36),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Supervisor'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('36'), findsNWidgets(2)); // headline tile and the In tile
    expect(find.text('(75%)'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sync Data'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    // The employees preview reads straight from the (fake) employee table.
    expect(find.text('EMPLOYEES'), findsOneWidget);
    expect(find.text('Employee 0'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('worker list summarises and lists the roster', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerListScreen(
          viewModel: WorkerListViewModel(
            employees: _FakeEmployeeRepository(2),
            attendance: _FakeAttendanceRepository(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Worker List'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('Employee 0'), findsOneWidget);
    expect(find.text('Employee 1'), findsOneWidget);
    // Nothing was logged today, so everyone reads as absent.
    expect(find.text('Absent'), findsNWidgets(2));
    expect(find.text('N/A'), findsNWidgets(2));
    // No pay type was recorded on the fake repository's rows, so both fall
    // back to the default.
    expect(find.text('Daily'), findsNWidgets(2));
  });

  group('enrollment form', () {
    // The whole form is taller than a phone; give it a surface tall enough
    // that every field is laid out and tappable.
    Future<void> pumpForm(WidgetTester tester) {
      usePhoneSurface(tester, logicalHeight: 1600);
      return tester.pumpWidget(
        const MaterialApp(home: EnrollmentFormScreen()),
      );
    }

    testWidgets('shows every detail field and the step strip', (tester) async {
      await pumpForm(tester);

      expect(find.text('New Enrollment'), findsOneWidget);
      expect(find.text('Supervisor Panel'), findsOneWidget);
      for (final step in ['Details', 'Face Capture', 'Complete']) {
        expect(find.text(step), findsOneWidget);
      }
      for (final label in ['Date of Birth', 'Gender', 'Enrollment Type']) {
        expect(find.text(label), findsOneWidget);
      }
      // The five required fields render their label plus a red "*" as one
      // Text.rich span, so a plain find.text() (which only matches Text.data)
      // won't see them — match the exact rendered string via findRichText
      // instead (a "contains" match would also pick up hint text like
      // "Enter National ID Card Number").
      for (final label in [
        'Full Name',
        'National ID',
        'Phone Number',
        'Department',
        'Address',
      ]) {
        expect(
          find.text('$label *', findRichText: true),
          findsOneWidget,
        );
      }
      expect(
        find.widgetWithText(ElevatedButton, 'Proceed to Face Capture'),
        findsOneWidget,
      );
    });

    testWidgets('blocks an empty submission', (tester) async {
      await pumpForm(tester);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Proceed to Face Capture'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter the full name'), findsOneWidget);
      expect(find.text('Enter the National ID'), findsOneWidget);
      expect(find.text('Enter the phone number'), findsOneWidget);
      expect(find.text('Enter the department'), findsOneWidget);
      expect(find.text('Enter the address'), findsOneWidget);
    });

    // Text field order on the form: Full Name, Date of Birth (read-only),
    // National ID, Phone Number, Department, Address.
    const fullNameField = 0;
    const nationalIdField = 2;
    const phoneField = 3;

    testWidgets('full name field strips digits and symbols as they are typed', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byType(TextFormField).at(fullNameField),
        'Rajesh123 Kumar!!',
      );
      await tester.pump();

      final field = tester.widget<TextFormField>(
        find.byType(TextFormField).at(fullNameField),
      );
      expect(field.controller?.text, 'Rajesh Kumar');
    });

    testWidgets(
      'National ID field uppercases letters and strips non-alphanumerics',
      (tester) async {
        await pumpForm(tester);

        await tester.enterText(
          find.byType(TextFormField).at(nationalIdField),
          'ab-12 cd!34',
        );
        await tester.pump();

        final field = tester.widget<TextFormField>(
          find.byType(TextFormField).at(nationalIdField),
        );
        expect(field.controller?.text, 'AB12CD34');
      },
    );

    testWidgets('rejects a malformed phone number', (tester) async {
      await pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(phoneField), '12');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Proceed to Face Capture'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid phone number'), findsOneWidget);
    });

    testWidgets('switches the selected gender', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('Female'));
      await tester.pump();

      final selected = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Female'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = selected.decoration as BoxDecoration;
      expect(decoration.color, isNot(Colors.white));
    });
  });

  testWidgets('face capture shows its guidance before the camera starts', (
    tester,
  ) async {
    usePhoneSurface(tester, logicalHeight: 1400);
    await tester.pumpWidget(const MaterialApp(home: FaceCaptureScreen()));

    expect(find.text('Face Capture'), findsNWidgets(2)); // header and step
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(
      find.text("Position the worker's face within the frame."),
      findsOneWidget,
    );
    expect(find.text('QUICK TIPS'), findsOneWidget);
    expect(find.text('Remove glasses or hats'), findsOneWidget);
    expect(find.text('Retake Photo'), findsOneWidget);
    // One tick for the completed step 1, plus one per quick tip.
    expect(find.byIcon(Icons.check), findsNWidgets(4));
  });

  testWidgets('enrollment complete confirms the registered worker', (
    tester,
  ) async {
    usePhoneSurface(tester, logicalHeight: 1200);
    await tester.pumpWidget(
      MaterialApp(
        home: EnrollmentCompleteScreen(
          workerName: 'Rajesh Kumar',
          systemId: 'EMP-048',
          enrollmentType: PayType.daily,
          registeredAt: DateTime.now(),
        ),
      ),
    );

    expect(find.text('Enrollment Complete'), findsOneWidget);
    expect(find.text('Enrollment Successful!'), findsOneWidget);
    expect(find.text('Rajesh Kumar'), findsOneWidget);
    expect(find.text('EMP-048'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(
      find.text('Today, ${DateTimeFormatter.dayLabel(DateTime.now())}'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ElevatedButton, 'Back to Worker List'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Enroll Another Worker'),
      findsOneWidget,
    );
    // Steps 1 and 2 are done, so both show ticks.
    expect(find.byIcon(Icons.check), findsNWidgets(3));
  });

  testWidgets('supervisor login lands on the dashboard', (tester) async {
    usePhoneSurface(tester, logicalHeight: 1600);
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.login,
        routes: {
          ...AppRoutes.routes,
          AppRoutes.dashboard: (_) => DashboardScreen(
            viewModel: DashboardViewModel(
              employees: _FakeEmployeeRepository(48),
              attendance: _FakeAttendanceRepository(36),
            ),
          ),
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'sanket');
    await tester.enterText(find.byType(TextFormField).last, 'Pass@123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Supervisor'), findsOneWidget);
    expect(find.text('Enroll Worker'), findsOneWidget);
  });

  testWidgets('wrong supervisor credentials stay on the login screen', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.login,
        routes: Map.of(AppRoutes.routes)..remove(AppRoutes.dashboard),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'sanket');
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect username or password'), findsOneWidget);
    expect(find.text('Username or Email'), findsOneWidget);
  });

  testWidgets('an empty employee table shows an empty state, not demo data', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerListScreen(
          viewModel: WorkerListViewModel(
            employees: _FakeEmployeeRepository(0),
            attendance: _FakeAttendanceRepository(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No workers to show'), findsOneWidget);
    expect(find.text('Enroll Worker'), findsOneWidget);
  });

  testWidgets(
    'bottom nav highlights the screen actually on display, not a stale tap',
    (tester) async {
      usePhoneSurface(tester, logicalHeight: 1400);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: AppRoutes.dashboard,
          routes: {
            ...AppRoutes.routes,
            AppRoutes.dashboard: (_) => DashboardScreen(
              viewModel: DashboardViewModel(
                employees: _FakeEmployeeRepository(2),
                attendance: _FakeAttendanceRepository(1),
              ),
            ),
            AppRoutes.workerList: (_) => WorkerListScreen(
              viewModel: WorkerListViewModel(
                employees: _FakeEmployeeRepository(2),
                attendance: _FakeAttendanceRepository(1),
              ),
            ),
          },
        ),
      );

      expect(find.text('Welcome, Supervisor'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppSection.dashboard.index,
      );

      await tester.tap(find.text('Workers'));
      await tester.pumpAndSettle();

      expect(find.text('Worker List'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppSection.workers.index,
      );

      // Switching back must re-highlight Dashboard rather than leaving
      // Workers selected — the bug this test guards against.
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome, Supervisor'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppSection.dashboard.index,
      );
    },
  );

  group('settings screen', () {
    testWidgets('logging out clears the session and returns to login', (
      tester,
    ) async {
      usePhoneSurface(tester, logicalHeight: 1400);
      SharedPreferences.setMockInitialValues({'supervisor_logged_in': true});

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: AppRoutes.settings,
          routes: {
            ...AppRoutes.routes,
            AppRoutes.dashboard: (_) => DashboardScreen(
              viewModel: DashboardViewModel(
                employees: _FakeEmployeeRepository(0),
                attendance: _FakeAttendanceRepository(0),
              ),
            ),
          },
        ),
      );

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // Confirmation dialog first — logging out must not happen on a
      // stray tap.
      expect(find.text('Log out?'), findsOneWidget);
      expect(
        await SupervisorSessionRepository().isLoggedIn(),
        isTrue,
        reason: 'declining the dialog must not touch the session',
      );

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Username or Email'), findsOneWidget);
      expect(await SupervisorSessionRepository().isLoggedIn(), isFalse);
    });

    testWidgets('cancelling the dialog stays on settings', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // "Settings" appears twice — the header and the (now re-selected)
      // bottom-nav label — so check the screen stayed put via the logout
      // row instead of a plain text lookup.
      expect(find.text('Logout'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('supervisor session repository', () {
    test('starts signed out and reflects markLoggedIn / logout', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SupervisorSessionRepository();

      expect(await repository.isLoggedIn(), isFalse);

      await repository.markLoggedIn();
      expect(await repository.isLoggedIn(), isTrue);

      await repository.logout();
      expect(await repository.isLoggedIn(), isFalse);
    });
  });

  group('create employee view model', () {
    test('flags a National ID that is already enrolled', () async {
      final viewModel = CreateEmployeeViewModel(
        employeeRepository: _FakeEmployeeRepository(
          0,
          takenEmployeeIds: {'NID-1'},
        ),
      );

      expect(await viewModel.isNationalIdTaken('NID-1'), isTrue);
      expect(await viewModel.isNationalIdTaken('NID-2'), isFalse);
    });
  });
}
