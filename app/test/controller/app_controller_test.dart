import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import '../support/fake_tts_provider.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_controller_test_');
    configPath = '${dir.path}/voice_config.json';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void writeConfig(Map<String, Object?> body) {
    File(configPath).writeAsStringSync(const JsonEncoder().convert(body));
  }

  AppController makeController() =>
      AppController(loader: VoiceConfigLoader(configPath: configPath));

  group('cold start', () {
    test('boots an empty, untitled document on the fish default', () {
      final c = makeController();
      expect(c.text, isEmpty);
      expect(c.documentName, 'untitled.txt');
      expect(c.dirty, isFalse);
      expect(c.wordCount, 0);
      expect(c.charCount, 0);
      expect(c.plannedChunks, isEmpty);
      expect(c.profile.alias, kDefaultProfile.profile.alias);
      expect(c.modelAlias, kDefaultProfile.profile.alias);
      expect(c.voice, kDefaultProfile.voice);
      expect(c.voiceLabel, kDefaultProfile.voiceLabel);
    });

    test('a missing config file degrades to the compiled fish bootstrap', () {
      final c = AppController(
        loader: VoiceConfigLoader(configPath: '${dir.path}/nope/config.json'),
      );
      expect(c.profile.alias, 'fish');
      expect(c.voice, kDefaultProfile.voice);
    });
  });

  group('document', () {
    test('setText replaces the text and marks the document dirty', () {
      final c = makeController();
      c.setText('The rain fell on the quiet street.');
      expect(c.text, 'The rain fell on the quiet street.');
      expect(c.dirty, isTrue);
      expect(c.wordCount, 7);
      expect(c.charCount, 'The rain fell on the quiet street.'.length);
      // No paragraphs -> no plan yet.
      expect(c.plannedChunks, hasLength(1));
    });

    test('setText with identical value is ignored', () {
      final c = makeController();
      c.setText('Hello');
      expect(c.dirty, isTrue);
      c.setText('Hello');
      expect(c.documentName, 'untitled.txt');
    });

    test('loadFromFile reads the file, sets the path, clears the dirty flag', () {
      final story = File('${dir.path}/story.txt')
        ..writeAsStringSync('Once upon a time there was a very long story.');
      final c = makeController();
      c.loadFromFile(story.path);
      expect(c.text, 'Once upon a time there was a very long story.');
      expect(c.documentPath, story.absolute.path);
      expect(c.documentName, 'story.txt');
      expect(c.dirty, isFalse);
      expect(c.narrateBlockReason(), isNull);
    });

    test('loadFromFile throws when the file is missing', () {
      final c = makeController();
      expect(
        () => c.loadFromFile('${dir.path}/missing.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('buildConfig', () {
    test('narrates from in-memory text with an untitled input path', () {
      writeConfig({
        'providers': {
          'openrouter': {'api_key': 'sk-test'},
        },
      });
      final c = makeController()..setText('Hello world. Some more words here.');
      final cfg = c.buildConfig();
      expect(cfg.sourceText, 'Hello world. Some more words here.');
      expect(cfg.inputPath, 'untitled.txt');
      expect(cfg.profile.alias, 'fish');
      expect(cfg.voice, kDefaultProfile.voice);
      expect(cfg.providerSettings['api_key'], 'sk-test');
      expect(cfg.pricing, freePricing);
    });

    test('documents use the real path for output naming', () {
      writeConfig({});
      final story = File('${dir.path}/my chapter.txt')
        ..writeAsStringSync('A chapter with enough words to narrate.');
      final c = makeController()..loadFromFile(story.path);
      final cfg = c.buildConfig();
      expect(cfg.sourceText, 'A chapter with enough words to narrate.');
      expect(cfg.inputPath, story.absolute.path);
      expect(inputStem(cfg.inputPath), 'my_chapter');
    });

    test('throws a FormatException when the model has no selected voice', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
      });
      final c = makeController();
      c.changeModel('gemini');
      expect(c.voice, isEmpty);
      expect(() => c.buildConfig(), throwsFormatException);
    });
  });

  group('model & voice', () {
    test('changeModel resets the voice to the new model default', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {
          'gemini': 'Charon',
        },
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      c.changeModel('gemini');
      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'CN2pVME9cDEeMRXJzcMPYj0p');
      expect(c.voiceLabel, 'Charon');
    });

    test('a user-set raw voice survives a model switch', () {
      writeConfig({
        'models': {
          'gemini': {
            'id': 'google/gemini-3.1-flash-tts-preview',
            'format': 'pcm',
            'sample_rate': 24000,
            'prompt_style': true,
          },
        },
        'defaults': {
          'gemini': 'Charon',
        },
        'voices': {
          'gemini': {'Charon': 'CN2pVME9cDEeMRXJzcMPYj0p'},
        },
      });
      final c = makeController();
      c.setVoice('my_custom_voice');
      c.changeModel('gemini');
      expect(c.voice, 'my_custom_voice');
    });

    test('resolveVoice wires a friendly alias to its raw id', () {
      writeConfig({
        'voices': {
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController();
      c.applyVoiceLabel('Narrator');
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
    });
  });

  group('narrate guard', () {
    test('blocks on empty text', () {
      final c = makeController();
      expect(c.narrateBlockReason(), contains('Nothing to narrate yet'));
    });

    test('allows narration with text present', () {
      final c = makeController()..setText('Hello world. Enough words.');
      expect(c.narrateBlockReason(), isNull);
    });

    test('blocks re-entrancy once a run starts', () async {
      final c = makeController()..setText('Hello world. Enough words.');
      final fake = FakeTtsProvider()..register();
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      expect(c.narrateBlockReason(), contains('already running'));
      // Let the single fake chunk land.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      expect(fake.callCount, 1);
    });

    test('command slots start unwired', () {
      final c = makeController();
      expect(c.onOpen, isNull);
      expect(c.onNarrate, isNull);
      expect(c.onCancel, isNull);
      expect(c.onPreferences, isNull);
    });
  });

  group('estimate', () {
    test('plans and estimates update with the text', () {
      final c = makeController();
      c.setText(
        'The rain fell on the quiet street. Lights glowed behind the windows. '
        'It was an evening of small, patient sounds. The story drifted on for '
        'a while, unhurried and calm.',
      );
      final chunks = c.plannedChunks;
      expect(chunks, isNotEmpty);
      expect(c.estimatedMinutes, greaterThan(0));
      expect(c.estimatedCostUsd, 0); // fish is free.
    });
  });
}