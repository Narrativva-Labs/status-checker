import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/page_status.dart';
import '../models/url_entry.dart';
import '../models/user_settings.dart';
import '../utils/status_utils.dart';

/// Data access for the app.
///
/// Read methods throw when the request fails, so the UI can tell
/// "no data" apart from "data could not be loaded". Write methods return
/// `true` on success and `false` on failure.
class SupabaseService {
  SupabaseClient get _supabase => Supabase.instance.client;

  // --- PAGES ---

  /// Public pages shown on the status page.
  Future<List<UrlEntry>> loadPublicPages() async {
    final List<dynamic> result =
        await _supabase.from('pages').select('*').eq('is_public', true).order('created_at');
    return result.map((json) => UrlEntry.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Pages added by the signed-in user.
  Future<List<UrlEntry>> loadUserPages() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final List<dynamic> result =
        await _supabase.from('pages').select('*').eq('user_id', user.id).order('created_at');
    return result.map((json) => UrlEntry.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<bool> addUserPage(String url, {String? urlName, String? expectText}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    return _write('adding page', () => _supabase.from('pages').insert({
          'url': url,
          'url_name': urlName,
          'expect_text': expectText == '' ? null : expectText,
          'user_id': user.id,
          'is_public': false,
        }));
  }

  Future<bool> updateUserPage(String pageId, String newUrl, {String? newUrlName, String? expectText}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    return _write(
      'updating page',
      () => _supabase
          .from('pages')
          .update({'url': newUrl, 'url_name': newUrlName, 'expect_text': expectText == '' ? null : expectText})
          .eq('id', pageId)
          .eq('user_id', user.id),
    );
  }

  Future<bool> deleteUserPage(String pageId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    return _write(
      'deleting page',
      () => _supabase.from('pages').delete().eq('id', pageId).eq('user_id', user.id),
    );
  }

  // --- USER SETTINGS ---

  /// Settings of the signed-in user, or `null` if they have none yet.
  Future<UserSettings?> loadUserSettings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final List<dynamic> result =
        await _supabase.from('user_settings').select('*').eq('user_id', user.id).limit(1);
    return result.isEmpty ? null : UserSettings.fromJson(result.first as Map<String, dynamic>);
  }

  /// Saves (or clears with `null`) the user's Discord webhook.
  ///
  /// `is_admin` is never sent: it is read-only for the app (see schema.sql).
  Future<bool> saveDiscordWebhook(String? discordWebhookUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    return _write(
      'saving Discord webhook',
      () => _supabase.from('user_settings').upsert({
        'user_id': user.id,
        'discord_webhook_url': discordWebhookUrl,
      }),
    );
  }

  // --- STATUSES ---

  /// Daily history, today's status and the latest check of a page.
  Future<PageStatusData> loadPageStatus(String pageId, {required String timezone}) async {
    final today = wallClock(DateTime.now(), timezone);
    final start = midnightUtc(today.year, today.month, today.day, timezone);
    final end = midnightUtc(today.year, today.month, today.day + 1, timezone);

    final responses = await Future.wait([
      _supabase
          .from('page_daily_status')
          .select('status, day, timezone')
          .eq('page_id', pageId)
          .eq('timezone', timezone)
          .order('day', ascending: false)
          .limit(30),
      // The daily record for today is written only after the day ends, so
      // today's status is computed from the raw logs.
      _supabase
          .from('pages_logs')
          .select('status_code, error, checked_at')
          .eq('page_id', pageId)
          .gte('checked_at', start.toIso8601String())
          .lt('checked_at', end.toIso8601String()),
      // Latest check of any day, so a check just before midnight still counts.
      _supabase
          .from('pages_logs')
          .select('status_code, error, checked_at')
          .eq('page_id', pageId)
          .order('checked_at', ascending: false)
          .limit(1),
    ]);

    final daily = (responses[0] as List<dynamic>)
        .map((json) => PageStatus.fromJson(json as Map<String, dynamic>))
        .toList();
    final logs = (responses[1] as List<dynamic>).cast<Map<String, dynamic>>();
    final latest = (responses[2] as List<dynamic>).cast<Map<String, dynamic>>();

    bool failed(Map<String, dynamic> log) =>
        isFailedCheck(statusCode: log['status_code'] as int?, error: log['error'] as String?);

    return PageStatusData(
      pageId: pageId,
      timezone: timezone,
      daily: daily,
      today: PageStatus(
        status: dailyStatus(checks: logs.length, failedChecks: logs.where(failed).length),
        day: dayKey(today),
        timezone: timezone,
      ),
      lastCheck: latest.isEmpty
          ? null
          : LastCheck(
              checkedAt: parseUtc(latest.first['checked_at'] as String),
              failed: failed(latest.first),
              reason: failedCheckReason(
                statusCode: latest.first['status_code'] as int?,
                error: latest.first['error'] as String?,
              ),
            ),
    );
  }

  Future<bool> _write(String action, Future<dynamic> Function() request) async {
    try {
      await request();
      return true;
    } catch (e) {
      debugPrint('Error $action: $e');
      return false;
    }
  }
}
