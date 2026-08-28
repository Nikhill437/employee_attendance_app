import '../../../core/base/base_view_model.dart';
import '../../../data/models/attendance_log_model.dart';
import '../../../data/repositories/attendance_repository.dart';

/// Loads attendance logs grouped per employee for the summary screen.
class AttendanceSummaryViewModel extends BaseViewModel {
  final AttendanceRepository _attendanceRepository;

  AttendanceSummaryViewModel({AttendanceRepository? attendanceRepository})
    : _attendanceRepository = attendanceRepository ?? AttendanceRepository();

  bool _isLoading = true;
  Map<String, List<AttendanceLog>> _groupedLogs = {};

  bool get isLoading => _isLoading;
  Map<String, List<AttendanceLog>> get groupedLogs => _groupedLogs;
  bool get isEmpty => _groupedLogs.isEmpty;

  Future<void> loadLogs() async {
    _isLoading = true;
    safeNotify();

    _groupedLogs = await _attendanceRepository.getLogsGroupedByEmployee();

    _isLoading = false;
    safeNotify();
  }
}
