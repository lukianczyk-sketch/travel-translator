import 'package:flutter/material.dart';

const appVersion = '0.5.0';

/// Palette: deep midnight base, electric coral for "them", cyan for "you".
class Palette {
  static const bg = Color(0xFF0B0F1A);
  static const bg2 = Color(0xFF131A2B);
  static const card = Color(0xFF1A2236);
  static const them = Color(0xFFFF5C5C);
  static const themSoft = Color(0xFF3A1A22);
  static const you = Color(0xFF22D3EE);
  static const youSoft = Color(0xFF0F2E38);
  static const gold = Color(0xFFFFC857);
  static const text = Color(0xFFF5F7FA);
  static const muted = Color(0xFF8A94A8);
  static const ok = Color(0xFF34D399);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.you,
      secondary: Palette.them,
      surface: Palette.card,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
      fontFamily: 'Roboto',
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Palette.text,
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.card,
      contentTextStyle: TextStyle(color: Palette.text, fontSize: 16),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

const headline = TextStyle(
  fontSize: 34,
  fontWeight: FontWeight.w900,
  letterSpacing: -1,
  height: 1.05,
);
