import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/args.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';

void main() {
  late Directory dir;
  late String cfgPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_args_test_');
    cfgPath = '${dir.path}/voice_config.json';
    File(cfgPath).writeAsStringSync('''{
  "api_key": "sk-cfg",
  "voices": {
    "fish": {"British Female Narrator (good)": "89f41ea"},
    "kokoro": {"Emma": "bf_emma"}
  }
}''');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  NarrationConfig parse(List<String> args) => parseArgs([...args, '--config', cfgPath]);

  test('requires --input', () {
    expect(() => parse(['--model', 'fish']), throwsA(isA<CliUsageError>()));
    expect(() => parse(['--input', '']), throwsA(isA<CliUsageError>()));
  });

  test('rejects unknown flags and unknown models', () {
    expect(() => parse(['--input', 's', '--nope']), throwsA(isA<CliUsageError>()));
    expect(() => parse(['--input', 's', '--model', 'bogus']), throwsA(isA<CliUsageError>()));
  });

  test('invalid --tags value errors', () {
    expect(() => parse(['--input', 's', '--tags', 'maybe']), throwsA(isA<CliUsageError>()));
  });

  test('defaults: gemini profile, Charon code default, env key fallback', () {
    final cfg = parse(['--input', 's']);
    expect(cfg.profile.alias, 'gemini');
    expect(cfg.voice, 'Charon');
    expect(cfg.resume, isFalse);
    expect(cfg.dryRun, isFalse);
  });

  test('config api_key is used when no --api-key given', () {
    expect(parse(['--input', 's']).apiKey, 'sk-cfg');
  });

  test('--api-key overrides the config key', () {
    expect(parse(['--input', 's', '--api-key', 'sk-flag']).apiKey, 'sk-flag');
  });

  test('resolves a friendly fish voice via config and records the label', () {
    final cfg = parse(['--input', 's', '--model', 'fish', '--voice', 'British Female Narrator (good)']);
    expect(cfg.voice, '89f41ea');
    expect(cfg.voiceLabel, 'British Female Narrator (good)');
  });

  test('passes through unknown kokoro voice id freely', () {
    final cfg = parse(['--input', 's', '--model', 'kokoro', '--voice', 'bf_emma']);
    expect(cfg.voice, 'bf_emma');
    expect(cfg.voiceLabel, 'bf_emma');
  });

  test('gemini validates known voices and rejects unknown ones', () {
    expect(() => parse(['--input', 's', '--voice', 'NotAVoice']), throwsA(isA<CliUsageError>()));
    final ok = parse(['--input', 's', '--voice', 'Callirrhoe']);
    expect(ok.voice, 'Callirrhoe');
  });

  test('--model kokoro without --voice adopts kokoro default', () {
    final cfg = parse(['--input', 's', '--model', 'kokoro']);
    expect(cfg.voice, 'bf_emma');
  });

  test('--model fish without --voice adopts the fish hex default', () {
    final cfg = parse(['--input', 's', '--model', 'fish']);
    expect(cfg.voice, '89f41ea230034706881f85a8227d6ab9');
  });

  test('--sample-len and --min-words parse numerically and reject junk', () {
    final cfg = parse(['--input', 's', '--sample-len', '3', '--min-words', '10']);
    expect(cfg.sampleLen, 3);
    expect(cfg.minWords, 10);
    expect(() => parse(['--input', 's', '--sample-len', 'x']), throwsA(isA<CliUsageError>()));
    expect(() => parse(['--input', 's', '--min-words', '0']), throwsA(isA<CliUsageError>()));
  });

  test('--dry-run and --resume flags set', () {
    final cfg = parse(['--input', 's', '--dry-run', '--resume']);
    expect(cfg.dryRun, isTrue);
    expect(cfg.resume, isTrue);
  });

  test('--out override is passed through', () {
    expect(parse(['--input', 's', '--out', '/tmp/x']).outDir, '/tmp/x');
  });

  test('explicit --config pointing at a missing file errors loudly', () {
    expect(
      () => parseArgs(['--input', 's', '--config', '${dir.path}/missing.json']),
      throwsA(isA<CliUsageError>()),
    );
  });

  group('expandInputFiles', () {
    test('a plain file yields itself', () {
      final f = File('${dir.path}/a.txt')..writeAsStringSync('x');
      expect(expandInputFiles(f.path), [f.path]);
    });

    test('a directory yields sorted top-level .txt files, hiding dots', () {
      File('${dir.path}/b.txt').writeAsStringSync('x');
      File('${dir.path}/a.txt').writeAsStringSync('x');
      File('${dir.path}/.hidden.txt').writeAsStringSync('x');
      File('${dir.path}/notes.txt~').writeAsStringSync('x');
      File('${dir.path}/readme.md').writeAsStringSync('x');
      final files = expandInputFiles(dir.path);
      expect(files, hasLength(2));
      expect(files[0].split(Platform.pathSeparator).last, 'a.txt');
      expect(files[1].split(Platform.pathSeparator).last, 'b.txt');
    });

    test('a directory with no .txt files errors', () {
      File('${dir.path}/only.md').writeAsStringSync('x');
      expect(() => expandInputFiles(dir.path), throwsA(isA<CliUsageError>()));
    });

    test('a missing path errors', () {
      expect(
        () => expandInputFiles('${dir.path}/does-not-exist.txt'),
        throwsA(isA<CliUsageError>()),
      );
    });
  });

  group('renderVoiceListing', () {
    test('lists all models when no model is given', () {
      final out = renderVoiceListing(config: const VoiceConfig());
      expect(out, contains('gemini —'));
      expect(out, contains('kokoro —'));
      expect(out, contains('fish —'));
    });

    test('lists a single model containing its known voices', () {
      final out = renderVoiceListing(
        model: kGeminiProfile,
        config: const VoiceConfig(),
      );
      expect(out, contains('google/gemini-3.1-flash-tts-preview'));
      expect(out.toLowerCase(), contains('callirrhoe'));
      expect(out, isNot(contains('kokoro —')));
    });

    test('annotates free-form models and shows friendly aliases', () {
      final cfg = VoiceConfig(aliases: {
        'fish': {'British Female Narrator': '89f41ea'},
      });
      final out = renderVoiceListing(model: kFishProfile, config: cfg);
      expect(out, contains('free-form'));
      expect(out, contains('British Female Narrator → 89f41ea'));
    });
  });

  group('NarrationConfig.copyWith', () {
    test('replaces inputPath and keeps everything else', () {
      final base = parse(['--input', 's', '--model', 'fish', '--out', '/tmp/x']);
      final copy = base.copyWith(inputPath: '/other.txt');
      expect(copy.inputPath, '/other.txt');
      expect(copy.profile, base.profile);
      expect(copy.voice, base.voice);
      expect(copy.outDir, base.outDir);
      expect(copy.resume, base.resume);
      expect(copy.apiKey, base.apiKey);
    });
  });
}