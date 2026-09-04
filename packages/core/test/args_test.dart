import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_narrator_core/src/cli/args.dart';
import 'package:tts_narrator_core/src/cli/voice_config.dart';
import 'package:tts_narrator_core/src/narration/config.dart';
import 'package:tts_narrator_core/src/narration/cost.dart';
import 'package:tts_narrator_core/src/narration/model_profiles.dart';
import 'package:tts_narrator_core/src/narration/tts_provider.dart';

import 'support/fake_provider.dart';

void main() {
  late Directory dir;
  late String cfgPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tts_args_test_');
    cfgPath = '${dir.path}/cfg';
    Directory(cfgPath).createSync(recursive: true);
    ttsProviderRegistry.register('openrouter', () => FakeTtsProvider());
    File('$cfgPath/config.json').writeAsStringSync('''{
  "default_model": "fish",
  "providers": {
    "openrouter": { "api_key": "sk-cfg" }
  }
}''');
    File('$cfgPath/gemini.json').writeAsStringSync('''{
  "id": "google/gemini-3.1-flash-tts-preview",
  "provider": "openrouter",
  "format": "pcm",
  "sample_rate": 24000,
  "prompt_style": true,
  "default_voice": "Charon",
  "voices": {"Charon": "Charon"}
}''');
    File('$cfgPath/kokoro.json').writeAsStringSync('''{
  "id": "hexgrad/kokoro-82m",
  "provider": "openrouter",
  "format": "mp3",
  "default_voice": "Emma",
  "pricing": {"usd_per_m_chars": 0.62},
  "voices": {"Emma": "bf_emma"}
}''');
    File('$cfgPath/fish.json').writeAsStringSync('''{
  "id": "fish-audio/s2.1-pro-free",
  "provider": "openrouter",
  "format": "mp3",
  "voices": {"British Female Narrator (good)": "89f41ea"}
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

  test('defaults: fish profile (free), compiled free default, no resumption', () {
    final cfg = parse(['--input', 's']);
    expect(cfg.profile.alias, 'fish');
    expect(cfg.voice, '89f41ea230034706881f85a8227d6ab9');
    expect(cfg.voiceLabel, 'British Female Narrator');
    expect(cfg.pricing.isFree, isTrue);
    expect(cfg.resume, isFalse);
    expect(cfg.dryRun, isFalse);
  });

  test('providers.<id>.api_key is the effective setting when no --api-key given',
      () {
    expect(parse(['--input', 's']).providerSettings['api_key'], 'sk-cfg');
  });

  test('--api-key overrides the config provider api_key', () {
    expect(
      parse(['--input', 's', '--api-key', 'sk-flag']).providerSettings['api_key'],
      'sk-flag',
    );
  });

  test('the model file provider is used to pick settings', () {
    expect(parse(['--input', 's']).profile.provider, 'openrouter');
  });

  test('--provider overrides the model provider', () {
    final cfg = parse(['--input', 's', '--provider', 'openrouter']);
    expect(cfg.profile.provider, 'openrouter');
  });

  test('an unresolvable env ref is a CliUsageError, not a StateError', () {
    const varName = 'TTN_UNSET_SECRET_4F7B';
    if (Platform.environment.containsKey(varName)) {
      return; // Only deterministic when the ref is genuinely unset.
    }
    final cfg = '${dir.path}/env_ref';
    Directory(cfg).createSync(recursive: true);
    File('$cfg/config.json').writeAsStringSync('''{
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "\${$varName}" }
  }
}''');
    File('$cfg/fish.json').writeAsStringSync(
        '{"id": "fish-audio/s2.1-pro-free", "provider": "openrouter", "format": "mp3"}');
    expect(
      () => parseArgs(['--input', 's', '--config', cfg]),
      throwsA(
        isA<CliUsageError>().having(
          (e) => e.message,
          'message',
          contains(varName),
        ),
      ),
    );
  });

  test('a dry run skips settings resolution entirely', () {
    const varName = 'TTN_UNSET_SECRET_9C21';
    if (Platform.environment.containsKey(varName)) {
      return; // Only deterministic when the ref is genuinely unset.
    }
    final cfg = '${dir.path}/dryrun_env_ref';
    Directory(cfg).createSync(recursive: true);
    File('$cfg/config.json').writeAsStringSync('''{
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "\${$varName}" }
  }
}''');
    File('$cfg/fish.json').writeAsStringSync(
        '{"id": "fish-audio/s2.1-pro-free", "provider": "openrouter", "format": "mp3"}');
    // Dry run parses fine with empty provider settings — no key needed.
    final parsed = parseArgs(['--input', 's', '--dry-run', '--config', cfg]);
    expect(parsed.dryRun, isTrue);
    expect(parsed.providerSettings, isEmpty);
  });

  test('an unknown --provider errors listing registered ids', () {
    expect(
      () => parse(['--input', 's', '--provider', 'bogus']),
      throwsA(
        isA<CliUsageError>().having(
          (e) => e.message,
          'message',
          contains('openrouter'),
        ),
      ),
    );
  });

  test('resolves a friendly fish voice via config and records the label', () {
    final cfg = parse(['--input', 's', '--model', 'fish', '--voice', 'British Female Narrator (good)']);
    expect(cfg.voice, '89f41ea');
    expect(cfg.voiceLabel, 'British Female Narrator (good)');
  });

  test('passes through unknown kokoro voice id freely', () {
    final cfg = parse(['--input', 's', '--model', 'kokoro', '--voice', 'bm_lewis']);
    expect(cfg.voice, 'bm_lewis');
    // Raw id equals its label, so no friendly label is recorded.
    expect(cfg.voiceLabel, isNull);
  });

  test('explicit voice is never validated (testing arbitrary ids)', () {
    final cfg = parse(['--input', 's', '--model', 'gemini', '--voice', 'NotAVoice']);
    expect(cfg.voice, 'NotAVoice');
    expect(cfg.voiceLabel, isNull);
  });

  test('--model kokoro without --voice adopts the configured default', () {
    final cfg = parse(['--input', 's', '--model', 'kokoro']);
    expect(cfg.voice, 'bf_emma');
    expect(cfg.voiceLabel, 'Emma');
  });

  test('--model gemini without --voice adopts the configured default', () {
    final cfg = parse(['--input', 's', '--model', 'gemini']);
    expect(cfg.voice, 'Charon');
  });

  test('--model fish without --voice adopts the compiled free default', () {
    final cfg = parse(['--input', 's', '--model', 'fish']);
    expect(cfg.voice, '89f41ea230034706881f85a8227d6ab9');
    expect(cfg.voiceLabel, 'British Female Narrator');
  });

  test('a model with no configured default requires --voice', () {
    final noDefaults = '${dir.path}/nodefaults';
    Directory(noDefaults).createSync(recursive: true);
    File('$noDefaults/kokoro.json').writeAsStringSync('''{
  "id": "hexgrad/kokoro-82m",
  "provider": "openrouter",
  "format": "mp3",
  "voices": {"Emma": "bf_emma"}
}''');
    expect(
      () => parseArgs(['--input', 's', '--model', 'kokoro', '--config', noDefaults]),
      throwsA(isA<CliUsageError>()),
    );
    final explicit = parseArgs([
      '--input', 's', '--model', 'kokoro', '--voice', 'bf_emma',
      '--config', noDefaults,
    ]);
    expect(explicit.voice, 'bf_emma');
  });

  test('pricing comes from the config, free when unconfigured', () {
    final kokoro = parse(['--input', 's', '--model', 'kokoro', '--voice', 'Emma']);
    expect(kokoro.pricing, const AudioPricing(usdPerMChars: 0.62));
    final fish = parse(['--input', 's']);
    expect(fish.pricing, freePricing);
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

  test('explicit --config pointing at a missing directory errors loudly', () {
    expect(
      () => parseArgs(['--input', 's', '--config', '${dir.path}/missing']),
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
    test('lists all models, but only those configured, when no model is given', () {
      final out = renderVoiceListing(config: const VoiceConfig());
      // Only fish bootstraps when nothing is configured.
      expect(out, contains('fish —'));
      expect(out, isNot(contains('gemini —')));
      expect(out, isNot(contains('kokoro —')));
    });

    test('lists a single model with its configured default', () {
      final cfg = VoiceConfig(
        models: const {
          'gemini': TtsModelProfile(
            alias: 'gemini',
            id: 'google/gemini-3.1-flash-tts-preview',
            format: 'pcm',
          ),
        },
        defaults: const {'gemini': 'Charon'},
        voices: const {'gemini': {'Charon': Voice(id: 'Charon')}},
      );
      final out = renderVoiceListing(
        model: cfg.models['gemini'],
        config: cfg,
      );
      expect(out, contains('google/gemini-3.1-flash-tts-preview'));
      expect(out, contains('default voice:  Charon'));
      expect(out, contains('Charon → Charon'));
      expect(out, isNot(contains('kokoro —')));
    });

    test('shows friendly aliases and notes when nothing is configured', () {
      final out = renderVoiceListing(
        model: kDefaultProfile.profile,
        config: const VoiceConfig(),
      );
      expect(out, contains('default voice:  British Female Narrator '
          '(89f41ea230034706881f85a8227d6ab9)'));
      expect(out, contains('none configured — add "fish" aliases in the voice config'));
    });

    test('shows a default voice when the config has none', () {
      final out = renderVoiceListing(
        model: const TtsModelProfile(
          alias: 'kokoro',
          id: 'hexgrad/kokoro-82m',
          format: 'mp3',
        ),
        config: const VoiceConfig(),
      );
      expect(out, contains('default voice:  none configured'));
    });

    test('tags aliases with their configured gender', () {
      final cfg = VoiceConfig(
        voices: const {
          'kokoro': {
            'Emma': Voice(id: 'bf_emma', gender: VoiceGender.female),
            'Daniel': Voice(id: 'bm_daniel', gender: VoiceGender.male),
          },
        },
      );
      final out = renderVoiceListing(
        model: const TtsModelProfile(
          alias: 'kokoro',
          id: 'hexgrad/kokoro-82m',
          format: 'mp3',
        ),
        config: cfg,
      );
      expect(out, contains('Emma → bf_emma [f]'));
      expect(out, contains('Daniel → bm_daniel [m]'));
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
      expect(copy.providerSettings, base.providerSettings);
      expect(copy.pricing, base.pricing);
    });
  });
}