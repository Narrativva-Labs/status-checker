import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/page_status.dart';
import '../models/url_entry.dart';
import '../services/supabase_service.dart';
import '../utils/status_utils.dart';
import 'load_error.dart';

/// Name, URL, latest check and a 30-day status bar of one monitored page.
class PageStatusRowWidget extends StatefulWidget {
  final UrlEntry page;
  final String timezone;

  /// Data source; replaceable in tests.
  final SupabaseService? service;

  const PageStatusRowWidget({
    super.key,
    required this.page,
    required this.timezone,
    this.service,
  });

  @override
  State<PageStatusRowWidget> createState() => _PageStatusRowWidgetState();
}

class _PageStatusRowWidgetState extends State<PageStatusRowWidget> {
  late final SupabaseService _service = widget.service ?? SupabaseService();
  Timer? _refreshTimer;

  PageStatusData? _data;
  bool _failed = false;

  /// Increases with every request, so only the newest response is applied.
  int _requestId = 0;

  /// Checks run every 5 minutes, so the bar refreshes at the same pace.
  static const _refreshInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  @override
  void didUpdateWidget(PageStatusRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload only when the data really changes, not on every parent rebuild.
    if (oldWidget.page.id != widget.page.id ||
        oldWidget.page.url != widget.page.url ||
        oldWidget.timezone != widget.timezone) {
      _load();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    try {
      final data = await _service.loadPageStatus(widget.page.id, timezone: widget.timezone);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _data = data;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Error loading statuses of ${widget.page.url}: $e');
      if (!mounted || requestId != _requestId) return;
      // A failed background refresh keeps the last data on screen.
      setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurface;
    // Data of another page or time zone (still loading after a change) is not
    // shown, otherwise it would appear under the wrong name or dates.
    final current = _data;
    final data = current != null &&
            current.pageId == widget.page.id &&
            current.timezone == widget.timezone
        ? current
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
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
            style: GoogleFonts.inter(fontSize: 12, color: mutedColor.withValues(alpha: 0.45)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          if (data != null) ...[
            _StatusBar(data: data, mutedColor: mutedColor),
            if (data.lastCheck != null) ...[
              const SizedBox(height: 8),
              _LastCheckLabel(check: data.lastCheck!, timezone: widget.timezone),
            ],
          ] else if (_failed)
            LoadError(message: 'Could not load the status.', onRetry: _retry)
          else
            const SizedBox(
              height: 28,
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final PageStatusData data;
  final Color mutedColor;

  const _StatusBar({required this.data, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    final statusByDay = {for (final s in data.daily) s.day: s.status};
    // Days are taken in the selected time zone, so they match the records.
    final days = lastDayKeys(DateTime.now(), data.timezone);
    final today = days.last;
    final ovals = [
      for (final day in days)
        (
          day == today && data.today.day == today
              ? data.today.status
              : (statusByDay[day] ?? DayStatus.grey),
          day,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit all 30 days into the available width (16 px side padding,
        // 2.6 px gap per oval), up to 15 px per oval.
        const gap = 2.6;
        final available = constraints.maxWidth - 32;
        final ovalWidth = (available / ovals.length - gap).clamp(3.0, 15.0);
        final isNarrow = ovalWidth < 15.0;
        final ovalHeight = isNarrow ? 22.0 : 28.0;

        final row = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (status, day) in ovals)
              _StatusOval(status: status, day: day, width: ovalWidth, height: ovalHeight),
          ],
        );

        if (!isNarrow) return row;

        return Column(
          children: [
            row,
            const SizedBox(height: 4),
            Text(
              'Last 30 days',
              style: GoogleFonts.inter(fontSize: 12, color: mutedColor.withValues(alpha: 0.6)),
            ),
          ],
        );
      },
    );
  }
}

/// "Up · checked 18:30" from the most recent check.
class _LastCheckLabel extends StatelessWidget {
  final LastCheck check;
  final String timezone;

  const _LastCheckLabel({required this.check, required this.timezone});

  @override
  Widget build(BuildContext context) {
    final color = check.failed ? _StatusOvalState._colors[DayStatus.red]! : _StatusOvalState._colors[DayStatus.green]!;
    final time = DateFormat('HH:mm').format(wallClock(check.checkedAt, timezone));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${check.failed ? 'Down' : 'Up'} · checked $time',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
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

  static const Map<String, Color> _colors = {
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
