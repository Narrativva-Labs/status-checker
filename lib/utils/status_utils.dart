// Shared, side-effect free helpers for time zones and status evaluation.
//
// The same rules are implemented in `supabase/functions/_shared/status.ts`,
// so the "today" bar computed in the app matches the daily records written by
// the edge function.

const String kTimezoneUtc = 'UTC';
const String kTimezonePrague = 'Europe/Prague';

/// Maximum number of pages one user can monitor (also enforced in the DB).
const int kMaxPagesPerUser = 10;

/// Number of failed checks in one day from which the day is shown as red.
const int kRedDayFailedChecks = 12;

/// Status values stored in `page_daily_status.status`.
abstract final class DayStatus {
  static const String green = 'green';
  static const String orange = 'orange';
  static const String red = 'red';
  static const String grey = 'grey';
}

DateTime _lastSundayUtc(int year, int month, int hour) {
  // Day 0 of the next month is the last day of [month].
  var date = DateTime.utc(year, month + 1, 0, hour);
  while (date.weekday != DateTime.sunday) {
    date = date.subtract(const Duration(days: 1));
  }
  return date;
}

/// UTC offset of Europe/Prague (CET/CEST) at the given instant.
///
/// Daylight saving time runs from the last Sunday of March 01:00 UTC to the
/// last Sunday of October 01:00 UTC (EU rules).
Duration pragueOffset(DateTime instant) {
  final utc = instant.toUtc();
  final dstStart = _lastSundayUtc(utc.year, 3, 1);
  final dstEnd = _lastSundayUtc(utc.year, 10, 1);
  final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return Duration(hours: isDst ? 2 : 1);
}

/// Wall-clock time in [timezone], returned as a UTC-flagged [DateTime] whose
/// fields (year, month, day, hour…) are the local values in that zone.
DateTime wallClock(DateTime instant, String timezone) {
  final utc = instant.toUtc();
  return timezone == kTimezonePrague ? utc.add(pragueOffset(utc)) : utc;
}

/// The UTC instant of local midnight of the given calendar day in [timezone].
/// Day overflow is normalised, so `day + 1` gives the next midnight.
DateTime midnightUtc(int year, int month, int day, String timezone) {
  final wallMidnight = DateTime.utc(year, month, day);
  if (timezone != kTimezonePrague) return wallMidnight;
  // DST switches at 01:00 UTC (02:00/03:00 local), so the offset one hour
  // before local midnight is the offset valid at midnight.
  final offset = pragueOffset(wallMidnight.subtract(const Duration(hours: 1)));
  return wallMidnight.subtract(offset);
}

/// Parses a database timestamp as UTC. `timestamp without time zone` values
/// come without an offset and would otherwise be read as local time.
DateTime parseUtc(String value) {
  final hasOffset = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$').hasMatch(value);
  return DateTime.parse(hasOffset ? value : '${value}Z').toUtc();
}

/// `YYYY-MM-DD` key of a wall-clock date.
String dayKey(DateTime wall) =>
    '${wall.year.toString().padLeft(4, '0')}-'
    '${wall.month.toString().padLeft(2, '0')}-'
    '${wall.day.toString().padLeft(2, '0')}';

/// Day keys of the last [count] days in [timezone], oldest first, today last.
List<String> lastDayKeys(DateTime now, String timezone, {int count = 30}) {
  final today = wallClock(now, timezone);
  return List.generate(count, (i) {
    final offsetDays = count - 1 - i;
    return dayKey(DateTime.utc(today.year, today.month, today.day - offsetDays));
  });
}

/// A check failed when the request threw (no status code / an error message)
/// or the server answered with an HTTP error (4xx/5xx).
bool isFailedCheck({int? statusCode, String? error}) {
  if (error != null && error.isNotEmpty) return true;
  return statusCode == null || statusCode >= 400;
}

/// Colour of a day from the number of checks and failed checks.
String dailyStatus({required int checks, required int failedChecks}) {
  if (checks == 0) return DayStatus.grey;
  if (failedChecks >= kRedDayFailedChecks) return DayStatus.red;
  if (failedChecks > 0) return DayStatus.orange;
  return DayStatus.green;
}

/// Whether [url] is a Discord webhook endpoint (the only supported target).
bool isDiscordWebhookUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.isScheme('https') &&
      !uri.hasPort &&
      RegExp(r'^((ptb|canary)\.)?discord(app)?\.com$').hasMatch(uri.host) &&
      RegExp(r'^/api/webhooks/\d+/[A-Za-z0-9_-]+/?$').hasMatch(uri.path);
}
