/// Formatting helpers for the ISO-8601 timestamps stored in the database.
class DateTimeFormatter {
  const DateTimeFormatter._();

  /// Renders an ISO-8601 string as `dd/MM/yyyy  •  HH:mm`.
  static String format(String isoString) {
    final dt = DateTime.parse(isoString);
    final date =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return '$date  •  $time';
  }
}
