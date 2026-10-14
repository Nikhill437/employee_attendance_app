/// An admin-defined holiday, as cached locally from the backend's
/// `GET attendance/holiday_data` response (`{"data": [{"holiday_id": 1,
/// "holiday_name": "Gandhi Jayanti", "description": "National Holiday",
/// "start_date": "2026-10-02T00:00:00.000Z", "end_date": "...", ...}, ...]}`)
/// and re-read from the local `holiday` table for the dashboard's Holiday
/// card. Read-only from this app's side — same as Department/Task, nothing
/// local ever edits a holiday.
class Holiday {
  final int id;
  final String name;
  final String? description;
  final String startDate;
  final String endDate;

  const Holiday({
    required this.id,
    required this.name,
    this.description,
    required this.startDate,
    required this.endDate,
  });

  factory Holiday.fromRemote(Map<String, dynamic> json) {
    return Holiday(
      id: _asInt(json['holiday_id']),
      name: (json['holiday_name'] ?? '').toString(),
      description: json['description'] as String?,
      startDate: (json['start_date'] ?? '').toString(),
      endDate: (json['end_date'] ?? '').toString(),
    );
  }

  /// Reads back a local `holiday` row (see DatabaseHelper.getHolidays).
  factory Holiday.fromMap(Map<String, dynamic> map) {
    return Holiday(
      id: map['holiday_id'] as int,
      name: map['holiday_name'] as String,
      description: map['description'] as String?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException(
    'Expected an int id, got $value (${value.runtimeType})',
  );
}
