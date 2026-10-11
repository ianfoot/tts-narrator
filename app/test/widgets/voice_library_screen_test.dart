import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_narrator/src/gui/controller/app_controller.dart';
import 'package:tts_narrator/src/gui/voices/voice_library_screen.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../support/fake_audio_platform.dart';
import '../support/fake_tts_provider.dart';
import '../support/l10n_test_support.dart';
import '../support/run_setup_fixtures.dart';

/// The voice library is the only place where audio is generated before a run, so
/// these tests are mostly about what reaches the disk and when. Everything is
/// driven through a real config directory for the same reason the settings
/// tests are: the store's whole job is the layout it writes.
class _Fixture {
  late final Directory dir;
  late final FakeTtsProvider provider;
  late final AppController controller;

  /// The installed audio platform, so a test can see what the player was
  /// actually asked to load.
  late final FakeAudioPlatform audio;

  _Fixture({bool withConsumer = false}) {
    audio = installFakeAudioPlatform();
    dir = Directory.systemTemp.createTempSync('tts_voice_library_test_');
    // One writeConfig call, never two: it rewrites `models/` wholesale, so a
    // second call would silently drop the model the first one declared.
    writeConfig(dir.path, {
      'models': {
        'qwen': {
          'id': 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16',
          'formats': ['wav'],
          'sends_voice': false,
          'sends_instruct': true,
          'sends_language': true,
          'default_instruct': 'A calm male narrator with a low, steady voice.',
          'languages': {'English': 'English'},
          'default_language': 'English',
        },
        if (withConsumer)
          'fish': {
            'id': 'mlx-community/fish-audio-s2-pro-8bit',
            'formats': ['wav'],
            'sends_reference_audio': true,
            'default_voice': 'Anne',
            'voices': {'Anne': '7da08ad79a8a4492b2c6b54091499922'},
          },
      },
      'defaults': {'fish': 'Anne'},
      'voices': {'fish': {'Anne': '7da08ad79a8a4492b2c6b54091499922'}},
    });
    provider = FakeTtsProvider();
    controller = makeController(dir.path, client: provider.client);
    if (withConsumer) controller.changeModel('fish');
  }

  CustomVoiceStore get store => CustomVoiceStore(dir.path);

  /// The temporary file the screen writes so a draft can be played.
  File get previewFile => File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'tts-narrator-voice-draft.wav',
  );

  /// Whether anything at all has been written under the voice directory.
  bool get anythingPersisted {
    final voices = store.voicesDir;
    if (!Directory(voices).existsSync()) return false;
    return Directory(voices).listSync().isNotEmpty;
  }

  /// Clears the preview the screen leaves behind, so one test cannot pass on
  /// the file another wrote.
  void clearPreview() {
    final file = previewFile;
    if (file.existsSync()) file.deleteSync();
  }

  void dispose() {
    dir.deleteSync(recursive: true);
    // The preview lives outside the fixture's directory, so nothing else would
    // remove it.
    clearPreview();
  }
}

