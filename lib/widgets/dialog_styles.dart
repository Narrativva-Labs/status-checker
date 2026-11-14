import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared look of the app's dialogs.
ShapeBorder dialogShape() => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: Colors.white.withValues(alpha: 0.28),
        width: 2.0,
      ),
    );

InputDecoration dialogInputDecoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
    );

ButtonStyle dialogButtonStyle({
  required Color background,
  Color foreground = Colors.white,
}) =>
    FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(vertical: 18),
      textStyle: GoogleFonts.epilogue(fontSize: 16, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Shows a dialog and disposes [disposables] (e.g. text controllers) once
/// the dialog's exit animation has finished, when nothing uses them anymore.
Future<T?> showDialogDisposing<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required List<ChangeNotifier> disposables,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  route.completed.whenComplete(() {
    for (final disposable in disposables) {
      disposable.dispose();
    }
  });
  return navigator.push(route);
}
