import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_gate.dart';

class StatusCheckerApp extends StatefulWidget {
  const StatusCheckerApp({super.key});

  @override
  State<StatusCheckerApp> createState() => _StatusCheckerAppState();
}

class _StatusCheckerAppState extends State<StatusCheckerApp> {
  static const _themeModeKey = 'themeMode';

  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    if (stored == null || !mounted) return;
    setState(() {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.system,
      );
    });
  }

  /// Toggles between light and dark mode and remembers the choice.
  Future<void> _toggleTheme() async {
    final isDarkNow = _themeMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
        : _themeMode == ThemeMode.dark;
    final newMode = isDarkNow ? ThemeMode.light : ThemeMode.dark;

    setState(() => _themeMode = newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, newMode.name);
  }

  @override
  Widget build(BuildContext context) {
    const subThemes = FlexSubThemesData(
      cardRadius: 20,
      elevatedButtonRadius: 16,
      inputDecoratorRadius: 12,
      defaultRadius: 16,
    );

    return MaterialApp(
      title: 'Narrativva Status',
      debugShowCheckedModeBanner: false,
      theme: FlexThemeData.light(
        scheme: FlexScheme.hippieBlue,
        fontFamily: GoogleFonts.inter().fontFamily,
        subThemesData: subThemes.copyWith(blendOnLevel: 12),
      ).copyWith(
        textTheme: GoogleFonts.interTextTheme(),
        primaryTextTheme: GoogleFonts.epilogueTextTheme(),
      ),
      darkTheme: FlexThemeData.dark(
        scheme: FlexScheme.hippieBlue,
        fontFamily: GoogleFonts.inter().fontFamily,
        subThemesData: subThemes.copyWith(blendOnLevel: 24),
      ).copyWith(
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        primaryTextTheme: GoogleFonts.epilogueTextTheme(ThemeData.dark().textTheme),
      ),
      themeMode: _themeMode,
      home: AuthGate(
        onToggleTheme: _toggleTheme,
        themeMode: _themeMode,
      ),
    );
  }
}
