import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth/magic_link_service.dart';
import 'models/url_entry.dart';
import 'services/supabase_service.dart';
import 'utils/status_utils.dart';
import 'widgets/app_footer.dart';
import 'widgets/dialog_styles.dart';
import 'widgets/online_dot.dart';
import 'widgets/page_status_row.dart';
import 'widgets/timezone_switch.dart';

/// Public status page with a magic-link login.
class LoginPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const LoginPage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final SupabaseService supabaseService = SupabaseService();
  final MagicLinkService magicLinkService = MagicLinkService();
  // Owned by the login dialog (created when it opens, disposed when it closes),
  // so it stays valid even if this page is replaced while the dialog is open.
  TextEditingController emailController = TextEditingController();

  // Loaded once; switching the time zone must not refetch the list.
  late final Future<List<UrlEntry>> _publicPages = supabaseService.loadPublicPages();

  String timezone = kTimezonePrague;
  bool isLoading = false;
  String? message;
  bool isError = false;
  bool _dialogOpen = false;
  int _dialogId = 0; // Identifies the currently open login dialog.

  Future<void> _sendLink(StateSetter dialogSetState) async {
    final email = emailController.text.trim();
    if (email.isEmpty) return;

    final dialogId = _dialogId;
    dialogSetState(() {
      isLoading = true;
      message = null;
    });

    final String? error = await magicLinkService.sendMagicLink(email);
    void update() {
      isError = error != null;
      message = error ?? 'Check your email and click the link to log in.';
      isLoading = false;
    }

    // The dialog may have been closed while the request was running.
    if (_dialogOpen && dialogId == _dialogId) {
      dialogSetState(update);
    } else if (mounted) {
      setState(update);
    }
  }

  void _showLoginDialog() {
    message = null;
    isLoading = false;
    _dialogOpen = true;
    _dialogId++;
    final controller = emailController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            shape: dialogShape(),
            elevation: 14,
            title: Text(
              'Login / Registration',
              style: GoogleFonts.epilogue(fontWeight: FontWeight.w600, fontSize: 22),
              textAlign: TextAlign.center,
            ),
            content: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "You don't need to register – just enter your email and "
                    "we'll send you a login link.",
                    style: GoogleFonts.inter(fontSize: 15, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => isLoading ? null : _sendLink(dialogSetState),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mail_outline),
                      label: Text(
                        'Send magic link',
                        style: GoogleFonts.epilogue(fontWeight: FontWeight.w600),
                      ),
                      onPressed: isLoading ? null : () => _sendLink(dialogSetState),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: GoogleFonts.epilogue(fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      message!,
                      style: GoogleFonts.inter(
                        color: isError
                            ? Theme.of(context).colorScheme.error
                            : Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _dialogOpen = false;
      controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On phones the clock is hidden so the login button still fits.
                final compact = constraints.maxWidth <= 450;
                return Row(
                  children: [
                    const Spacer(),
                    TimezoneSwitchWidget(
                      selectedTimezone: timezone,
                      onChanged: (tz) => setState(() => timezone = tz),
                      compact: compact,
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: Icon(
                        widget.themeMode == ThemeMode.dark
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        size: 25,
                      ),
                      onPressed: widget.onToggleTheme,
                      tooltip: 'Switch light/dark theme',
                    ),
                    IconButton(
                      icon: const Icon(Icons.login),
                      onPressed: _showLoginDialog,
                      tooltip: 'Login',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: EdgeInsets.symmetric(
              vertical: constraints.maxWidth < 650 ? 36 : 70,
            ),
            children: [
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: SelectableText(
                          'Narrativva Status',
                          style: GoogleFonts.epilogue(
                            fontWeight: FontWeight.w800,
                            fontSize: 38,
                            letterSpacing: -1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const OnlineDot(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SelectableText(
                      'Live status and uptime monitoring for all Narrativva apps and websites.',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
              FutureBuilder<List<UrlEntry>>(
                future: _publicPages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 40.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final publicPages = snapshot.data ?? const <UrlEntry>[];
                  if (publicPages.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 40.0),
                      child: Center(
                        child: Text(
                          'No public pages available.',
                          style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final page in publicPages)
                            PageStatusRowWidget(
                              key: ValueKey(page.id),
                              page: page,
                              timezone: timezone,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const AppFooter(),
            ],
          );
        },
      ),
    );
  }
}
