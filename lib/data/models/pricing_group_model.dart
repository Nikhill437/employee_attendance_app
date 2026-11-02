/// A pricing group, as cached locally from the backend's
/// `GET pricing-groups/list` response and re-read from the local
/// `pricing_groups` table (see DatabaseHelper.upsertPricingGroups) — what
/// AssignTaskViewModel looks up to show a task-change-request dialog's
/// group names, and what [Task.pricingGroupId]/[WorkerTask.
/// taskPricingGroupId] are compared against by id (never by [groupName] —
/// see that comparison's own doc comment).
class PricingGroup {
  final int id;
  final String groupName;

  /// The backend sends these as decimal strings (e.g. `"6001.00"`) —
  /// parsed to `double` here and stored as `REAL` locally.
  final double minRate;
  final double maxRate;
  final String? description;
  final String status;
  final String? createdDate;
  final String? modifiedDate;
  final int? createdBy;
  final int? modifiedBy;

  const PricingGroup({
    required this.id,
    required this.groupName,
    required this.minRate,
    required this.maxRate,
    this.description,
    this.status = 'active',
    this.createdDate,
    this.modifiedDate,
    this.createdBy,
    this.modifiedBy,
  });

  /// `created_by_name`/`modified_by_name` (display names for whichever
  /// admin created/modified this group) and `active_tasks_count` are in
  /// the confirmed response but aren't stored locally — the first two
  /// have no local admin-accounts table to join against anyway (same
  /// reasoning as every other `created_by`/`modified_by` column in this
  /// app), and the count is a live aggregate that would just go stale the
  /// moment it's cached, with nothing here reading it back.
  factory PricingGroup.fromRemote(Map<String, dynamic> json) {
    return PricingGroup(
      id: _asInt(json['pricing_group_id'] ?? json['id']),
      groupName: (json['group_name'] ?? '').toString(),
      minRate: _asDouble(json['min_rate']),
      maxRate: _asDouble(json['max_rate']),
      description: json['description'] as String?,
      status: (json['status'] as String?) ?? 'active',
      createdDate: json['created_date'] as String?,
      modifiedDate: json['modified_date'] as String?,
      createdBy: _asIntOrNull(json['created_by']),
      modifiedBy: _asIntOrNull(json['modified_by']),
    );
  }

  /// Reads back a local `pricing_groups` row.
  factory PricingGroup.fromMap(Map<String, dynamic> map) {
    return PricingGroup(
      id: map['pricing_group_id'] as int,
      groupName: map['group_name'] as String,
      minRate: (map['min_rate'] as num).toDouble(),
      maxRate: (map['max_rate'] as num).toDouble(),
      description: map['description'] as String?,
      status: map['status'] as String? ?? 'active',
      createdDate: map['created_date'] as String?,
      modifiedDate: map['modified_date'] as String?,
      createdBy: map['created_by'] as int?,
      modifiedBy: map['modified_by'] as int?,
    );
  }

  /// "Group F (₹5001.00 - ₹6000.00)" — the task-change-request dialog's
  /// own display format (see AssignTaskViewModel).
  String get rangeLabel =>
      '$groupName (₹${minRate.toStringAsFixed(2)} - ₹${maxRate.toStringAsFixed(2)})';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException(
    'Expected an int id, got $value (${value.runtimeType})',
  );
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
