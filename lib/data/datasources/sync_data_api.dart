import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';
import '../models/sync_data_result_model.dart';
import '../models/worker_task_model.dart';

/// Remote datasource for `POST attendance/sync-data` — pushes every one of
/// an approved worker's not-yet-synced `worker_attendance` days together
/// with their pending task-assignment review in one multipart/form-data
/// call (a plain JSON body can't carry the review photos, same reasoning
/// as WorkerSyncApi's own National ID photo upload).
///
/// Request/response shape not confirmed against a real backend yet — built
/// to the structure given when this was requested; adjust once the real
/// contract is confirmed, same as every other endpoint here so far.
class SyncDataApi {
  final ApiClient _client;

  SyncDataApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// [attendance] is one map per unsynced day (see
  /// AttendanceSubmissionRepository.submitAllUnsyncedAttendance for how
  /// each is built). [workerTasks] is the worker's pending assignment(s).
  /// [realWorkerId] is sent as each entry's own `worker_id`.
  ///
  /// `sync_data` has one entry **per day**, each with `attendance` and
  /// `worker_tasks` as single objects (not arrays) — matched up by
  /// `task_date`/`attendance_date`. A day with only one side present (an
  /// attendance day with no task, or vice versa) sends the other as `null`.
  /// A non-null [WorkerTask.workPhoto] is attached as a file, cross-referenced
  /// by a `photo_index` field on that day's `worker_tasks` object (the one
  /// piece of this shape that can't be given directly in JSON).
  Future<SyncDataResult> submit({
    required List<Map<String, dynamic>> attendance,
    required List<WorkerTask> workerTasks,
    required int realWorkerId,
  }) async {
    final photoFiles = <MapEntry<String, MultipartFile>>[];

    final taskPayloadByDate = <String, Map<String, dynamic>>{};
    for (final task in workerTasks) {
      final payload = <String, dynamic>{
        'worker_id': realWorkerId,
        'task_id': task.taskId,
        'department_id': task.departmentId,
        'status': task.status,
        'completed_target': task.completedTarget,
        'task_status': task.taskStatus,
        'overtime': task.overtime ?? 0,
        'task_note': task.taskNote,
        'supervisor_note': task.supervisorNote,
        'created_at': task.createdAt,
        'task_date': task.taskDate,
        'isDefault': task.isDefault ? 1 : 0,
      };

      final photoPath = task.workPhoto;
      if (photoPath != null && photoPath.isNotEmpty) {
        final photoIndex = photoFiles.length;
        payload['photo_index'] = photoIndex;
        photoFiles.add(
          MapEntry(
            'photo_$photoIndex',
            await MultipartFile.fromFile(
              photoPath,
              filename: photoPath.split('/').last,
            ),
          ),
        );
      }

      final realWorkerTaskId = task.realWorkerTaskId;
      if (realWorkerTaskId != null) {
        payload['worker_task_id'] = realWorkerTaskId;
      }
      // One task per day is expected (the worker's one standing assignment);
      // if more than one somehow exists for the same day, the last one wins.
      taskPayloadByDate[task.taskDate] = payload;
    }

    final attendanceByDate = <String, Map<String, dynamic>>{
      for (final day in attendance) day['attendance_date'] as String: day,
    };

    final dates = <String>{
      ...attendanceByDate.keys,
      ...taskPayloadByDate.keys,
    }.toList()..sort();
    final syncData = [
      for (final date in dates)
        {
          'attendance': attendanceByDate[date],
          'worker_tasks': taskPayloadByDate[date],
        },
    ];

    final formData = FormData.fromMap({'sync_data': jsonEncode(syncData)});
    for (final entry in photoFiles) {
      formData.files.add(entry);
    }

    log(syncData.toString(), name: 'SyncDataApi.submit');
    final response = await _client.post(
      ApiRoutes.submitAttendance,
      data: formData,
    );
    return _parseResult(response);
  }

  SyncDataResult _parseResult(dynamic response) {
    if (response is! Map || response['success'] != true) {
      throw ApiException(
        (response is Map ? response['message'] as String? : null) ??
            'Sync failed. Please try again.',
      );
    }

    final attendances = <SyncedAttendance>[];
    final workerTasks = <SyncedWorkerTask>[];
    final batches = response['sync_data'];
    if (batches is List) {
      for (final batch in batches) {
        if (batch is! Map) continue;
        // Each day's batch may echo its attendance/worker_tasks back as a
        // single object (matching what's now sent, one entry per day) or as
        // a list (the older, one-entry-overall response shape) — accept
        // either until the real response for the new request is confirmed.
        for (final entry in _asMapList(
          batch['attendance'] ?? batch['attendances'],
        )) {
          final parsed = SyncedAttendance.fromJson(entry);
          if (parsed != null) attendances.add(parsed);
        }
        for (final entry in _asMapList(
          batch['worker_tasks'] ?? batch['worker_task'],
        )) {
          final parsed = SyncedWorkerTask.fromJson(entry);
          if (parsed != null) workerTasks.add(parsed);
        }
      }
    }

    return SyncDataResult(attendances: attendances, workerTasks: workerTasks);
  }

  /// Normalizes a response value that could be a single object, a list of
  /// them, or absent/null, into a plain list of maps to iterate.
  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is Map) return [Map<String, dynamic>.from(value)];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return const [];
  }
}
