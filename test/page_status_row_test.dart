import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:status_checker/models/page_status.dart';
import 'package:status_checker/models/url_entry.dart';
import 'package:status_checker/services/supabase_service.dart';
import 'package:status_checker/utils/status_utils.dart';
import 'package:status_checker/widgets/page_status_row.dart';

/// Returns queued responses (data or errors) instead of calling Supabase.
class FakeService extends SupabaseService {
  final List<FutureOr<PageStatusData> Function(String timezone)> responses;
  final List<String> requestedTimezones = [];

  FakeService(this.responses);

  @override
  Future<PageStatusData> loadPageStatus(String pageId, {required String timezone}) async {
    requestedTimezones.add(timezone);
    return responses.removeAt(0)(timezone);
  }
}

PageStatusData healthy(String timezone) {
  final today = dayKey(wallClock(DateTime.now(), timezone));
  return PageStatusData(
    pageId: 'page-1',
    timezone: timezone,
    daily: const [],
    today: PageStatus(status: DayStatus.green, day: today, timezone: timezone),
    lastCheck: LastCheck(checkedAt: DateTime.now().toUtc(), failed: false),
  );
}

final page = UrlEntry(
  id: 'page-1',
  url: 'https://example.com',
  urlName: 'Example',
  isPublic: true,
  createdAt: DateTime.utc(2026),
);

Widget app(SupabaseService service, String timezone) => MaterialApp(
      home: Scaffold(
        body: PageStatusRowWidget(page: page, timezone: timezone, service: service),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('shows the latest check when the status loads', (tester) async {
    await tester.pumpWidget(app(FakeService([healthy]), kTimezoneUtc));
    await tester.pump();

    expect(find.text('Example'), findsOneWidget);
    expect(find.textContaining('Up · checked'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('shows an error with retry instead of an empty history', (tester) async {
    final service = FakeService([
      (_) => throw Exception('network down'),
      healthy,
    ]);
    await tester.pumpWidget(app(service, kTimezoneUtc));
    await tester.pump();

    expect(find.text('Could not load the status.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.textContaining('Up · checked'), findsOneWidget);
  });

  testWidgets('reloads and hides data of the old time zone after a switch', (tester) async {
    final pending = Completer<PageStatusData>();
    final service = FakeService([healthy, (_) => pending.future]);

    await tester.pumpWidget(app(service, kTimezoneUtc));
    await tester.pump();
    expect(find.textContaining('Up · checked'), findsOneWidget);

    await tester.pumpWidget(app(service, kTimezonePrague));
    await tester.pump();
    expect(service.requestedTimezones, [kTimezoneUtc, kTimezonePrague]);
    // UTC data must not be drawn under Prague dates while loading.
    expect(find.textContaining('Up · checked'), findsNothing);

    pending.complete(healthy(kTimezonePrague));
    await tester.pump();
    expect(find.textContaining('Up · checked'), findsOneWidget);
  });
}
