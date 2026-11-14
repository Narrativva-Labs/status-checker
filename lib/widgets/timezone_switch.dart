import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/status_utils.dart';

class TimezoneSwitchWidget extends StatefulWidget {
  final String selectedTimezone;
  final void Function(String timezone) onChanged;

  /// Hides the clock, so the switch fits next to other buttons on phones.
  final bool compact;

  const TimezoneSwitchWidget({
    super.key,
    required this.selectedTimezone,
    required this.onChanged,
    this.compact = false,
  });

  @override
  State<TimezoneSwitchWidget> createState() => _TimezoneSwitchWidgetState();
}

class _TimezoneSwitchWidgetState extends State<TimezoneSwitchWidget> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formattedTime() =>
      DateFormat('HH:mm').format(wallClock(DateTime.now(), widget.selectedTimezone));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.compact) ...[
            const Icon(Icons.access_time, size: 18),
            const SizedBox(width: 8),
            Text(
              _formattedTime(),
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 14),
          ],
          SegmentedButton<String>(
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 9)),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              textStyle: WidgetStateProperty.all(
                GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: kTimezonePrague,
                label: SizedBox(
                  width: 52,
                  child: Text(
                    'Prague',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              ButtonSegment(
                value: kTimezoneUtc,
                label: SizedBox(
                  width: 40,
                  child: Text(
                    'UTC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            selected: {widget.selectedTimezone},
            onSelectionChanged: (values) => widget.onChanged(values.first),
            showSelectedIcon: false,
          ),
        ],
      ),
    );
  }
}
