import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLocalizations {
  final Locale locale;
  final Map<String, String> _strings;

  const AppLocalizations(this.locale, this._strings);

  static const supportedLocales = <Locale>[
    Locale('ar'),
    Locale('fr'),
    Locale('en'),
  ];

  static AppLocalizations of(BuildContext context) {
    final instance = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(instance != null, 'AppLocalizations not found in widget tree');
    return instance!;
  }

  String tr(String key) => _strings[key] ?? key;

  bool get isRtl => locale.languageCode == 'ar';

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'fr', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final code = isSupported(locale) ? locale.languageCode : 'ar';
    final rawJson = await rootBundle.loadString('assets/translations/$code.json');
    final decoded = json.decode(rawJson) as Map<String, dynamic>;
    final strings = decoded.map((k, v) => MapEntry(k, v.toString()));
    return AppLocalizations(Locale(code), strings);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

/// Manages UI language ('ar' | 'fr' | 'en') cleanly via Riverpod.
class UiLocaleNotifier extends StateNotifier<Locale> {
  UiLocaleNotifier() : super(const Locale('ar'));

  void setLanguageCode(String code) {
    if (['ar', 'fr', 'en'].contains(code)) {
      state = Locale(code);
    }
  }
}

final uiLocaleProvider = StateNotifierProvider<UiLocaleNotifier, Locale>((ref) {
  return UiLocaleNotifier();
});
