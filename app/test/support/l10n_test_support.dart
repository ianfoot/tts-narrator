// Test-only helpers for reaching the English `AppLocalizations` outside a
// widget tree.
//
// Tests used to import the generated `TextTokens` constants directly. Strings
// now come from `AppLocalizations`, whose `of(context)` requires a mounted
// `AppLocalizations` delegate. Most assertions only need the string *values*
// (to match a `find.text(...)`), so they can bypass the widget tree entirely
// with [testL10n].
//
// Widget tests that need a real delegate in scope should wrap the widget under
// test with `localizationsDelegates` + `supportedLocales` — see [testApp] and
// [testLocalizationsDelegates] below.

import 'package:flutter/cupertino.dart';
import 'package:tts_narrator/l10n/app_localizations.dart';

/// The English localizations, for assertions that just need string values.
AppLocalizations get testL10n => lookupAppLocalizations(const Locale('en'));

/// Parses a `en`, `en_US`, or `en-US` style tag into a [Locale].
Locale localeFromTag(String tag) {
  final normalized = tag.replaceAll('_', '-');
  final dash = normalized.indexOf('-');
  if (dash == -1) return Locale(normalized);
  return Locale(normalized.substring(0, dash), normalized.substring(dash + 1));
}

/// The production delegate set, for tests that build their own `CupertinoApp`.
const testLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  DefaultWidgetsLocalizations.delegate,
  DefaultCupertinoLocalizations.delegate,
];

/// Locales the generated localizations support, for tests that build their own
/// `MaterialApp`/`CupertinoApp` rather than using [testApp].
const testSupportedLocales = AppLocalizations.supportedLocales;

/// A `CupertinoApp` with the app's localization delegates wired up, so widgets
/// calling `AppLocalizations.of(context)` resolve.
///
/// Prefer this over a bare `CupertinoApp` in any test that mounts a widget
/// under test — `of(context)` is non-nullable and throws when no delegate is in
/// scope, which is exactly the wiring bug this would otherwise hide.
Widget testApp({Widget? home}) => CupertinoApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: home,
);
