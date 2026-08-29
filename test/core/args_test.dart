import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator/src/cli/args.dart';
import 'package:tts_narrator/src/narration/config.dart';

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
}