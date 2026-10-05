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
  /// each is built). [workerTasks] is the worker's pending assignment(s) —
  /// [realWorkerId] is sent as each entry's own `worker_id`, and a non-null
  /// [WorkerTask.workPhoto] is attached as a file, cross-referenced by a
  /// `photo_index` field on that same entry (the one piece of this shape
  /// not given directly in the backend's JSON example, since a plain JSON
  /// value can't carry a file inline).
  Future<SyncDataResult> submit({
    required List<Map<String, dynamic>> attendance,
    required List<WorkerTask> workerTasks,
    required int realWorkerId,
  }) async {
    final workerTaskPayloads = <Map<String, dynamic>>[];
    final photoFiles = <MapEntry<String, MultipartFile>>[];

    for (final task in workerTasks) {
      final payload = <String, dynamic>{
        'worker_id': realWorkerId,
        'task_id': task.taskId,
        'department_id': task.departmentId,
        'status': task.status,
        'completed_target': task.completedTarget,
        'task_status': task.taskStatus,
        'overtime': task.overtime ?? 0,
        'note': task.note,
        'created_at': task.createdAt,
        'task_date': task.taskDate,
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
      workerTaskPayloads.add(payload);
    }

    final syncData = [
      {'attendance': attendance, 'worker_tasks': workerTaskPayloads},
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
        final rawAttendances = batch['attendances'];
        if (rawAttendances is List) {
          for (final entry in rawAttendances) {
            if (entry is! Map) continue;
            final parsed = SyncedAttendance.fromJson(
              Map<String, dynamic>.from(entry),
            );
            if (parsed != null) attendances.add(parsed);
          }
        }
        final rawWorkerTasks = batch['worker_tasks'];
        if (rawWorkerTasks is List) {
          for (final entry in rawWorkerTasks) {
            if (entry is! Map) continue;
            final parsed = SyncedWorkerTask.fromJson(
              Map<String, dynamic>.from(entry),
            );
            if (parsed != null) workerTasks.add(parsed);
          }
        }
      }
    }

    return SyncDataResult(attendances: attendances, workerTasks: workerTasks);
  }
}
