import '../../../core/base/base_view_model.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';

/// Loads the supervisor dashboard figures.
class DashboardViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;

  DashboardViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository();

  bool _isLoading = true;
  DashboardSummary _summary = const DashboardSummary();
  List<Employee> _roster = const [];

  bool get isLoading => _isLoading;
  DashboardSummary get summary => _summary;

  /// Every enrolled employee, for the dashboard's employee list section.
  List<Employee> get roster => _roster;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final enrolled = await _employees.getUnique();
    final presentToday = await _attendance.countPresentOn(DateTime.now());

    _roster = enrolled;
    // Every stored log is a check-in — there is no check-out or offline sync
    // queue in the data layer yet, so those counters stay at their defaults
    // instead of being filled with placeholder numbers.
    _summary = DashboardSummary(
      totalEmployees: enrolled.length,
      presentToday: presentToday,
      checkedIn: presentToday,
    );

    _isLoading = false;
    safeNotify();
  }

  /// Both "Sync Now" and "Sync Data" re-read local storage for now; there is
  /// no remote endpoint to push to.
  Future<void> sync() => load();
}
