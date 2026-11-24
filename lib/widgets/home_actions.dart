import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/discord_service.dart';
import '../utils/status_utils.dart';
import 'dialog_styles.dart';

class HomeActions extends StatelessWidget {
  final Future<void> Function(String url, String? urlName, String? expectText) onAddUrl;
  final String? currentWebhookUrl;
  final Future<bool> Function(String? webhookUrl) onSaveDiscordWebhook;

  const HomeActions({
    super.key,
    required this.onAddUrl,
    required this.currentWebhookUrl,
    required this.onSaveDiscordWebhook,
  });

  static const Color _addColor = Color(0xFFBE1931);
  static const Color _discordColor = Color(0xFF5865F2);

  void _showMessage(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ======= ADD PAGE DIALOG =======
  void _showAddPageDialog(BuildContext context) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final expectController = TextEditingController();

    showDialogDisposing<void>(
      context,
      disposables: [urlController, nameController, expectController],
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        shape: dialogShape(),
        elevation: 14,
        titlePadding: const EdgeInsets.only(top: 32, left: 24, right: 24, bottom: 6),
        title: Text(
          'Add Page',
          style: GoogleFonts.epilogue(fontWeight: FontWeight.w600, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.only(left: 28, right: 28, bottom: 8, top: 2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              'Add a page for monitoring.',
              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            TextField(
              controller: nameController,
              decoration: dialogInputDecoration('Page Name (optional)'),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: dialogInputDecoration('Page URL'),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: expectController,
              maxLength: 200,
              decoration: dialogInputDecoration('Expected text in the response (optional)').copyWith(
                helperText: 'The check fails if the response does not contain this exact text '
                    '(case-sensitive, first 64 KiB).',
                helperMaxLines: 4,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: dialogButtonStyle(
                    background: Colors.grey.shade300,
                    foreground: Colors.black87,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: FilledButton(
                  style: dialogButtonStyle(background: _addColor),
                  onPressed: () async {
                    final url = urlController.text.trim();
                    if (url.isEmpty) return;
                    final expected = expectController.text;
                    final name = nameController.text.trim();
                    Navigator.of(dialogContext).pop();
                    // Feedback (success or the reason of failure) is shown by the caller.
                    await onAddUrl(url, name.isEmpty ? null : name, expected);
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ======= DISCORD WEBHOOK DIALOG + VERIFICATION =======
  void _showDiscordWebhookDialog(BuildContext context) {
    final currentWebhook = currentWebhookUrl ?? '';
    final webhookController = TextEditingController(text: currentWebhook);

    showDialogDisposing<void>(
      context,
      disposables: [webhookController],
      builder: (dialogContext) => AlertDialog(
        shape: dialogShape(),
        elevation: 14,
        titlePadding: const EdgeInsets.only(top: 32, left: 24, right: 24, bottom: 6),
        title: Text(
          'Discord Webhook URL',
          style: GoogleFonts.epilogue(fontWeight: FontWeight.w600, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        contentPadding: const EdgeInsets.only(left: 28, right: 28, bottom: 8, top: 2),
        content: TextField(
          controller: webhookController,
          decoration: dialogInputDecoration(
            'Webhook URL',
            hint: 'https://discord.com/api/webhooks/…',
          ),
          keyboardType: TextInputType.url,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: dialogButtonStyle(
                    background: Colors.grey.shade300,
                    foreground: Colors.black87,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 18),
              if (currentWebhook.isNotEmpty) ...[
                Expanded(
                  child: FilledButton(
                    style: dialogButtonStyle(background: Colors.red.shade400),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      final ok = await onSaveDiscordWebhook(null);
                      if (!context.mounted) return;
                      _showMessage(context,
                          ok ? 'Webhook deleted.' : 'Could not delete the webhook.');
                    },
                    child: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 18),
              ],
              Expanded(
                child: FilledButton(
                  style: dialogButtonStyle(background: _discordColor),
                  onPressed: () async {
                    final url = webhookController.text.trim();
                    Navigator.of(dialogContext).pop();
                    if (url.isEmpty || url == currentWebhook) return;
                    await _verifyAndSaveWebhook(context, url);
                  },
                  child: const Text('Verify & Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sends a one-time code to the webhook and saves the webhook only after the
  /// user proves access to the Discord channel by entering the code.
  Future<void> _verifyAndSaveWebhook(BuildContext context, String url) async {
    if (!isDiscordWebhookUrl(url)) {
      _showMessage(context, 'Enter a Discord webhook URL (https://discord.com/api/webhooks/…).');
      return;
    }

    final discordService = DiscordService();
    bool sent;
    try {
      sent = await discordService.sendVerificationCode(url);
    } catch (_) {
      sent = false;
    }
    if (!context.mounted) return;
    if (!sent) {
      _showMessage(context, 'Failed to send the verification code.');
      return;
    }

    final codeController = TextEditingController();
    final verified = await showDialogDisposing<bool>(
      context,
      disposables: [codeController],
      builder: (verifyContext) => AlertDialog(
        title: const Text('Enter Verification Code'),
        content: TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: 'We sent a 4-digit code to your Discord channel.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(verifyContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (discordService.verifyCode(codeController.text.trim())) {
                Navigator.of(verifyContext).pop(true);
              } else {
                ScaffoldMessenger.of(verifyContext).showSnackBar(
                  const SnackBar(content: Text('Invalid code')),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (verified != true) return;
    final ok = await onSaveDiscordWebhook(url);
    if (!context.mounted) return;
    _showMessage(context, ok ? 'Webhook saved.' : 'Could not save the webhook.');
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      textStyle: GoogleFonts.epilogue(fontSize: 16, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Column(
      children: [
        SelectableText(
          'Narrativva Status',
          style: GoogleFonts.epilogue(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        SelectableText(
          'Live status and uptime monitoring for all Narrativva apps and websites.',
          style: GoogleFonts.inter(
            fontSize: 17,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.56),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Page'),
              style: buttonStyle.copyWith(
                backgroundColor: const WidgetStatePropertyAll(_addColor),
              ),
              onPressed: () => _showAddPageDialog(context),
            ),
            FilledButton.icon(
              icon: const FaIcon(FontAwesomeIcons.discord, color: Colors.white, size: 20),
              label: const Text('Set Discord'),
              style: buttonStyle.copyWith(
                backgroundColor: const WidgetStatePropertyAll(_discordColor),
              ),
              onPressed: () => _showDiscordWebhookDialog(context),
            ),
          ],
        ),
      ],
    );
  }
}
