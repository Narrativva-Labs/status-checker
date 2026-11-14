// lib/services/supabase_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/page_status.dart';
import '../models/url_entry.dart';
import '../models/user_settings.dart';
import '../utils/status_utils.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // --- PAGES ---

  /// Loads public (shared) pages.
  Future<List<UrlEntry>> loadPublicPages() async {
    try {
      final List<dynamic> result = await _supabase
          .from('pages')
          .select('*')
          .eq('is_public', true)
          .order('created_at');
      return result
          .map((json) => UrlEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading public pages: $e');
      return [];
    }
  }

  /// Loads pages added by the currently authenticated user.
  Future<List<UrlEntry>> loadUserPages() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final List<dynamic> result = await _supabase
          .from('pages')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at');
      return result
          .map((json) => UrlEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading user pages: $e');
      return [];
    }
  }

  /// Adds a new page for the authenticated user. Returns `true` on success.
  Future<bool> addUserPage(String url, {String? urlName}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('pages').insert({
        'url': url,
        'url_name': urlName,
        'user_id': user.id,
        'is_public': false,
      });
      return true;
    } catch (e) {
      debugPrint('Error adding page: $e');
      return false;
    }
  }

  /// Updates a page owned by the authenticated user. Returns `true` on success.
  Future<bool> updateUserPage(String pageId, String newUrl, {String? newUrlName}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase
          .from('pages')
          .update({'url': newUrl, 'url_name': newUrlName})
          .eq('id', pageId)
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      debugPrint('Error updating page: $e');
      return false;
    }
  }

  /// Deletes a page owned by the authenticated user. Returns `true` on success.
  Future<bool> deleteUserPage(String pageId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('pages').delete().eq('id', pageId).eq('user_id', user.id);
      return true;
    } catch (e) {
      debugPrint('Error deleting page: $e');
      return false;
    }
  }

  // --- USER SETTINGS ---

  /// Loads settings of the currently authenticated user.
  Future<UserSettings?> loadUserSettings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final List<dynamic> result = await _supabase
          .from('user_settings')
          .select('*')
          .eq('user_id', user.id)
          .limit(1);

      if (result.isNotEmpty) {
        return UserSettings.fromJson(result.first as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading user settings: $e');
      return null;
    }
  }

  /// Saves (or clears with `null`) the user's Discord webhook.
  ///
  /// `is_admin` is intentionally never sent from the client: it is managed in
  /// the database only, so saving a webhook cannot reset or escalate it.
  Future<bool> saveDiscordWebhook(String? discordWebhookUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      await _supabase.from('user_settings').upsert({
        'user_id': user.id,
        'discord_webhook_url': discordWebhookUrl,
      });
      return true;
    } catch (e) {
      debugPrint('Error saving Discord webhook: $e');
      return false;
    }
  }

  // --- STATUSES ---

  /// Daily statuses of a page for the last 30 days in the given time zone.
  Future<List<PageStatus>> loadPageDailyStatuses(String pageId,
      {String timezone = kTimezoneUtc}) async {
    try {
      final List<dynamic> result = await _supabase
          .from('page_daily_status')
          .select('status, day, timezone')
          .eq('page_id', pageId)
          .eq('timezone', timezone)
          .order('day', ascending: false)
          .limit(30);

      return result
          .map((json) => PageStatus.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading daily statuses: $e');
      return [];
    }
  }

  /// Today's status computed from the raw check logs (the daily record for
  /// today is only written after the day ends).
  Future<PageStatus?> loadPageLatestStatus(String pageId,
      {String timezone = kTimezoneUtc}) async {
    try {
      final today = wallClock(DateTime.now(), timezone);
      final start = midnightUtc(today.year, today.month, today.day, timezone);
      final end = midnightUtc(today.year, today.month, today.day + 1, timezone);

      final List<dynamic> result = await _supabase
          .from('pages_logs')
          .select('status_code, error')
          .eq('page_id', pageId)
          .gte('checked_at', start.toIso8601String())
          .lt('checked_at', end.toIso8601String());

      final failedChecks = result
          .where((log) => isFailedCheck(
                statusCode: log['status_code'] as int?,
                error: log['error'] as String?,
              ))
          .length;

      return PageStatus(
        status: dailyStatus(checks: result.length, failedChecks: failedChecks),
        day: dayKey(today),
        timezone: timezone,
      );
    } catch (e) {
      debugPrint('Error loading latest status from logs: $e');
      return null;
    }
  }
}
