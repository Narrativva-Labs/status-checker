/// Status of a page for one calendar day.
class PageStatus {
  final String status; // green / orange / red / grey (see DayStatus)
  final String day; // YYYY-MM-DD
  final String timezone; // UTC or Europe/Prague

  const PageStatus({
    required this.status,
    required this.day,
    required this.timezone,
  });

  factory PageStatus.fromJson(Map<String, dynamic> json) {
    return PageStatus(
      status: json['status'] as String,
      day: json['day'] as String,
      timezone: json['timezone'] as String,
    );
  }
}

/// Result of the most recent check of a page.
class LastCheck {
  final DateTime checkedAt; // UTC
  final bool failed;
  final String? reason;

  const LastCheck({required this.checkedAt, required this.failed, this.reason});
}

/// Everything the 30-day status bar of one page needs.
class PageStatusData {
  final String pageId;
  final String timezone;
  final List<PageStatus> daily;
  final PageStatus today;
  final LastCheck? lastCheck;

  const PageStatusData({
    required this.pageId,
    required this.timezone,
    required this.daily,
    required this.today,
    this.lastCheck,
  });
}
