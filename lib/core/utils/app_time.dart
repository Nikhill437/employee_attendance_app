// app_time.dart
// Central timezone handling for the whole app.
//
// The backend stores and sends every timestamp in UTC. Each user has an IANA
// timezone (e.g. `Europe/London`, `Asia/Kolkata`, `Africa/Lagos`) that comes
// back in the login response. We store that name locally and use the IANA tz
// database (via the `timezone` package) to convert UTC → the user's local wall
// clock before displaying it — so daylight-saving transitions (UK GMT/BST,
// etc.) are handled automatically and nothing is hardcoded per country.

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';

class AppTime {
  AppTime._();

  /// SharedPreferences key holding the user's IANA timezone name.
  static String get storageKey => '${AppConfig.envPrefix}user_timezone';

  static tz.Location? _location;
  static String? _name;

  /// Fixed UTC offset parsed from an offset-style value (e.g. `+02:00`,
  /// `UTC+5:30`) when the backend sends an offset instead of an IANA name.
  /// Used only when [_location] could not be resolved. No DST awareness.
  static Duration? _fixedOffset;

  /// The active IANA timezone name, or null when none is set (falls back to the
  /// device's local timezone).
  static String? get timeZoneName => _name;

  /// Loads the tz database and activates the stored timezone. Call once from
  /// `main()` before `runApp`.
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final prefs = await SharedPreferences.getInstance();
      _apply(prefs.getString(storageKey));
    } catch (_) {
      _apply(null);
    }
  }

  /// Persists and activates the IANA timezone received from the login response.
  /// Passing null / empty clears it (display then falls back to device local).
  static Future<void> setTimeZone(String? ianaName) async {
    final name = ianaName?.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name == null || name.isEmpty) {
        await prefs.remove(storageKey);
      } else {
        await prefs.setString(storageKey, name);
      }
    } catch (_) {
      /* storage unavailable — still apply for this session */
    }
    _apply(name);
  }

  /// Clears the stored timezone (used on logout).
  static Future<void> clear() => setTimeZone(null);

  static void _apply(String? name) {
    final trimmed = name?.trim();
    _location = null;
    _fixedOffset = null;
    _name = null;
    if (trimmed == null || trimmed.isEmpty) return;

    // Prefer a real IANA zone (DST-aware).
    try {
      _location = tz.getLocation(trimmed);
      _name = trimmed;
      return;
    } catch (_) {
      /* not an IANA name — try an offset below */
    }

    // Backend sometimes sends a plain UTC offset ("+02:00", "UTC+5:30", "-8").
    final offset = _parseOffset(trimmed);
    if (offset != null) {
      _fixedOffset = offset;
      _name = trimmed;
    }
  }

  /// Parses an offset-style timezone string into a [Duration], or null.
  static Duration? _parseOffset(String raw) {
    final m = RegExp(
      r'^(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d{2}))?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final sign = m.group(1) == '-' ? -1 : 1;
    final hours = int.parse(m.group(2)!);
    final minutes = int.parse(m.group(3) ?? '0');
    if (hours > 14 || minutes > 59) return null;
    return Duration(minutes: sign * (hours * 60 + minutes));
  }

  /// Converts a backend timestamp to the user's timezone. A naive [dt] (no UTC
  /// flag) is assumed to already be UTC, since that's what the backend sends.
  static DateTime toUserTime(DateTime dt) {
    final utc = dt.isUtc
        ? dt
        : DateTime.utc(
            dt.year,
            dt.month,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second,
            dt.millisecond,
            dt.microsecond,
          );
    final loc = _location;
    if (loc != null) return tz.TZDateTime.from(utc, loc);
    final off = _fixedOffset;
    if (off != null) return utc.add(off);
    return utc.toLocal();
  }

  /// The current wall-clock time in the user's IANA timezone, as a naive
  /// [DateTime] whose calendar fields are that zone's local time. Falls back to
  /// the device's local time when no timezone is set. Use this to seed date /
  /// time pickers so their defaults match what the user expects.
  static DateTime nowInUserZone() {
    final loc = _location;
    if (loc != null) {
      final z = tz.TZDateTime.now(loc);
      return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second);
    }
    final off = _fixedOffset;
    if (off != null) {
      final z = DateTime.now().toUtc().add(off);
      return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second);
    }
    return DateTime.now();
  }

  /// Interprets [wall]'s calendar fields as a wall-clock time in the user's
  /// IANA timezone and returns the corresponding UTC instant. The inverse of
  /// [toUserTime]. Falls back to treating [wall] as device-local time when no
  /// timezone is set. Use this to serialise a value the user picked from a
  /// date / time picker before sending it to the backend.
  static DateTime userWallTimeToUtc(DateTime wall) {
    final loc = _location;
    if (loc != null) {
      return tz.TZDateTime(
        loc,
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
        wall.millisecond,
      ).toUtc();
    }
    final off = _fixedOffset;
    if (off != null) {
      return DateTime.utc(
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
        wall.millisecond,
      ).subtract(off);
    }
    return wall.toUtc();
  }

  /// Formats a backend timestamp in the user's timezone using an
  /// [DateFormat] pattern.
  static String format(DateTime dt, String pattern) =>
      DateFormat(pattern).format(toUserTime(dt));

  /// `3:07 PM`
  static String formatTime(DateTime dt) => format(dt, 'h:mm a');

  /// `03 Sep 2026`
  static String formatDate(DateTime dt) => format(dt, 'dd MMM yyyy');

  /// `03 Sep 2026 • 3:07 PM`
  static String formatDateTime(DateTime dt) =>
      format(dt, 'dd MMM yyyy • h:mm a');
}
