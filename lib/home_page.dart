import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/url_entry.dart';
import 'models/user_settings.dart';
import 'services/discord_service.dart';
import 'services/supabase_service.dart';
import 'utils/status_utils.dart';
import 'widgets/home_content.dart';
import 'widgets/load_error.dart';
import 'widgets/timezone_switch.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const HomePage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final SupabaseService supabaseService = SupabaseService();
  final DiscordService discordService = DiscordService();

  List<UrlEntry> publicPages = [];
  List<UrlEntry> userPages = [];
  UserSettings? currentUserSettings;
  bool isLoading = true;
  bool loadFailed = false;
  String timezone = kTimezonePrague;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    // Close dialogs left open from the login page (e.g. after logging in
    // through a magic link in another tab).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<void> _loadAllData() async {
    try {
      final results = await Future.wait([
        supabaseService.loadPublicPages(),
        supabaseService.loadUserPages(),
        supabaseService.loadUserSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        publicPages = results[0] as List<UrlEntry>;
        userPages = results[1] as List<UrlEntry>;
        currentUserSettings = results[2] as UserSettings?;
        isLoading = false;
        loadFailed = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (!mounted) return;
      if (isLoading) {
        setState(() {
          isLoading = false;
          loadFailed = true;
        });
      } else {
        // Keep the data on screen when only a refresh failed.
        _showMessage('Could not refresh the data.');
      }
    }
  }

  void _retryLoad() {
    setState(() {
      isLoading = true;
      loadFailed = false;
    });
    _loadAllData();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Adds `https://` when the scheme is missing and validates the result.
  /// Returns `null` for an invalid URL.
  String? _normalizeUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    final valid = uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    return valid ? url : null;
  }

  Future<void> _addUserUrl(String url, String? urlName, String? expectText) async {
    final finalUrl = _normalizeUrl(url);
    if (finalUrl == null) {
      _showMessage('The entered URL is not valid.');
      return;
    }
    if (userPages.any((entry) => entry.url == finalUrl)) {
      _showMessage('This page has already been added.');
      return;
    }
    if (userPages.length >= kMaxPagesPerUser) {
      _showMessage('You can monitor up to $kMaxPagesPerUser pages.');
      return;
    }

    final ok = await supabaseService.addUserPage(finalUrl, urlName: urlName?.trim(), expectText: expectText);
    if (!ok) {
      _showMessage('Could not add the page. Please try again.');
      return;
    }
    await _loadAllData();
    _showMessage('Page added.');
    await _logToDiscord('**Page added:** ${urlName ?? finalUrl}');
  }

  Future<void> _deleteUserUrl(String pageId) async {
    final deleted = userPages.where((p) => p.id == pageId).firstOrNull;

    final ok = await supabaseService.deleteUserPage(pageId);
    if (!ok) {
      _showMessage('Could not delete the page. Please try again.');
      return;
    }
    await _loadAllData();
    _showMessage('Page deleted.');
    if (deleted != null) {
      await _logToDiscord('**Page deleted:** ${deleted.displayName}');
    }
  }

  Future<void> _editUserUrl(String pageId, String newUrl, String? newUrlName, String? expectText) async {
    final finalUrl = _normalizeUrl(newUrl);
    if (finalUrl == null) {
      _showMessage('The entered URL is not valid.');
      return;
    }
    if (userPages.any((entry) => entry.id != pageId && entry.url == finalUrl)) {
      _showMessage('This page has already been added.');
      return;
    }

    final ok = await supabaseService.updateUserPage(pageId, finalUrl,
        newUrlName: newUrlName?.trim(), expectText: expectText);
    if (!ok) {
      _showMessage('Could not update the page. Please try again.');
      return;
    }
    await _loadAllData();
    _showMessage('Page updated.');
    await _logToDiscord('**Page updated:** ${newUrlName ?? finalUrl}');
  }

  Future<bool> _saveDiscordWebhook(String? webhookUrl) async {
    final ok = await supabaseService.saveDiscordWebhook(webhookUrl);
    if (ok) await _loadAllData();
    return ok;
  }

  Future<void> _logToDiscord(String message) async {
    final webhook = currentUserSettings?.discordWebhookUrl;
    if (webhook == null || webhook.trim().isEmpty) return;
    try {
      await discordService.sendSimpleMessage(webhook, message);
    } catch (e) {
      debugPrint('Failed to send message to Discord: $e');
    }
  }

  // AuthGate listens to auth changes and shows the login page after sign-out.
  Future<void> _signOut() => supabase.auth.signOut();

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (loadFailed) {
      return Scaffold(
        body: Center(
          child: LoadError(message: 'Could not load your pages.', onRetry: _retryLoad),
        ),
      );
    }

    return Scaffold(
      // No AppBar, just a top row of controls (same as the login page).
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Row(
              children: [
                const Spacer(),
                TimezoneSwitchWidget(
                  selectedTimezone: timezone,
                  onChanged: (tz) => setState(() => timezone = tz),
                  compact: MediaQuery.sizeOf(context).width <= 450,
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: Icon(
                    widget.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                    size: 25,
                  ),
                  onPressed: widget.onToggleTheme,
                  tooltip: 'Switch light/dark theme',
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: _signOut,
                ),
              ],
            ),
          ),
        ),
      ),
      body: HomeContent(
        publicPages: publicPages,
        userPages: userPages,
        onAddUrl: _addUserUrl,
        onDeleteUrl: _deleteUserUrl,
        onEditUrl: _editUserUrl,
        currentWebhookUrl: currentUserSettings?.discordWebhookUrl,
        onSaveDiscordWebhook: _saveDiscordWebhook,
        timezone: timezone,
      ),
    );
  }
}