Future<void> _pumpLibrary(WidgetTester tester, _Fixture fixture) async {
  // Set through `tester.view` rather than the legacy `setSurfaceSize`, which in
  // this Flutter version lays the tree out at the requested size while
  // `tester.view` keeps reporting the default. The two then disagree about
  // where a coordinate is, and `tester.tap` silently fires at the wrong place.
  //
  // The height is generous on purpose: this screen is one long scroll, and a
  // control below the fold is not merely un-tappable, it taps whatever is
  // really there instead of complaining.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      home: VoiceLibraryScreen(controller: fixture.controller),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps [key] after scrolling it into view.
///
/// The screen is one long scroll: panel, then the draft card, then the saved
/// voices. Only the panel fits the window, so anything below it needs scrolling
/// first. Scrolling rather than enlarging the window because the spec surface
/// here stays at the app's default 800x600 no matter what is asked for, and
/// `ensureVisible` is not a substitute -- it looks for a `ScrollPosition` below
/// the target, while the `ListView` holding these controls is above it.
///
/// A tap on a control that is off-screen does not fail loudly. It fires at
/// coordinates that land on whatever is really there, which reads downstream as
/// a missing effect rather than a missing widget.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) => _tap(tester, 'designVoiceGenerateButton');

void main() {
  late _Fixture fixture;

  setUp(() {
    // Not optional. The screen auto-plays each generated draft, which builds a
    // real `AudioPlayer`; without a platform behind it every later `await
    // player.stop()` never completes, and since cancel, re-roll and save all
    // stop playback first they would silently do nothing.
    //
    // The fixture installs its own and keeps the handle: a test needs to see what
    // the player was actually asked to load, not merely that it stopped
    // complaining.
    fixture = _Fixture();
  });
  tearDown(() => fixture.dispose());

  group('the design panel', () {
    testWidgets('offers the design models and prefills the prose', (tester) async {
      await _pumpLibrary(tester, fixture);

      expect(find.byKey(const Key('designVoiceGenerateButton')), findsOneWidget);
      expect(find.textContaining('calm male narrator'), findsWidgets);
    });

    // The passage is fixed, so the words are on screen to be read rather than
    // edited: comparing two designs means something only if they differ by
    // voice and not by text.
    testWidgets('shows the standard passage as read-only text', (tester) async {
      await _pumpLibrary(tester, fixture);

      // Against the constant rather than a word from it: swapping the passage
      // is a routine editorial choice, and pinning a fragment here would break
      // the test each time the words change.
      final preview = tester.widget<Text>(
        find.byKey(const Key('voiceDesignPassagePreview')),
      );
      expect(preview.data, kVoiceDesignPassage.trim());
    });

    // The whole screen used to stretch to the window, which left each control a
    // wide bar with its label marooned in the middle. Capping the column is what
    // keeps a label and the control it labels visibly a pair.
    testWidgets('caps the content column instead of stretching to the window',
        (tester) async {
      await _pumpLibrary(tester, fixture);

      final width = tester.getSize(
        find.byKey(const Key('designVoiceInstructField')),
      ).width;
      expect(width, lessThanOrEqualTo(720));
      // And centred, not left-flush against a 1200px window.
      expect(width, lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio));
    });

    // The dropdown label centred inside a full-width button read as body text
    // with a chevron beside it rather than as a control. Asserting the widget's
    // alignment rather than the pixels, because a rendered-coordinate check
    // would pass just as happily if the button had merely shrunk.
    testWidgets('left-aligns the dropdown labels', (tester) async {
      await _pumpLibrary(tester, fixture);

      final button = tester.widget<CupertinoButton>(
        find.descendant(
          of: find.byKey(const Key('designVoiceModelDropdown')),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(button.alignment, Alignment.centerLeft);
    });
  });

  group('generating and judging a draft', () {
    // The whole point of a draft: most generations get thrown away, so nothing
    // may reach the disk until the user says so.
    testWidgets('generating writes nothing to disk', (tester) async {
      await _pumpLibrary(tester, fixture);

      await _generate(tester);

      expect(fixture.provider.callCount, 1);
      final call = fixture.provider.calls.single;
      expect(call.input, kVoiceDesignPassage);
      expect(call.instruct, contains('calm male narrator'));
      expect(call.voice, isNull);
      expect(fixture.anythingPersisted, isFalse);
      expect(
        fixture.controller.customVoices.draft,
        isNotNull,
        reason: 'the clip is held in memory until it is saved',
      );
    });

    // The panel above stays editable while a draft is on screen, so without the
    // caption "generate again" looks like it re-rolls the clip being judged.
    testWidgets('shows the prose the draft was generated from', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);

      expect(
        find.byKey(const Key('voiceDraftInstructCaption')),
        findsOneWidget,
      );
    });

    testWidgets('a second generation rolls the same prose again', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);
      expect(fixture.controller.customVoices.draft!.attempts, 1);

      await _tap(tester, 'designVoiceGenerateButton');
      await tester.pumpAndSettle();

      expect(fixture.provider.callCount, 2);
      expect(fixture.controller.customVoices.draft!.attempts, 2);
      expect(fixture.anythingPersisted, isFalse);
    });

    testWidgets('cancelling the draft discards it without writing anything', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);

      await _tap(tester, 'voiceDraftCancelButton');
      await tester.pumpAndSettle();

      expect(fixture.controller.customVoices.draft, isNull);
      expect(find.byKey(const Key('voiceDraftSaveButton')), findsNothing);
      expect(fixture.anythingPersisted, isFalse);
    });

    // The preview file is a workaround for playback, not a save. It has to be
    // named like audio or the platform cannot decode it, and it has to stay out
    // of the library or "nothing is written until you press Save" stops meaning
    // anything the user can rely on.
    testWidgets('writes the preview to a wav outside the voice library', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);

      final preview = fixture.previewFile;
      expect(preview.existsSync(), isTrue);
      expect(preview.uri.pathSegments.last, endsWith('.wav'));
      expect(preview.parent.path, Directory.systemTemp.path);
      expect(fixture.anythingPersisted, isFalse);
    });

    // Generating must be silent. The clip is written so that pressing Play has
    // something to hand the platform, but sound that starts on its own
    // interrupts whatever the user was doing, and they did not ask for it.
    testWidgets('generating on its own plays nothing', (tester) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);

      expect(fixture.controller.customVoices.draft, isNotNull);
      expect(fixture.audio.requestedUrls, isEmpty);
      expect(fixture.audio.byteSourceCount, 0);
    });

    // The bug this pins down is specific: passing the clip as bytes reads like
    // an in-memory play, but audioplayers writes those bytes to a temp file
    // named by a content hash with no extension, which the platform then
    // cannot decode. Nothing throws; the button just does nothing. Asserting
    // the request the platform actually receives is the only way to see it.
    testWidgets('hands the player a decodable file rather than raw bytes', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);
      await _tap(tester, 'voiceDraftPlayButton');

      expect(fixture.audio.byteSourceCount, 0);
      expect(fixture.audio.requestedUrls, isNotEmpty);
      final requested = fixture.audio.requestedUrls.last;
      expect(requested.url, endsWith('.wav'));
      expect(requested.mimeType, 'audio/wav');
    });
  });

  group('saving a draft', () {
    testWidgets('asks for a name, then writes the clip and a registry row', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);

      await _tap(tester, 'voiceDraftSaveButton');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saveVoiceNameField')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('saveVoiceNameField')),
        'Gravelly',
      );
      await tester.tap(find.byKey(const Key('saveVoiceDialogSaveButton')));
      await tester.pumpAndSettle();

      final library = fixture.store.read();
      expect(library.voices, hasLength(1));
      expect(library.voices.single.name.value, 'Gravelly');
      final id = library.voices.single.id.value;
      expect(fixture.store.wavFile(id).existsSync(), isTrue);
      expect(fixture.controller.customVoices.draft, isNull);
      expect(find.byKey(Key('voiceUse_$id')), findsOneWidget);
    });

    // A second variation of the same design must not overwrite the first: the
    // user kept the first on purpose.
    testWidgets('saving the same name twice keeps both clips', (tester) async {
      await _pumpLibrary(tester, fixture);

      for (final attempt in [1, 2]) {
        await _generate(tester);
        await _tap(tester, 'voiceDraftSaveButton');
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('saveVoiceNameField')),
          'Gravelly',
        );
        await tester.tap(find.byKey(const Key('saveVoiceDialogSaveButton')));
        await tester.pumpAndSettle();
        expect(fixture.store.read().voices, hasLength(attempt));
      }
    });
  });

  group('a saved voice', () {
    Future<void> saveOne(WidgetTester tester, String name) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);
      await _tap(tester, 'voiceDraftSaveButton');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('saveVoiceNameField')), name);
      await tester.tap(find.byKey(const Key('saveVoiceDialogSaveButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('renames without moving the clip', (tester) async {
      await saveOne(tester, 'Gravelly');
      final id = fixture.store.read().voices.single.id.value;

      await _tap(tester, 'voiceRename_$id');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('renameVoiceNameField')),
        'Raspy',
      );
      await tester.tap(find.byKey(const Key('renameVoiceDialogSaveButton')));
      await tester.pumpAndSettle();

      final voice = fixture.store.read().byId(id)!;
      expect(voice.name.value, 'Raspy');
      expect(fixture.store.wavFile(id).existsSync(), isTrue);
    });

    testWidgets('deletes the clip as well as the row, once confirmed', (
      tester,
    ) async {
      await saveOne(tester, 'Gravelly');
      final id = fixture.store.read().voices.single.id.value;

      await _tap(tester, 'voiceDelete_$id');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteVoiceCancelButton')));
      await tester.pumpAndSettle();
      expect(fixture.store.read().voices, hasLength(1));

      await _tap(tester, 'voiceDelete_$id');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteVoiceConfirmButton')));
      await tester.pumpAndSettle();

      expect(fixture.store.read().isEmpty, isTrue);
      expect(fixture.store.wavFile(id).existsSync(), isFalse);
    });

    // A new variation is a new draft. The kept clip has to survive the
    // temptation to improve on it.
    testWidgets('new variation seeds the panel and saves nothing', (
      tester,
    ) async {
      await saveOne(tester, 'Gravelly');
      final id = fixture.store.read().voices.single.id.value;
      final clipPath = fixture.store.wavFile(id).path;

      await _tap(tester, 'voiceVariation_$id');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voiceDraftSaveButton')), findsNothing);
      expect(fixture.controller.customVoices.draft, isNull);
      expect(fixture.store.wavFile(id).path, clipPath);
      expect(fixture.store.read().voices, hasLength(1));
    });
  });

  group('adopting a voice into a run', () {
    testWidgets('a design-only model cannot adopt one, and says so', (
      tester,
    ) async {
      await _pumpLibrary(tester, fixture);
      await _generate(tester);
      await _tap(tester, 'voiceDraftSaveButton');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('saveVoiceNameField')),
        'Gravelly',
      );
      await tester.tap(find.byKey(const Key('saveVoiceDialogSaveButton')));
      await tester.pumpAndSettle();
      final id = fixture.store.read().voices.single.id.value;

      expect(
        fixture.controller.usesCustomVoices,
        isFalse,
        reason: 'qwen sends no reference audio',
      );
      // Disabled with the reason beside it, not hidden: a missing button would
      // read as an empty library rather than a fixable mismatch.
      expect(find.byKey(Key('voiceUse_$id')), findsOneWidget);
      expect(find.text('Use'), findsOneWidget);
    });

    testWidgets('a cloning model adopts the clip and its transcript', (
      tester,
    ) async {
      fixture.dispose();
      fixture = _Fixture(withConsumer: true);
      await _pumpLibrary(tester, fixture);
      await _generate(tester);
      await _tap(tester, 'voiceDraftSaveButton');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('saveVoiceNameField')),
        'Gravelly',
      );
      await tester.tap(find.byKey(const Key('saveVoiceDialogSaveButton')));
      await tester.pumpAndSettle();
      final voice = fixture.store.read().voices.single;

      expect(fixture.controller.usesCustomVoices, isTrue);
      await _tap(tester, 'voiceUse_${voice.id.value}');
      await tester.pumpAndSettle();

      expect(
        fixture.controller.referenceAudioPath,
        fixture.store.wavFile(voice.id.value).path,
      );
      expect(fixture.controller.referenceAudioText, kVoiceDesignPassage);
    });
  });
}