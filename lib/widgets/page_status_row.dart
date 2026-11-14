import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/page_status.dart';
import '../models/url_entry.dart';
import '../services/supabase_service.dart';
import '../utils/status_utils.dart';

/// Name, URL and a 30-day status bar of one monitored page.
class PageStatusRowWidget extends StatefulWidget {
  final UrlEntry page;
  final String timezone;

  const PageStatusRowWidget({super.key, required this.page, required this.timezone});

  @override
  State<PageStatusRowWidget> createState() => _PageStatusRowWidgetState();
}

class _PageStatusRowWidgetState extends State<PageStatusRowWidget> {
  final SupabaseService _supabaseService = SupabaseService();
  late Future<(List<PageStatus>, PageStatus?)> _statuses;
  Timer? _refreshTimer;

  /// Checks run every 5 minutes, so the bar refreshes at the same pace.
  static const _refreshInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _statuses = _load();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Reloads in the background and swaps the data in when it arrives, so the
  /// bar does not flash a loading spinner.
  Future<void> _refresh() async {
    final pageId = widget.page.id;
    final timezone = widget.timezone;
    final next = _load();
    await next;
    // Ignore the result if the page or time zone changed in the meantime.
    if (!mounted || pageId != widget.page.id || timezone != widget.timezone) return;
    setState(() => _statuses = next);
  }

  @override
  void didUpdateWidget(PageStatusRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload only when the data really changes, not on every parent rebuild.
    if (oldWidget.page.id != widget.page.id ||
        oldWidget.page.url != widget.page.url ||
        oldWidget.timezone != widget.timezone) {
      _statuses = _load();
    }
  }

  Future<(List<PageStatus>, PageStatus?)> _load() async {
    final daily = _supabaseService.loadPageDailyStatuses(widget.page.id,
        timezone: widget.timezone);
    final latest = _supabaseService.loadPageLatestStatus(widget.page.id,
        timezone: widget.timezone);
    return (await daily, await latest);
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurface;

    return FutureBuilder<(List<PageStatus>, PageStatus?)>(
      future: _statuses,
      builder: (context, snapshot) {
        // While refreshing, FutureBuilder keeps the previous data, so the
        // spinner is shown only on the first load.
        if (!snapshot.hasData) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const Text('Error loading statuses.');
        }

        final (statuses, latestStatus) = snapshot.data!;
        final statusByDay = {for (final s in statuses) s.day: s.status};

        // Days are taken in the selected time zone, so they match the records.
        final days = lastDayKeys(DateTime.now(), widget.timezone);
        final today = days.last;
        final ovals = [
          for (final day in days)
            (
              day == today
                  ? (latestStatus?.status ?? DayStatus.grey)
                  : (statusByDay[day] ?? DayStatus.grey),
              day,
            ),
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SelectableText(
                widget.page.displayName,
                style: GoogleFonts.epilogue(
                  fontWeight: FontWeight.w700,
                  fontSize: 21,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              SelectableText(
                widget.page.url,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: mutedColor.withValues(alpha: 0.45),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Fit all 30 days into the available width (16 px side
                  // padding, 2.6 px gap per oval), up to 15 px per oval.
                  const gap = 2.6;
                  final available = constraints.maxWidth - 32;
                  final ovalWidth = (available / ovals.length - gap).clamp(3.0, 15.0);
                  final isNarrow = ovalWidth < 15.0;
                  final ovalHeight = isNarrow ? 22.0 : 28.0;

                  final row = Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (status, day) in ovals)
                        _StatusOval(
                          status: status,
                          day: day,
                          width: ovalWidth,
                          height: ovalHeight,
                        ),
                    ],
                  );

                  if (!isNarrow) return row;

                  return Column(
                    children: [
                      row,
                      const SizedBox(height: 4),
                      Text(
                        'Last 30 days',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: mutedColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusOval extends StatefulWidget {
  final String status;
  final String day;
  final double width;
  final double height;

  const _StatusOval({
    required this.status,
    required this.day,
    this.width = 15,
    this.height = 28,
  });

  @override
  State<_StatusOval> createState() => _StatusOvalState();
}

class _StatusOvalState extends State<_StatusOval> {
  bool _hovered = false;

  static const _colors = {
    DayStatus.green: Color(0xFF34D399),
    DayStatus.orange: Color(0xFFF59E42),
    DayStatus.red: Color(0xFFEF4444),
  };

  static const _labels = {
    DayStatus.green: 'No incidents',
    DayStatus.orange: 'Some issues',
    DayStatus.red: 'Major issues',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[widget.status] ?? Colors.grey.shade400;
    final statusText = _labels[widget.status] ?? 'No data';

    String formattedDate;
    try {
      formattedDate = DateFormat('MMM d, yyyy').format(DateTime.parse(widget.day));
    } catch (_) {
      formattedDate = widget.day;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: '$formattedDate\n$statusText',
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        preferBelow: false,
        waitDuration: Duration.zero,
        child: Transform.translate(
          offset: _hovered ? const Offset(0, -2) : Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 1.3),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.36),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : const [],
            ),
          ),
        ),
      ),
    );
  }
}
