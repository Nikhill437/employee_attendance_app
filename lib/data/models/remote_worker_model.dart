/// One worker row from the backend's `POST attendance/list` response.
///
/// Deliberately not folded into [Employee]/`toWorkerRow` (which shape a
/// LOCALLY-enrolled worker for insert): this mirrors the backend's own row
/// more literally, including fields (status, rejection_reason,
/// approved_by/at) the app doesn't set for its own local enrollments yet.
class RemoteWorkerRecord {
  final int workerId;
  final String fullName;
  final String? birthDate;
  final String gender;
  final String nationalId;
  final String? nationalIdImage;
  final String? phoneNumber;
  final int departmentId;
  final String departmentName;
  final String? address;
  final String? faceDetection;
  final String status;
  final String? rejectionReason;
  final int? createdBy;
  final int? approvedBy;
  final String? approvedAt;
  final String? createdDate;
  final String? modifiedDate;

  const RemoteWorkerRecord({
    required this.workerId,
    required this.fullName,
    required this.birthDate,
    required this.gender,
    required this.nationalId,
    required this.nationalIdImage,
    required this.phoneNumber,
    required this.departmentId,
    required this.departmentName,
    required this.address,
    required this.faceDetection,
    required this.status,
    required this.rejectionReason,
    required this.createdBy,
    required this.approvedBy,
    required this.approvedAt,
    required this.createdDate,
    required this.modifiedDate,
  });

  factory RemoteWorkerRecord.fromJson(Map<String, dynamic> json) {
    return RemoteWorkerRecord(
      workerId: json['worker_id'] as int,
      fullName: json['full_name'] as String,
      birthDate: json['birth_date'] as String?,
      gender: (json['gender'] as String?) ?? 'other',
      nationalId: json['national_id'] as String,
      nationalIdImage: json['national_id_image'] as String?,
      phoneNumber: json['phone_number'] as String?,
      departmentId: json['department_id'] as int,
      departmentName: (json['department_name'] as String?) ?? 'Unassigned',
      address: json['address'] as String?,
      // Not real embeddings from this endpoint (can be a placeholder string
      // like "embedding_data_009") — stored as-is; Employee.fromMap decodes
      // it defensively, so a worker imported this way just reads back with
      // no usable face profile rather than the app crashing on it.
      faceDetection: json['face_detection'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      rejectionReason: json['rejection_reason'] as String?,
      createdBy: json['created_by'] as int?,
      approvedBy: json['approved_by'] as int?,
      approvedAt: json['approved_at'] as String?,
      createdDate: json['created_date'] as String?,
      modifiedDate: json['modified_date'] as String?,
    );
  }
}
