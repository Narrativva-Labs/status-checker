import 'package:flutter_test/flutter_test.dart';
import 'package:status_checker/utils/status_utils.dart';

void main() {
  group('pragueOffset', () {
    test('winter time is UTC+1', () {
      expect(pragueOffset(DateTime.utc(2026, 1, 15, 12)), const Duration(hours: 1));
    });

    test('summer time is UTC+2', () {
      expect(pragueOffset(DateTime.utc(2026, 7, 15, 12)), const Duration(hours: 2));
    });

    test('switches on the last Sunday of March at 01:00 UTC', () {
      // 29 March 2026 is the last Sunday of March.
      expect(pragueOffset(DateTime.utc(2026, 3, 29, 0, 59)), const Duration(hours: 1));
      expect(pragueOffset(DateTime.utc(2026, 3, 29, 1)), const Duration(hours: 2));
    });

    test('switches back on the last Sunday of October at 01:00 UTC', () {
      // 25 October 2026 is the last Sunday of October.
      expect(pragueOffset(DateTime.utc(2026, 10, 25, 0, 59)), const Duration(hours: 2));
      expect(pragueOffset(DateTime.utc(2026, 10, 25, 1)), const Duration(hours: 1));
    });
  });

  group('midnightUtc', () {
    test('UTC midnight is unchanged', () {
      expect(midnightUtc(2026, 5, 10, kTimezoneUtc), DateTime.utc(2026, 5, 10));
    });

    test('Prague midnight in summer is 22:00 UTC the day before', () {
      expect(midnightUtc(2026, 5, 10, kTimezonePrague), DateTime.utc(2026, 5, 9, 22));
    });

    test('Prague midnight in winter is 23:00 UTC the day before', () {
      expect(midnightUtc(2026, 12, 10, kTimezonePrague), DateTime.utc(2026, 12, 9, 23));
    });

    test('DST transition days have the right length', () {
      final springStart = midnightUtc(2026, 3, 29, kTimezonePrague);
      final springEnd = midnightUtc(2026, 3, 30, kTimezonePrague);
      expect(springEnd.difference(springStart), const Duration(hours: 23));

      final autumnStart = midnightUtc(2026, 10, 25, kTimezonePrague);
      final autumnEnd = midnightUtc(2026, 10, 26, kTimezonePrague);
      expect(autumnEnd.difference(autumnStart), const Duration(hours: 25));
    });
  });

  group('lastDayKeys', () {
    test('returns 30 days ending today, oldest first', () {
      final keys = lastDayKeys(DateTime.utc(2026, 3, 5, 12), kTimezoneUtc);
      expect(keys, hasLength(30));
      expect(keys.first, '2026-02-04');
      expect(keys.last, '2026-03-05');
    });

    test('uses the calendar day of the selected time zone', () {
      // 23:30 UTC on 31 Dec is already 1 Jan in Prague.
      final now = DateTime.utc(2026, 12, 31, 23, 30);
      expect(lastDayKeys(now, kTimezoneUtc).last, '2026-12-31');
      expect(lastDayKeys(now, kTimezonePrague).last, '2027-01-01');
    });
  });

  group('isFailedCheck', () {
    test('2xx and 3xx responses are healthy', () {
      expect(isFailedCheck(statusCode: 200), isFalse);
      expect(isFailedCheck(statusCode: 301), isFalse);
    });

    test('HTTP errors, network errors and missing status codes fail', () {
      expect(isFailedCheck(statusCode: 404), isTrue);
      expect(isFailedCheck(statusCode: 503), isTrue);
      expect(isFailedCheck(error: 'Connection refused'), isTrue);
      expect(isFailedCheck(), isTrue);
    });
  });

  group('isDiscordWebhookUrl', () {
    test('accepts Discord webhook endpoints', () {
      expect(isDiscordWebhookUrl('https://discord.com/api/webhooks/1/abc'), isTrue);
      expect(isDiscordWebhookUrl('https://canary.discord.com/api/webhooks/1/abc'), isTrue);
    });

    test('rejects other hosts, paths and plain http', () {
      expect(isDiscordWebhookUrl('https://example.com/api/webhooks/1/abc'), isFalse);
      expect(isDiscordWebhookUrl('https://discord.com/channels/1'), isFalse);
      expect(isDiscordWebhookUrl('http://discord.com/api/webhooks/1/abc'), isFalse);
    });
  });

  group('dailyStatus', () {
    test('no checks means no data', () {
      expect(dailyStatus(checks: 0, failedChecks: 0), DayStatus.grey);
    });

    test('maps failed checks to a colour', () {
      expect(dailyStatus(checks: 96, failedChecks: 0), DayStatus.green);
      expect(dailyStatus(checks: 96, failedChecks: 1), DayStatus.orange);
      expect(dailyStatus(checks: 96, failedChecks: kRedDayFailedChecks), DayStatus.red);
    });
  });
}
