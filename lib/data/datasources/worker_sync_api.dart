import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/employee_model.dart';

/// Remote datasource for pushing a locally enrolled worker to the backend.
class WorkerSyncApi {
  final ApiClient _client;

  WorkerSyncApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/sync-worker, as multipart/form-data — a plain JSON
  /// body can't carry the National ID photo file, so every field goes over
  /// as form fields alongside it. Request shape not otherwise confirmed
  /// yet — this sends the worker's fields using the same column names as
  /// the backend's own `workers` table (the schema given earlier), with
  /// `department_id` rather than the department's name, since that's what
  /// the table's own FK actually stores. Adjust once the real contract is
  /// confirmed, same as every other endpoint here so far.
  ///
  /// Confirmed response on success: `{"message": ..., "worker_id": ...,
  /// "status": true}` — returns that `worker_id`, or null if the response
  /// doesn't have the expected shape.
  Future<int?> syncWorker(Employee worker) async {
    final formData = await _toFormData(worker);
    log('Syncing worker ${worker.employeeId} to backend');
    final response = await _client.post(ApiRoutes.syncWorker, data: formData);
    return _extractId(response, 'worker_id');
  }

  /// POST attendance/sync-worker for a worker the backend already knows —
  /// sends only `worker_id` plus the fields the supervisor actually changed
  /// (see WorkerEditQueue), never the whole profile. Request shape not
  /// confirmed against the real backend yet; same endpoint as [syncWorker].
  Future<void> updateWorker({
    required int realWorkerId,
    required Map<String, String> changes,
  }) async {
    final formData = FormData.fromMap({
      'worker_id': realWorkerId.toString(),
      ...changes,
    });
    log('Updating worker $realWorkerId: ${changes.keys.join(', ')}');
    await _client.post(ApiRoutes.syncWorker, data: formData);
  }

  int? _extractId(dynamic response, String key) {
    if (response is! Map) return null;
    final value = response[key];
    return value is int ? value : int.tryParse(value.toString());
  }

  Future<FormData> _toFormData(Employee worker) async {
    final fields = <String, String>{
      'full_name': worker.name,
      'gender': worker.gender.name,
      'national_id': worker.employeeId,
      'phone_number': worker.number,
      'face_detection': jsonEncode(worker.faceEmbeddings),
    };
    if (worker.dateOfBirth != null) fields['birth_date'] = worker.dateOfBirth!;
    if (worker.departmentId != null) {
      fields['department_id'] = worker.departmentId.toString();
    }
    if (worker.address != null) fields['address'] = worker.address!;
    // The creation timestamp (see Employee.attendanceTime) — sent on create
    // and never changed by an edit.
    fields['created_date'] = worker.attendanceTime;
    if (worker.modifiedDate != null) {
      fields['modified_date'] = worker.modifiedDate!;
    }
    // The task picked on the enrollment form's Task dropdown (see
    // Employee.taskId) — the assigned task being synced along with this
    // worker's own profile.
    if (worker.taskId != null) fields['task_id'] = worker.taskId.toString();

    final formData = FormData.fromMap(fields);

    final imagePath = worker.nationalIdImage;
    if (imagePath != null && imagePath.isNotEmpty) {
      formData.files.add(
        MapEntry(
          'national_id_image',
          await MultipartFile.fromFile(
            imagePath,
            filename: imagePath.split('/').last,
          ),
        ),
      );
    }
    return formData;
  }
}
