import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'l10n_test_support.dart';
import 'spec_window.dart';

/// Shared fixtures for the run-setup panel section widget tests. Each section
/// takes only an [AppController], so a section-under-test is pumped directly
/// (no full [RunSetupPanel]) on a panel-sized surface.
///
/// Config layout helpers mirror the [UserVoiceConfigLoader] directory layout:
/// `config.json` is a marker naming nothing, each `providers/<name>.json`
/// carries that provider's `settings` and nothing else, and each
/// `models/<alias>.json` holds a model plus its `defaults`/`pricing`/`voices`
/// and names the provider that serves it.

/// Writes the shared grouped config body onto the directory layout. Specs name
/// their providers as `<name> -> settings`, and each model says which provider
/// serves it — a spec may spell that out with `"provider": "<name>"` in the
/// model, and a model that says nothing belongs to the first provider, so
/// single-provider specs need no bookkeeping.
///
/// There is no `default_model` key, and nothing anywhere lists the models: the
/// default model is the first model of the default provider, which is the first
/// provider holding an `api_key`, and within it the alphabetically first alias.
/// A spec that wants a different one says so by naming a different provider.
void writeConfig(String configDir, Map<String, Object?> body) {
  final models = (body['models'] as Map<String, Object?>?) ?? {};
  final defaults = (body['defaults'] as Map<String, Object?>?) ?? {};
  final pricing = (body['pricing'] as Map<String, Object?>?) ?? {};
  final voices = (body['voices'] as Map<String, Object?>?) ?? {};

  // `narrate` validates the provider block before the first segment, so a
  // fixture without one cannot start a run. Default to a block shaped like the
  // shipped one; a test that cares about the key section passes its own.
  //
  // The shipped `${ENV}` reference is the default here, but it only *resolves*
  // for a controller built with an environment that holds the variable (see
  // [makeController]) — which is why it defaults to an empty map.
  final blocks =
      (body['providers'] as Map<String, Object?>?) ??
      {
        'alpha': {
          'base_url': 'https://vendor.example/api/v1',
          'api_key': r'${VENDOR_API_KEY}',
        },
      };

  final settingsFor = <String, Map<String, Object?>>{};
  final claims = <String, List<String>>{};
  blocks.forEach((name, value) {
    final block = Map<String, Object?>.from(value as Map);
    // A provider file states settings and nothing else. A spec may still say
    // which models belong to it, but only so the models can be attributed
    // without repeating the name on every one of them.
    final own = block.remove('models');
    settingsFor[name] = block;
    claims[name] = [if (own is List) ...own.whereType<String>()];
  });
  final names = settingsFor.keys.toList();

  void writeJson(String subdir, String name, Object? body) {
    final file = File('$configDir/$subdir/$name.json')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder().convert(body));
  }

  // The base layers are replaced wholesale, not merged: with nothing listing
  // them any more, a model file left behind by an earlier call would keep being
  // served, so a spec that narrows the config has to actually lose the models it
  // no longer names. The overlay is the user's own and is left alone.
  for (final subdir in ['models', 'providers']) {
    final dir = Directory('$configDir/$subdir');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  // The marker names nothing at all; it only says this is a voice config dir.
  writeJson('', 'config', <String, Object?>{});
  for (final name in names) {
    writeJson('providers', name, {'settings': settingsFor[name]});
  }
  models.forEach((alias, spec) {
    final m = Map<String, Object?>.from(spec as Map<String, Object?>);
    final dv = defaults[alias];
    final pr = pricing[alias];
    final vo = voices[alias];
    if (dv is String) m['default_voice'] = dv;
    if (pr is Map) m['pricing'] = pr;
    if (vo is Map) m['voices'] = vo;
    final named = m['provider'];
    m['provider'] = named is String ? named : _providerFor(alias, claims, names);
    writeJson('models', alias, m);
  });
}

/// The provider a model spec names: the first one whose spec claims the alias,
/// or the first provider at all when none of them does.
String _providerFor(
  String alias,
  Map<String, List<String>> claims,
  List<String> names,
) {
  for (final name in names) {
    if (claims[name]!.contains(alias)) return name;
  }
  return names.first;
}

/// Builds a controller over [configDir]. Pass [client] to drive narration
/// with a fake instead of the network; omitting it keeps the real client,
/// which is correct for tests that never start a run.
///
/// [environment] defaults to an empty map rather than the process environment,
/// so a test never depends on what the host shell happens to export — the
/// shared fixture's `api_key: "${VENDOR_API_KEY}"` resolves to nothing
/// unless a test opts in.
AppController makeController(
  String configDir, {
  SpeechClient? client,
  Map<String, String>? environment,
}) => AppController(
  loader: UserVoiceConfigLoader(
    configDir: configDir,
    environment: environment ?? const {},
  ),
  client: client,
);

/// Writes the starter fish config so the controller preselects fish with its
/// default voice (as after the first-run download).
void writeFishConfig(String configDir) {
  writeConfig(configDir, {
    'models': {
      'fish': {
        'id': 'fish-audio/s2.1-pro-free:free',
        'formats': ['mp3'],
      },
    },
    'defaults': {'fish': 'British Female Narrator'},
    'voices': {
      'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
    },
  });
}

/// As [writeFishConfig], but with a provider block carrying a *literal* API key
/// rather than the `${VENDOR_API_KEY}` reference [writeConfig] defaults to.
///
/// That is the whole difference, and it is the difference that matters: an
/// unresolved reference yields no key, and `narrate` refuses to start a run
/// without one. So this is the fixture for any test that actually starts a run,
/// where [writeFishConfig] is the right one for tests that only read the config
/// back. [extra] merges into the model file, for the tests whose subject is a
/// capability the plain fish profile does not declare.
void writeRunnableFishConfig(
  String configDir, {
  Map<String, Object?> extra = const {},
}) => writeConfig(configDir, {
  'providers': {
    'alpha': {'base_url': 'https://vendor.example/api/v1', 'api_key': 'sk-test'},
  },
  'models': {
    'fish': {
      'id': 'fish-audio/s2.1-pro-free:free',
      'formats': ['mp3'],
      ...extra,
    },
  },
  'defaults': {'fish': 'British Female Narrator'},
  'voices': {
    'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
  },
});

/// Writes a voice-design config: a model that takes no voice id and writes its
/// narrator from prose instead, the way Qwen3 TTS Voice Design does.
///
/// Declares no `default_voice` and no `voices` on purpose — that is the honest
/// shape for such a model, and it is the shape the GUI has to cope with: no
/// voice to resolve at run time and nothing to show in the voice picker. The
/// language list is there because `lang_code` is a real request field for this
/// model, so the language dropdown still has to reach it.
void writeVoiceDesignConfig(String configDir) {
  writeConfig(configDir, {
    'models': {
      'qwen': {
        'id': 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16',
        'formats': ['wav'],
        'sample_rate': 24000,
        'sends_voice': false,
        'sends_instruct': true,
        'sends_language': true,
        'default_instruct': 'A calm male narrator with a low, steady voice.',
        'default_language': 'English',
        'languages': {'English': 'English', 'Chinese': 'Chinese'},
      },
    },
  });
}

/// Pumps the given run-setup section on a tall panel-sized surface and restores
/// the default test surface afterwards. The height is not the spec default
/// because a run-setup column is meant to scroll.
Future<void> pumpRunSetupSection(WidgetTester tester, Widget child) async {
  await setSpecWindowSize(tester, const Size(1200, 1800));
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
