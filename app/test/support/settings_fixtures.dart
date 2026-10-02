import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'l10n_test_support.dart';

/// Shared fixtures for the settings-rail section widget tests. Each section
/// takes only an [AppController], so a section-under-test is pumped directly
/// (no full [SettingsPanel]) on a rail-sized surface.
///
/// Config layout helpers mirror the flat-loading [UserVoiceConfigLoader]: the
/// global keys (`default_model`, `providers`) land in `config.json` and each
/// `models` entry plus its `defaults`/`pricing`/`voices` land in `<alias>.json`.

/// Writes the shared grouped config body onto the flat layout. Specs without a
/// `provider` default to `openrouter` so model files stay valid.
void writeConfig(String configDir, Map<String, Object?> body) {
  final global = <String, Object?>{
    if (body['default_model'] != null) 'default_model': body['default_model'],
    if (body['providers'] != null) 'providers': body['providers'],
  };
  File('$configDir/config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder().convert({
        ...global,
        // `narrate` validates the provider block before the first segment, so
        // a fixture without one cannot start a run. Default to a block shaped
        // like the shipped `config.json`; a test that cares about the key
        // section can still pass its own `providers`.
        'providers':
            global['providers'] ??
            {
              'openrouter': {
                'base_url': 'https://openrouter.ai/api/v1',
                'api_key_env': 'OPENROUTER_API_KEY',
              },
            },
      }),
    );

  final models = (body['models'] as Map<String, Object?>?) ?? {};
  if (models.isEmpty) return;
  final defaults = (body['defaults'] as Map<String, Object?>?) ?? {};
  final pricing = (body['pricing'] as Map<String, Object?>?) ?? {};
  final voices = (body['voices'] as Map<String, Object?>?) ?? {};
  Directory(configDir).createSync(recursive: true);
  models.forEach((alias, spec) {
    final m = Map<String, Object?>.from(spec as Map<String, Object?>);
    m.putIfAbsent('provider', () => 'openrouter');
    final dv = defaults[alias];
    final pr = pricing[alias];
    final vo = voices[alias];
    if (dv is String) m['default_voice'] = dv;
    if (pr is Map) m['pricing'] = pr;
    if (vo is Map) m['voices'] = vo;
    File('$configDir/$alias.json')
        .writeAsStringSync(const JsonEncoder().convert(m));
  });
}

/// Builds a controller over [configDir]. Pass [client] to drive narration
/// with a fake instead of the network; omitting it keeps the real client,
/// which is correct for tests that never start a run.
AppController makeController(String configDir, {SpeechClient? client}) =>
    AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      client: client,
    );

/// Writes the starter fish config so the controller preselects fish with its
/// default voice (as after the first-run download).
void writeFishConfig(String configDir) {
  writeConfig(configDir, {
    'default_model': 'fish',
    'models': {
      'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
    },
    'defaults': {'fish': 'British Female Narrator'},
    'voices': {
      'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
    },
  });
}

/// Pumps the given settings-rail section on a rail-sized surface (the same
/// 1200x1800 logical size the full settings rail tests use) and restores the
/// default surface when the test ends.
Future<void> pumpSettingsSection(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// Expands the collapsed "Advanced Voice ID" disclosure.
Future<void> expandVoiceRaw(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('voiceAdvancedDisclosure')),
      matching: find.text('Advanced Voice ID'),
    ),
  );
  await tester.pump();
}

/// Expands the collapsed "API key" disclosure (the tappable header row, not
/// the whole disclosure).
Future<void> expandApiKey(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('apiKeyDisclosure')),
      matching: find.text('API key'),
    ),
  );
  await tester.pump();
}
