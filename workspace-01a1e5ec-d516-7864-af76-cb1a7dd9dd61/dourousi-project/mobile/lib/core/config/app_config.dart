import 'package:flutter/material.dart';

class AppConfig {
  AppConfig._();

  static const String appName = 'Dourousi';
  static const String appVersion = '1.0.0';
  static const String developerName = 'حمزة شعيب (Hamza Chouaib)';
  static const String algeriaDialCode = '+213';

  /// Configured via `--dart-define=API_BASE_URL=https://api.dourousi.app` in production builds.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.dourousi.app',
  );

  /// Deep link host for verified Android App Links & iOS Universal Links.
  static const String deepLinkHost = 'dourousi.app';

  /// Biometric grace period when switching briefly away from the app.
  static const Duration backgroundLockGracePeriod = Duration(seconds: 15);

  /// Validates Algerian mobile phone input (05 / 06 / 07) and returns normalized E.164 (+213[567]XXXXXXXX) or null.
  static String? normalizeAlgerianMobile(String rawInput) {
    final cleaned = rawInput.replaceAll(RegExp(r'[\s\-().]'), '').trim();
    if (cleaned.isEmpty) return null;

    // Reject any non-Algerian international prefix
    if (cleaned.startsWith('+') && !cleaned.startsWith('+213')) return null;
    if (cleaned.startsWith('00') && !cleaned.startsWith('00213')) return null;

    String nineDigits;
    if (cleaned.startsWith('+213')) {
      nineDigits = cleaned.substring(4);
    } else if (cleaned.startsWith('00213')) {
      nineDigits = cleaned.substring(5);
    } else if (cleaned.startsWith('213') && cleaned.length == 12) {
      nineDigits = cleaned.substring(3);
    } else if (cleaned.startsWith('0') && cleaned.length == 10) {
      nineDigits = cleaned.substring(1);
    } else if (cleaned.length == 9) {
      nineDigits = cleaned;
    } else {
      return null;
    }

    if (nineDigits.length == 10 && nineDigits.startsWith('0')) {
      nineDigits = nineDigits.substring(1);
    }

    final e164 = '+213$nineDigits';
    final regex = RegExp(r'^\+213[567]\d{8}$');
    return regex.hasMatch(e164) ? e164 : null;
  }
}

class AppTheme {
  AppTheme._();

  static const Color primaryEmerald = Color(0xFF0D9488);
  static const Color deepSlate = Color(0xFF0F172A);

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryEmerald,
      brightness: Brightness.light,
      primary: primaryEmerald,
      surface: const Color(0xFFF8FAFC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      appBarTheme: const AppBarTheme(
        backgroundColor: deepSlate,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryEmerald, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryEmerald,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
