import 'package:flutter/material.dart';

import '../models/url_entry.dart';
import 'app_footer.dart';
import 'home_actions.dart';
import 'home_public_pages.dart';
import 'home_user_pages.dart';

class HomeContent extends StatelessWidget {
  final List<UrlEntry> publicPages;
  final List<UrlEntry> userPages;
  final Future<void> Function(String url, String? urlName, String? expectText) onAddUrl;
  final Future<void> Function(String pageId) onDeleteUrl;
  final Future<void> Function(String pageId, String newUrl, String? newUrlName, String? expectText) onEditUrl;
  final String? currentWebhookUrl;
  final Future<bool> Function(String? webhookUrl) onSaveDiscordWebhook;
  final String timezone;

  const HomeContent({
    super.key,
    required this.publicPages,
    required this.userPages,
    required this.onAddUrl,
    required this.onDeleteUrl,
    required this.onEditUrl,
    this.currentWebhookUrl,
    required this.onSaveDiscordWebhook,
    required this.timezone,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          padding: EdgeInsets.symmetric(
            vertical: constraints.maxWidth < 650 ? 36 : 70,
          ),
          children: [
            Center(
              child: Column(
                children: [
                  HomeActions(
                    onAddUrl: onAddUrl,
                    currentWebhookUrl: currentWebhookUrl,
                    onSaveDiscordWebhook: onSaveDiscordWebhook,
                  ),
                  HomeUserPages(
                    userPages: userPages,
                    onEditUrl: onEditUrl,
                    onDeleteUrl: onDeleteUrl,
                    timezone: timezone,
                  ),
                ],
              ),
            ),
            Center(
              child: HomePublicPages(
                publicPages: publicPages,
                timezone: timezone,
              ),
            ),
            const AppFooter(),
          ],
        );
      },
    );
  }
}
