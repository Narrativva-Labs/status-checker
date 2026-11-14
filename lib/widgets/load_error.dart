import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inline error message with a retry button.
class LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const LoadError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.error),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
