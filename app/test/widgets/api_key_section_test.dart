import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:tts_narrator/src/gui/controller/api_key_store.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/controller/settings_controller.dart'
    show ApiKeySource;
import 'package:tts_narrator/src/gui/platform/widgets/platform_button.dart';
import 'package:tts_narrator/src/gui/settings/api_key_section.dart';
import 'package:tts_narrator/src/gui/theme/app_text_tokens.dart';

import '../support/settings_fixtures.dart';

/// A key store whose writes always fail, standing in for an unreachable
/// keychain / Secret Service.
class _FailingApiKeyStore extends ApiKeyStore {
  @override
  Future<void> save(String key) async {
    throw StateError('key store unreachable');
  }

  @override
  Future<void> remove() async {
    throw StateError('key store unreachable');
  }
}

/// Resets the mock keychain between tests so a stored key never leaks.
void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_api_key_section_');
    configDir = '${dir.path}/cfg';
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester, AppController c) =>
      pumpSettingsSection(tester, ApiKeySection(controller: c));

  PlatformButton buttonWith(WidgetTester tester, String key) =>
      tester.widget<PlatformButton>(find.byKey(Key(key)));

  testWidgets('shows "Not set" and a disabled Remove when no key exists', (
    tester,
  ) async {
    writeFishConfig(configDir); // no providers block -> no config/env key.
    final c = makeController(configDir);
    await pumpSection(tester, c);

    // Collapsed by default: the caption mirrors the status.
    expect(find.byKey(const Key('apiKeyField')), findsNothing);
    expect(find.text('Not set'), findsOneWidget);
    // The section header carries a tooltip explaining what the key is for.
    expect(
      find.byTooltip(TextTokens.gui_settings_apiKeySectionTooltip),
      findsOneWidget,
    );

    await expandApiKey(tester);

    expect(find.byKey(const Key('apiKeyField')), findsOneWidget);
    // The empty field shows a placeholder so the input area stays visible
    // against the dark rail background.
    expect(
      find.text(TextTokens.gui_settings_apiKeyFieldPlaceholder),
      findsOneWidget,
    );
    expect(find.text('Not set'), findsOneWidget);
    expect(buttonWith(tester, 'apiKeySaveButton').onPressed, isNotNull);
    expect(buttonWith(tester, 'apiKeyRemoveButton').onPressed, isNull);
  });

  testWidgets('saving a key flips the status to keychain and enables Remove', (
    tester,
  ) async {
    writeFishConfig(configDir);
    final c = makeController(configDir);
    await pumpSection(tester, c);
    await expandApiKey(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
      'sk-gui-saved',
    );
    await tester.tap(find.byKey(const Key('apiKeySaveButton')));
    await tester.pumpAndSettle();

    expect(c.hasStoredApiKey, isTrue);
    expect(c.apiKeySource, ApiKeySource.keychain);
    expect(find.text('Stored in keychain'), findsOneWidget);
    expect(buttonWith(tester, 'apiKeyRemoveButton').onPressed, isNotNull);
    // The secret never lingers in the edit box.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);

    // Removing clears the store and reverts the status.
    await tester.tap(find.byKey(const Key('apiKeyRemoveButton')));
    await tester.pumpAndSettle();
    expect(c.hasStoredApiKey, isFalse);
    expect(c.apiKeyMissing, isTrue);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('a key-store failure reports an error and keeps the input', (
    tester,
  ) async {
    writeFishConfig(configDir);
    final c = AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      apiKeyStore: _FailingApiKeyStore(),
    );
    await pumpSection(tester, c);
    await expandApiKey(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
      'sk-wont-save',
    );
    await tester.tap(find.byKey(const Key('apiKeySaveButton')));
    await tester.pumpAndSettle();

    // The failure lands on the status row instead of surfacing as an
    // unhandled async error, and the typed key stays editable.
    expect(find.text(TextTokens.gui_settings_apiKeyStoreError), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('apiKeyField')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'sk-wont-save');
    expect(c.hasStoredApiKey, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unset \${ENV} config ref still narrates via a stored key', (
    tester,
  ) async {
    writeConfig(configDir, {
      'default_model': 'fish',
      'providers': {
        'openrouter': {'OPENROUTER_API_KEY': r'${TTS_NARRATOR_NOT_SET}'},
      },
      'models': {
        'fish': {'id': 'fish-audio/s2.1-pro-free:free', 'format': 'mp3'},
      },
      'defaults': {'fish': 'British Female Narrator'},
      'voices': {
        'fish': {'British Female Narrator': '89f41ea230034706881f85a8227d6ab9'},
      },
    });
    FlutterSecureStorage.setMockInitialValues({
      'openrouter_api_key': 'sk-stored',
    });
    final store = ApiKeyStore();
    await store.load();
    final c = AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      apiKeyStore: store,
    );
    await pumpSection(tester, c);

    // "Stored in keychain" shows as the collapsed caption.
    expect(find.text('Stored in keychain'), findsOneWidget);
    expect(c.buildConfig().providerSettings['OPENROUTER_API_KEY'], 'sk-stored');
  });
}
