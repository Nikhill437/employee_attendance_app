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

  static const List<String> _monthAbbreviations = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `Oct 24, 2026` — the date line under the dashboard greeting.
  static String dayLabel(DateTime date) =>
      '${_monthAbbreviations[date.month - 1]} ${date.day}, ${date.year}';

  /// `10:30 AM` — the 12-hour clock used by the "Last synced" captions.
  static String clock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  /// True when [date] falls on the same calendar day as [other].
  static bool isSameDay(DateTime date, DateTime other) =>
      date.year == other.year &&
      date.month == other.month &&
      date.day == other.day;
}
