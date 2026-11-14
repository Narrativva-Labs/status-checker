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
