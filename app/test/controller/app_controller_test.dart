import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/controller/config_loader.dart';
import 'package:tts_narrator/src/gui/theme/app_tokens.dart' show AppThemeMode;
import '../support/fake_tts_provider.dart';

void main() {
  late Directory dir;
  late String configDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_controller_test_');
    configDir = '${dir.path}/cfg';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes the shared grouped config body onto the flat layout: global keys
  /// (`default_model`, `providers`) to config.json, and each `models` entry
  /// plus its `defaults`/`pricing`/`voices` to <alias>.json. Specs without a
  /// `provider` default to `openrouter` so model files stay valid.
  void writeConfig(Map<String, Object?> body) {
    final global = <String, Object?>{
      if (body['default_model'] != null) 'default_model': body['default_model'],
      if (body['providers'] != null) 'providers': body['providers'],
    };
    File('$configDir/config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder().convert(global));

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

  AppController makeController() =>
      AppController(loader: VoiceConfigLoader(configDir: configDir));

  group('cold start', () {
    test('boots an empty, untitled document on the fish default', () {
      final c = makeController();
      expect(c.text, isEmpty);
      expect(c.documentName, 'untitled.txt');
      expect(c.dirty, isFalse);
      expect(c.wordCount, 0);
      expect(c.charCount, 0);
      expect(c.plannedSegments, isEmpty);
      expect(c.profile.alias, kDefaultProfile.profile.alias);
      expect(c.modelAlias, kDefaultProfile.profile.alias);
      expect(c.voice, kDefaultProfile.voice);
      expect(c.voiceLabel, kDefaultProfile.voiceLabel);
    });

    test('a missing config file degrades to the compiled fish bootstrap', () {
      final c = AppController(
        loader: VoiceConfigLoader(configDir: '${dir.path}/nope'),
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
      expect(c.plannedSegments, hasLength(1));
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

  group('save', () {
    test('saveTo writes the text, adopts the path and clears the dirty flag', () {
      final c = makeController()..setText('Saved text. Enough words to count.');
      final target = File('${dir.path}/saved.txt');
      c.saveTo(target.path);
      expect(File(target.absolute.path).readAsStringSync(), c.text);
      expect(c.documentPath, target.absolute.path);
      expect(c.documentName, 'saved.txt');
      expect(c.dirty, isFalse);
    });

    test('saveAs picks a location, writes and adopts it', () async {
      final c = makeController()..setText('Via save as. Enough words.');
      c.saveLocationPicker = () async => '${dir.path}/picked.txt';
      await c.saveAs();
      expect(File('${dir.path}/picked.txt').readAsStringSync(), c.text);
      expect(c.documentPath, '${dir.path}/picked.txt');
      expect(c.dirty, isFalse);
    });

    test('saveAs with a cancelled picker leaves the path untouched', () async {
      final c = makeController()..setText('Not saved. Enough words.');
      c.saveLocationPicker = () async => null;
      await c.saveAs();
      expect(c.documentPath, isNull);
      expect(c.dirty, isTrue);
    });

    test('save on a titled document writes without picking', () async {
      final c = makeController()..setText('Direct save. Enough words.');
      final target = File('${dir.path}/direct.txt');
      c.saveTo(target.path);
      c.setText('Updated. Enough words to narrate.');
      var picked = false;
      c.saveLocationPicker = () async {
        picked = true;
        return null;
      };
      await c.save();
      expect(picked, isFalse);
      expect(File(target.absolute.path).readAsStringSync(), c.text);
      expect(c.dirty, isFalse);
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

    test('a preserved raw voice drops the previous model label on switch', () {
      writeConfig({
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
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
          'fish': {'Narrator': 'hex123'},
        },
      });
      final c = makeController();
      c.applyVoiceLabel('Narrator'); // fish alias -> hex123, label Narrator.
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, 'Narrator');
      // gemini's default differs, so the raw voice survives; the fish label
      // must not ride along to a foreign id.
      c.changeModel('gemini');
      expect(c.modelAlias, 'gemini');
      expect(c.voice, 'hex123');
      expect(c.voiceLabel, isNull);
    });

    test('resolveVoice wires a friendly alias to its raw id', () {
      writeConfig({
        'models': {
          'fish': {'id': 'fish-audio/s2.1-pro-free', 'format': 'mp3'},
        },
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

  group('voice gender', () {
    void writeKokoro() {
      writeConfig({
        'models': {
          'kokoro': {'id': 'hexgrad/kokoro-82m', 'format': 'mp3'},
        },
        'defaults': {
          'kokoro': 'Emma',
        },
        'voices': {
          'kokoro': {
            'Alice': {'id': 'bf_alice', 'gender': 'female'},
            'Daniel': {'id': 'bm_daniel', 'gender': 'male'},
            'Emma': {'id': 'bf_emma', 'gender': 'female'},
            'Fable': {'id': 'bm_fable', 'gender': 'male'},
          },
        },
      });
    }

    void writeGemini() {
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
          'gemini': {'Charon': 'Charon'},
        },
      });
    }

    test('hasGenderTags is true when a model tags voices', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.hasGenderTags, isTrue);
    });

    test('an untagged model has no gender tags', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      expect(c.hasGenderTags, isFalse);
    });

    test('the gender filter narrows voiceItems and appends shorthand', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.voiceItems.map((e) => e.$1), containsAll(['Emma', 'Daniel']));
      c.voiceGenderFilter = VoiceGender.male;
      expect(
        c.voiceItems.map((e) => e.$1),
        unorderedEquals(['Daniel', 'Fable']),
      );
      expect(
        c.voiceItems.map((e) => e.$2),
        containsAll(['Daniel (m)', 'Fable (m)']),
      );
    });

    test('setting a gender filter auto-selects a matching voice', () {
      writeKokoro();
      final c = makeController()..changeModel('kokoro');
      expect(c.voiceLabel, 'Emma'); // default is female
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceLabel, 'Daniel'); // first male entry
      c.voiceGenderFilter = null;
      expect(c.voiceLabel, 'Daniel'); // resetting the filter keeps the pick
    });

    test('changeModel resets the gender filter', () {
      writeKokoro();
      writeGemini();
      final c = makeController()..changeModel('kokoro');
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceGenderFilter, VoiceGender.male);
      c.changeModel('fish');
      expect(c.voiceGenderFilter, isNull);
    });

    test('changing gender tweaks the narrator phrase on gemini', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      expect(c.passagePrefix, contains('female narrator'));
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, contains('male narrator'));
      expect(c.passagePrefix, isNot(contains('female narrator')));
      c.voiceGenderFilter = VoiceGender.female;
      expect(c.passagePrefix, contains('female narrator'));
    });

    test('gender never rewrites a custom prefix without the exact phrase', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      c.passagePrefix = 'Read this in a hushed tone.';
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, 'Read this in a hushed tone.');
    });

    test('selecting any reverts the narrator phrase on gemini', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      final defaultPrefix = c.passagePrefix;
      expect(defaultPrefix, contains('female narrator'));
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.passagePrefix, contains('male narrator'));
      c.voiceGenderFilter = null;
      expect(c.passagePrefix, defaultPrefix);
    });

    test('male narrator is not mistaken inside a female phrase', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      // The default prefix already says "female narrator"; selecting Female
      // must not treat that phrase's 'male narrator' substring as a male one.
      c.voiceGenderFilter = VoiceGender.female;
      expect(c.passagePrefix, contains('female narrator'));
      expect(c.voiceGenderFilter, VoiceGender.female);
      // Reverting to Any is likewise a no-op on the default phrase.
      c.voiceGenderFilter = null;
      expect(c.passagePrefix, contains('female narrator'));
    });

    test('a gender with no matching voices reverts the filter to any', () {
      writeConfig({
        'models': {
          'single': {'id': 'example/single', 'format': 'mp3'},
        },
        'defaults': {
          'single': 'Alice',
        },
        'voices': {
          'single': {
            'Alice': {'id': 'a', 'gender': 'female'},
            'Beth': {'id': 'b', 'gender': 'female'},
          },
        },
      });
      final c = makeController()..changeModel('single');
      expect(c.hasGenderTags, isTrue);
      c.voiceGenderFilter = VoiceGender.male;
      // No male voices: rather than leave a voice hidden behind an empty
      // filter, the pick reverts to "any" and the full list stays available.
      expect(c.voiceGenderFilter, isNull);
      expect(c.voiceItems.map((e) => e.$1), unorderedEquals(['Alice', 'Beth']));
      expect(c.voiceLabel, 'Alice');
    });

    test('gender on an untagged model leaves the voice list untouched', () {
      writeGemini();
      final c = makeController()..changeModel('gemini');
      final before = c.voiceItems.map((e) => e.$1).toList();
      c.voiceGenderFilter = VoiceGender.male;
      expect(c.voiceItems.map((e) => e.$1), before);
      expect(c.voiceLabel, 'Charon'); // no auto-switch; default stays
    });
  });

  group('narrate guard', () {
    test('blocks on empty text', () {
      final c = makeController();
      expect(c.narrateBlockReason(), contains('Editor text is empty'));
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
      // Let the single fake segment land.
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

  group('run state', () {
    test('sampleLen sizes the segment plan so progress completes at 100%', () async {
      final c = makeController();
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      final fake = FakeTtsProvider()..register();
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.totalSegments, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.runDoneCount, 1);
      expect(c.runProgress, 1.0);
      expect(fake.callCount, 1);
    });

    test('cancelling a run clears the in-flight segment spinner', () async {
      final c = makeController();
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      FakeTtsProvider().register();
      c.outDir = dir.path;
      c.startRun();
      c.cancelRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runStopped, isTrue);
      expect(c.narrating, isFalse);
      expect(c.runSegments.every((segment) => !segment.running), isTrue);
    });

    test('a successful run records the combined track path', () async {
      final c = makeController();
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      FakeTtsProvider().register();
      c.outDir = dir.path;
      expect(c.completedAudioPath, isNull);
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      final path = c.completedAudioPath;
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, endsWith('untitled_full.mp3'));
    });

    test('a cancelled run never records a combined track path', () async {
      final c = makeController();
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      FakeTtsProvider().register();
      c.outDir = dir.path;
      c.startRun();
      c.cancelRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runStopped, isTrue);
      expect(c.completedAudioPath, isNull);
    });

    test('cancelRun makes narration idle immediately', () async {
      final c = makeController();
      c.setText(
        'First paragraph with enough words to become its own segment and then '
        'carry on a little longer to cross the minimum.\n\n'
        'Second paragraph with enough words to become its own segment as well '
        'and then carry on a little longer to cross the minimum.',
      );
      final fake = FakeTtsProvider();
      final gate = Completer<void>();
      fake.gate = gate;
      fake.register();
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      // Cancel must release the controller immediately: a new run can start
      // while the cancelled request is still unwinding, with no "already
      // running" guard left over.
      c.cancelRun();
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      // Let the abandoned request settle and confirm the controller stays idle.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.narrating, isFalse);
      expect(c.narrateBlockReason(), isNull);
      expect(c.runStopped, isTrue);
    });

    test('a successor run is not clobbered by the cancelled predecessor',
        () async {
      final c = makeController();
      c.setText(
        'First paragraph with enough words to become its own segment on its '
        'own, carrying straight past the minimum without needing any company '
        'from a neighbouring paragraph. It simply keeps going until it clears '
        'the bar here.\n\n'
        'Second paragraph with enough words to become its own segment as well, '
        'also carrying well past the minimum so it does not fuse with anything '
        'around it either. It clears the bar all by itself just the same.',
      );
      final fake = FakeTtsProvider();
      final gate = Completer<void>();
      fake.gate = gate;
      fake.register();
      c.outDir = dir.path;
      c.sampleLen = null;
      // Run A: gated mid-flight, then cancelled.
      c.startRun();
      c.cancelRun();
      // Run B: starts while A's request is still in flight (gate not yet
      // released), and must finish cleanly.
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);
      // Release A's stale request; its unwind must not mark B stopped, blank
      // its progress, or drop its combined track.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.runStopped, isFalse);
      expect(c.narrating, isFalse);
      expect(c.runDoneCount, 2);
      expect(c.runError, isNull);
      expect(c.completedAudioPath, isNotNull);
    });

    test('starting a new run clears a prior completed track path', () async {
      final c = makeController();
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      FakeTtsProvider().register();
      c.outDir = dir.path;
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.completedAudioPath, isNotNull);

      // A second run resets the path while it generates, then restores it on
      // completion.
      c.setText(
        'A different single paragraph long enough to stand alone too. It '
        'easily crosses the minimum word count and becomes its own segment, '
        'just like the first one did before it.',
      );
      c.startRun();
      expect(c.completedAudioPath, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.completedAudioPath, isNotNull);
    });

    test('canCleanupSegments enables and cleanupSegments removes per-segment '
        'files while keeping the combined track', () async {
      final c = makeController();
      c.setText(
        'A single paragraph long enough that it does not need any other '
        'company. It crosses the minimum word count comfortably and becomes '
        'one segment all on its own, plain and simple.',
      );
      final fake = FakeTtsProvider()..register();
      c.outDir = dir.path;
      c.startRun();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.runFinished, isTrue);
      expect(c.narrating, isFalse);

      expect(c.canCleanupSegments, isTrue);

      final outDir = Directory('${dir.path}/untitled');
      expect(File('${outDir.path}/untitled_full.mp3').existsSync(), isTrue);
      final manifestPath = '${outDir.path}/manifest.json';
      expect(File(manifestPath).existsSync(), isTrue);

      final removed = await c.cleanupSegments();

      expect(removed, 1); // one paragraph -> one segment file.
      expect(outDir.listSync().whereType<File>().length, 2); // combined + manifest
      expect(c.canCleanupSegments, isFalse);
      // Tiles no longer point at deleted files.
      expect(c.runSegments.single.filePath, isNull);
      final manifest = jsonDecode(
        File(manifestPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['segments_deleted'], isTrue);
      expect(fake.callCount, 1);
    });

    test('cleanupSegments before any run is a harmless no-op', () async {
      final c = makeController();
      expect(c.canCleanupSegments, isFalse);
      expect(await c.cleanupSegments(), 0);
    });

    test('cleanupSegments is a no-op while a run is in flight', () async {
      final c = makeController()..setText('Hello world. Enough words.');
      FakeTtsProvider().register();
      c.sampleLen = 1;
      c.outDir = dir.path;
      c.startRun();
      expect(c.narrating, isTrue);
      expect(await c.cleanupSegments(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('modelUiSpec', () {
    test('empty when no provider registers a spec for the model', () {
      final c = makeController();
      expect(c.modelUiSpec.isEmpty, isTrue);
    });

    test('resolves the active model spec from the registered provider', () {
      final fake = FakeTtsProvider()
        ..specsByAlias['fish'] = const ModelUiSpec([
          ModelUiOption(key: 'accent', label: 'Accent'),
          ModelUiOption(key: 'useCalmTag', label: '[calm]', type: ModelUiOptionType.bool),
        ]);
      fake.register();
      final c = makeController();
      expect(c.modelUiSpec.isEmpty, isFalse);
      final keys = c.modelUiSpec.options.map((o) => o.key).toList();
      expect(keys, ['accent', 'useCalmTag']);
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
      final segments = c.plannedSegments;
      expect(segments, isNotEmpty);
      expect(c.estimatedMinutes, greaterThan(0));
      expect(c.estimatedCostUsd, 0); // fish is free.
    });
  });

  group('appearance', () {
    test('defaults to following the system appearance', () {
      final c = makeController();
      expect(c.themeMode, AppThemeMode.system);
    });

    test('themeMode write updates the value and notifies listeners', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.themeMode = AppThemeMode.dark;
      expect(c.themeMode, AppThemeMode.dark);
      expect(notifications, 1);

      c.themeMode = AppThemeMode.light;
      expect(c.themeMode, AppThemeMode.light);
      expect(notifications, 2);
    });

    test('identical themeMode write is ignored', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.themeMode = AppThemeMode.system;
      expect(notifications, 0);
    });
  });

  group('settings setters', () {
    test('every setting write notifies listeners once', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.accent = 'x';
      c.style = 'y';
      c.passagePrefix = 'z';
      c.useCalmTag = true;
      c.minWords = 10;
      c.sampleLen = 2;
      c.outDir = 'out';
      c.resume = true;

      expect(c.accent, 'x');
      expect(c.style, 'y');
      expect(c.passagePrefix, 'z');
      expect(c.useCalmTag, isTrue);
      expect(c.minWords, 10);
      expect(c.sampleLen, 2);
      expect(c.outDir, 'out');
      expect(c.resume, isTrue);
      expect(notifications, 8);
    });

    test('identical setting writes are ignored', () {
      final c = makeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.resume = false; // already the default
      c.accent = c.accent; // already set

      expect(notifications, 0);
    });

    test('min words clamps to the settings slider range (10-100)', () {
      final c = makeController();
      c.minWords = 0;
      expect(c.minWords, 10);
      c.minWords = -5;
      expect(c.minWords, 10);
      c.minWords = 1000;
      expect(c.minWords, 100);
    });

    test('sample length can be cleared back to null', () {
      final c = makeController();
      c.sampleLen = 4;
      expect(c.sampleLen, 4);
      c.sampleLen = null;
      expect(c.sampleLen, isNull);
    });
  });

  group('output folder persistence', () {
    test('loads a previously saved output folder on construction', () async {
      SharedPreferences.setMockInitialValues({'outDir': '/tmp/saved'});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: VoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      expect(c.outDir, '/tmp/saved');
    });

    test('persists an output folder change to the preference store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: VoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      c.outDir = '/tmp/picked';
      expect(prefs.getString('outDir'), '/tmp/picked');
    });

    test('falls back to the default when no folder is saved', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: VoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      expect(c.outDir, 'output');
    });

    test('falls back to the default when the saved value is empty', () async {
      SharedPreferences.setMockInitialValues({'outDir': ''});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(
        loader: VoiceConfigLoader(configDir: configDir),
        prefs: prefs,
      );
      expect(c.outDir, 'output');
    });
  });
}