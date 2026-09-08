import 'dart:convert';
import 'dart:io';

import '../narration/cost.dart';
import '../narration/model_profiles.dart';

/// The narrator gender a configured voice is tagged with.
///
/// Tagging is purely optional, per-voice metadata carried inside each entry of
/// a model's `voices` block. Models expose different signals: kokoro's ids
/// encode it (`bf_*`/`bm_*`), curated lists like fish's encode it in the
/// friendly label, and gemini's named voices carry no gender signal at all (so
/// they stay untagged). [neutral] covers unisex or unspecified voices.
enum VoiceGender {
  male,
  female,
  neutral;

  /// The lowercase config spelling for this gender (`'male'`, `'female'`,
  /// `'neutral'`), used in `voices` blocks and CLI/UI labels.
  String get label => name;

  /// Single-letter shorthand for compact UI labels: `m`/`f`/`n`.
  String get shorthand => switch (this) {
    VoiceGender.male => 'm',
    VoiceGender.female => 'f',
    VoiceGender.neutral => 'n',
  };
}

/// Parses the config-string form to a [VoiceGender], or null for anything
/// unrecognized (mislabels are dropped by the loader, not a hard error).
VoiceGender? parseVoiceGender(String? value) {
  if (value == null) return null;
  return switch (value.trim().toLowerCase()) {
    'male' => VoiceGender.male,
    'female' => VoiceGender.female,
    'neutral' => VoiceGender.neutral,
    _ => null,
  };
}

/// One configured voice in a model's `voices` block: the provider voice id
/// sent in the request body, plus optional metadata (gender, and room for
/// more fields later) — one entry per voice, so a voice's fields live
/// together instead of being split across parallel blocks.
class Voice {
  const Voice({required this.id, this.gender});

  /// Provider voice id sent in the request body.
  final String id;

  /// Optional narrator gender tag; null when the voice is untagged.
  final VoiceGender? gender;
}

/// A single selectable voice for the GUI voice picker and CLI listing.
class VoiceOption {
  const VoiceOption({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
    this.gender,
  });

  /// Model alias this voice belongs to (e.g. `gemini`, `fish`).
  final String model;

  /// Provider voice id sent in the request body.
  final String id;

  /// Human-readable label: the friendly alias when [isAlias], else the raw id.
  final String label;

  /// Whether [label] is a friendly alias from the config (vs a raw id).
  final bool isAlias;

  /// Optional narrator gender tag; null when the voice is untagged.
  final VoiceGender? gender;
}

/// Voice data, model wiring, default model, and per-provider settings,
/// loaded from a config *directory*.
///
/// Layout:
///   config.json              global data — `default_model` + `providers`
///   `<alias>.json`           per-model — id, format, sample_rate, prompt_style,
///                            sends_voice, provider, default_voice, pricing,
///                            voices (each entry: id + optional gender)
///
/// Splitting per-model into one file each keeps the user's voice library
/// modular: edit a single model without touching the others, drop in a new
/// model, or copy a curated voice pack between machines. Providers (secrets)
/// stay global so a key shared across models is written once.
///
/// Models, voices, and pricing live in the files rather than in code because
/// providers add/remove voices, prices drift, and model ids change (e.g. a
/// gemini preview id being replaced by a GA id) — all without a rebuild. The
/// directory is optional: when no default config exists and `--config` was not
/// given, an empty config is used and everything degrades gracefully — fish's
/// compiled bootstrap remains the default; other models require a model file;
/// models without pricing are treated as free.
class VoiceConfig {
  const VoiceConfig({
    this.defaultModel,
    this.providers = const {},
    this.models = const {},
    this.defaults = const {},
    this.pricing = const {},
    this.voices = const {},
  });

  /// Default model alias or id (`default_model`) the CLI and GUI preselect on
  /// cold start; null falls back to the compiled fish bootstrap.
  final String? defaultModel;

  /// Opaque per-provider settings (`providers.<id>` → string→string). Keys and
  /// values are never interpreted here — this is the raw block, round-tripped
  /// verbatim; `${ENV}` references are resolved at run-config build time via
  /// [resolveSettings], not at load/save time.
  final Map<String, Map<String, String>> providers;

  /// Per-model request wiring (model alias → profile), overriding or extending
  /// the compiled fish bootstrap.
  final Map<String, TtsModelProfile> models;

  /// Per-model default voice label (model alias → friendly name from [voices]).
  final Map<String, String> defaults;

  /// Per-model cost data (model alias → pricing), for dry-run estimates.
  final Map<String, AudioPricing> pricing;

  /// Voice library per model: friendly label → [Voice], keyed by model alias.
  /// A voice's id and optional metadata (gender, and room for more later) live
  /// together in one entry, so there is no parallel block to keep in sync.
  final Map<String, Map<String, Voice>> voices;

  bool get isEmpty =>
      defaultModel == null &&
      providers.isEmpty &&
      models.isEmpty &&
      defaults.isEmpty &&
      pricing.isEmpty &&
      voices.isEmpty;

  /// Pricing for [modelAlias], or [freePricing] when unconfigured.
  AudioPricing pricingFor(String modelAlias) =>
      pricing[modelAlias] ?? freePricing;

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  ///
  /// If [value] matches a friendly alias for the model, the mapped raw id is
  /// returned. Otherwise the value is returned unchanged (free-form ids and
  /// raw id passthrough keep working exactly as before).
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final modelVoices = voices[modelAlias];
    if (modelVoices != null) {
      final voice = modelVoices[value];
      if (voice != null) return (voice.id, value);
    }
    return (value, value);
  }

  /// The gender tag for [voiceLabel] under [modelAlias], or null when the
  /// voice (or the whole model) is untagged.
  VoiceGender? genderFor(String modelAlias, String voiceLabel) =>
      voices[modelAlias]?[voiceLabel]?.gender;
}

/// The effective set of models the app can narrate with: the compiled fish
/// bootstrap first, merged with (and overridden / extended by) the `models`
/// block in [config]. Config entries override the bootstrap when their alias
/// matches (e.g. `models.fish`) and add any other model (gemini, kokoro, a new
/// provider) afterwards.
List<TtsModelProfile> effectiveModels(VoiceConfig config) {
  final out = <TtsModelProfile>[];
  final bootstrap = kDefaultProfile.profile;
  final concrete = config.models;
  if (concrete.containsKey(bootstrap.alias)) {
    out.add(concrete[bootstrap.alias]!);
  } else {
    out.add(bootstrap);
  }
  for (final e in concrete.entries) {
    if (e.key == bootstrap.alias) continue;
    out.add(e.value);
  }
  return out;
}

/// Resolves a `--model` value (alias or full id) against the effective model
/// set for [config], or null if unknown.
TtsModelProfile? profileFor(String aliasOrId, VoiceConfig config) {
  for (final p in effectiveModels(config)) {
    if (p.alias == aliasOrId || p.id == aliasOrId) return p;
  }
  return null;
}

/// The model the CLI and GUI preselect on cold start.
///
/// Resolution order:
///   1. `default_model` in the config, resolved against the effective model set
///      (alias or full id);
///   2. else fish's compiled bootstrap ([kDefaultProfile]) — the app's
///      out-of-box, cost-free default.
///
/// An unresolvable `default_model` is handled (warned + fallback) by the
/// loader; this helper stays pure.
TtsModelProfile defaultModelFor(VoiceConfig config) {
  final dm = config.defaultModel;
  if (dm != null && dm.trim().isNotEmpty) {
    final resolved = profileFor(dm.trim(), config);
    if (resolved != null) return resolved;
  }
  return kDefaultProfile.profile;
}

/// Resolves a friendly alias (or the raw id) for [modelAlias] to a provider id,
/// returning null when [value] matches neither.
String? _resolveAlias(VoiceConfig config, String modelAlias, String value) {
  final modelVoices = config.voices[modelAlias];
  return modelVoices?[value]?.id ?? (value.isNotEmpty ? value : null);
}

/// The default voice (+ friendly label) for [model], used when `--voice` /
/// the GUI voice field is empty.
///
/// Resolution order:
///   1. `defaults` in the config: the named voice must resolve via the model's
///      aliases (or be a raw id);
///   2. fish's compiled bootstrap ([kDefaultProfile]) when no config default is
///      set — the app's out-of-box, cost-free fallback;
///   3. otherwise a [VoiceConfigurationError]: model needs a `--voice` or a config
///      default.
(String id, String label) defaultVoiceFor(
  TtsModelProfile model,
  VoiceConfig config,
) {
  final configured = config.defaults[model.alias];
  if (configured != null && configured.trim().isNotEmpty) {
    final id = _resolveAlias(config, model.alias, configured);
    if (id != null) return (id, configured);
    throw VoiceConfigurationError(
      'Default voice "$configured" for "${model.alias}" is not a configured '
      'voice or raw id.',
    );
  }
  if (model.alias == kDefaultProfile.profile.alias) {
    return (kDefaultProfile.voice, kDefaultProfile.voiceLabel);
  }
  throw VoiceConfigurationError(
    'No default voice configured for "${model.alias}". Set "defaults" in the '
    'voice config, or pass --voice / pick one in the app.',
  );
}

/// All selectable voices for [model] (or all models when null).
///
/// Voices come from the user's [config] aliases only — plus the model's
/// default voice so the picker always has a sensible preselection even before
/// the user adds aliases. Code ships no voice lists: providers add/remove
/// voices, so the config is the single source of truth.
List<VoiceOption> voiceEntries({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : effectiveModels(config);
  final entries = <VoiceOption>[];
  for (final p in profiles) {
    void add(String id, String label, bool isAlias) {
      if (entries.any((e) => e.model == p.alias && e.id == id)) return;
      entries.add(
        VoiceOption(
          model: p.alias,
          id: id,
          label: label,
          isAlias: isAlias,
          gender: config.genderFor(p.alias, label),
        ),
      );
    }

    for (final e
        in (config.voices[p.alias] ?? const <String, Voice>{}).entries) {
      add(e.value.id, e.key, true);
    }
    try {
      final (id, label) = defaultVoiceFor(p, config);
      add(id, label, false);
    } on VoiceConfigurationError {
      // No default for this model yet; skip (raw-id entry stays available).
    }
  }
  entries.sort((a, b) {
    final byModel = a.model.compareTo(b.model);
    if (byModel != 0) return byModel;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return entries;
}

/// Default config directory, shared by the CLI and GUI.
///
/// macOS/Linux: `~/.config/tts-narrator/`
/// Windows:     `%APPDATA%\tts-narrator\`
String defaultConfigDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return appData != null ? '$appData\\tts-narrator' : 'tts-narrator';
  }
  final home = Platform.environment['HOME'];
  return home != null ? '$home/.config/tts-narrator' : '.';
}

/// Loads a [VoiceConfig] from a config *directory* ([configDir]).
///
/// Reads `config.json` for the global `default_model` + `providers` block,
/// then one ``<alias>.json`` file per model directly in the directory. A
/// missing `config.json` yields empty global data; a directory with no model
/// files yields no configured models (fish still falls back to its compiled
/// bootstrap).
///
/// Error policy: a malformed or unreadable `config.json` is a hard
/// [VoiceConfigurationError] (the global file is small and should fail loudly). A
/// malformed *model* file — bad JSON, a missing/non-string `id`, a missing or
/// empty `provider`, or a wrong-typed field — is skipped with a warning so one
/// bad model never breaks the rest of the app. A `default_model` that names no
/// configured model also warns and falls back to the fish bootstrap.
///
/// Returns the loaded config plus human-readable [warnings] for skipped models.
(VoiceConfig, List<String>) loadVoiceConfig(String configDir) {
  final warnings = <String>[];
  final separator = Platform.pathSeparator;
  final global = File('$configDir${separator}config.json');
  final globalConfig = global.existsSync()
      ? _loadGlobalConfig(global.path)
      : const VoiceConfig();

  final configDirEntry = Directory(configDir);
  if (!configDirEntry.existsSync()) return (globalConfig, warnings);

  final files =
      configDirEntry
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.json'))
          .where((f) => !f.path.toLowerCase().endsWith('config.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final models = <String, TtsModelProfile>{};
  final defaults = <String, String>{};
  final pricing = <String, AudioPricing>{};
  final voices = <String, Map<String, Voice>>{};
  for (final f in files) {
    final alias = _stemOf(f.path);
    try {
      final m = _parseModelFile(f.path, alias);
      models[alias] = m.profile;
      if (m.defaultVoice != null) defaults[alias] = m.defaultVoice!;
      if (m.pricing != null) pricing[alias] = m.pricing!;
      if (m.voices.isNotEmpty) voices[alias] = m.voices;
    } on VoiceConfigurationError catch (e) {
      warnings.add('Skipped model "$alias": ${e.message}');
    }
  }

  final config = VoiceConfig(
    defaultModel: globalConfig.defaultModel,
    providers: globalConfig.providers,
    models: models,
    defaults: defaults,
    pricing: pricing,
    voices: voices,
  );

  final configuredDefault = config.defaultModel;
  if (configuredDefault != null &&
      configuredDefault.trim().isNotEmpty &&
      profileFor(configuredDefault.trim(), config) == null) {
    warnings.add(
      'default_model "$configuredDefault" is not a configured model; '
      'falling back to the compiled default.',
    );
  }

  return (config, warnings);
}

/// Parses the global `config.json`: `default_model` + the verbatim `providers`
/// block. Hard-errors on malformed content.
VoiceConfig _loadGlobalConfig(String path) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": top-level value must be a JSON object',
    );
  }
  final defaultModelRaw = raw['default_model'];
  if (defaultModelRaw != null && defaultModelRaw is! String) {
    throw VoiceConfigurationError(
      'Invalid voice config "$path": "default_model" must be a string',
    );
  }
  final providersOut = <String, Map<String, String>>{};
  final providersRaw = raw['providers'];
  if (providersRaw is Map<String, dynamic>) {
    providersRaw.forEach((id, settings) {
      if (settings is! Map<String, dynamic>) {
        throw VoiceConfigurationError(
          'Invalid voice config "$path": "providers.$id" must be an object',
        );
      }
      final out = <String, String>{};
      settings.forEach((key, value) {
        if (value is! String) {
          throw VoiceConfigurationError(
            'Invalid voice config "$path": "providers.$id.$key" must be a '
            'string',
          );
        }
        out[key] = value;
      });
      // Preserved as-is (even when empty) so the block round-trips verbatim.
      providersOut[id] = out;
    });
  }
  return VoiceConfig(
    defaultModel: defaultModelRaw as String?,
    providers: providersOut,
  );
}

/// Parses a single ``<alias>.json`` model file into a model profile plus its
/// default voice, pricing, and voice library. Throws a [VoiceConfigurationError] for
/// anything that makes the model unusable (skipped by the caller).
({
  TtsModelProfile profile,
  String? defaultVoice,
  AudioPricing? pricing,
  Map<String, Voice> voices,
})
_parseModelFile(String path, String alias) {
  final raw = _readJson(path);
  if (raw is! Map<String, dynamic>) {
    throw VoiceConfigurationError('must be a JSON object');
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw VoiceConfigurationError('needs a non-empty "id"');
  }
  final format = raw['format'];
  if (format != null && format is! String) {
    throw VoiceConfigurationError('"format" must be a string');
  }
  final sampleRate = raw['sample_rate'];
  if (sampleRate != null && sampleRate is! num) {
    throw VoiceConfigurationError('"sample_rate" must be a number');
  }
  final promptStyle = raw['prompt_style'];
  if (promptStyle != null && promptStyle is! bool) {
    throw VoiceConfigurationError('"prompt_style" must be a bool');
  }
  final sendsVoice = raw['sends_voice'];
  if (sendsVoice != null && sendsVoice is! bool) {
    throw VoiceConfigurationError('"sends_voice" must be a bool');
  }
  final provider = raw['provider'];
  if (provider is! String || provider.trim().isEmpty) {
    throw VoiceConfigurationError('needs a non-empty "provider"');
  }
  final displayName = raw['display_name'];
  if (displayName != null && displayName is! String) {
    throw VoiceConfigurationError('"display_name" must be a string');
  }

  String? defaultVoice;
  final defaultVoiceRaw = raw['default_voice'];
  if (defaultVoiceRaw != null) {
    if (defaultVoiceRaw is! String || defaultVoiceRaw.trim().isEmpty) {
      throw VoiceConfigurationError('"default_voice" must be a non-empty string');
    }
    defaultVoice = defaultVoiceRaw;
  }

  AudioPricing? pricing;
  final pricingRaw = raw['pricing'];
  if (pricingRaw != null) {
    if (pricingRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError('"pricing" must be an object');
    }
    pricing = AudioPricing(
      inputUsdPerMTokens: _num(pricingRaw['input_usd_per_m_tokens']),
      outputUsdPerMTokens: _num(pricingRaw['output_usd_per_m_tokens']),
      usdPerMChars: _num(pricingRaw['usd_per_m_chars']),
    );
  }

  final voices = <String, Voice>{};
  final voicesRaw = raw['voices'];
  if (voicesRaw != null) {
    if (voicesRaw is! Map<String, dynamic>) {
      throw VoiceConfigurationError('"voices" must be an object');
    }
    voicesRaw.forEach((label, value) {
      if (value is String) {
        // Legacy shorthand: "label": "id" with no metadata.
        if (value.isNotEmpty) voices[label] = Voice(id: value);
        return;
      }
      if (value is! Map<String, dynamic>) return; // skip malformed entries
      final id = value['id'];
      if (id is! String || id.isEmpty) return; // skip entries without an id
      voices[label] = Voice(
        id: id,
        gender: parseVoiceGender(
          value['gender'] is String ? value['gender'] : null,
        ),
      );
    });
  }

  return (
    profile: TtsModelProfile(
      alias: alias,
      id: id,
      format: format ?? 'mp3',
      promptStyle: promptStyle ?? false,
      sendsVoiceField: sendsVoice ?? true,
      sampleRate: sampleRate?.toInt(),
      provider: provider.trim(),
      displayName: displayName,
    ),
    defaultVoice: defaultVoice,
    pricing: pricing,
    voices: voices,
  );
}

/// Reads and JSON-decodes [path]; wraps read/decode failures in a
/// [VoiceConfigurationError].
Object? _readJson(String path) {
  try {
    return jsonDecode(File(path).readAsStringSync());
  } on FormatException catch (e) {
    throw VoiceConfigurationError('Invalid voice config "$path": ${e.message}');
  } on IOException catch (e) {
    throw VoiceConfigurationError('Cannot read voice config "$path": $e');
  }
}

/// Last path component of [path] without its extension.
String _stemOf(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot == -1 ? name : name.substring(0, dot);
}

/// The JSON for a single model's file. The `provider` is always written so
/// each file is self-describing (models route to their provider without any
/// global fallback); other fields elide values that merely restate defaults so
/// a hand-written file can stay minimal.
Map<String, Object?> _modelJson(TtsModelProfile p, VoiceConfig config) => {
  'id': p.id,
  'provider': p.provider,
  if (p.displayName != null) 'display_name': p.displayName,
  if (p.format != 'mp3') 'format': p.format,
  if (p.sampleRate != null) 'sample_rate': p.sampleRate,
  if (p.promptStyle) 'prompt_style': p.promptStyle,
  if (!p.sendsVoiceField) 'sends_voice': p.sendsVoiceField,
  if (config.defaults[p.alias] != null)
    'default_voice': config.defaults[p.alias],
  if (config.pricing[p.alias] != null)
    'pricing': {
      if (config.pricing[p.alias]!.usdPerMChars != null)
        'usd_per_m_chars': config.pricing[p.alias]!.usdPerMChars,
      if (config.pricing[p.alias]!.inputUsdPerMTokens != null)
        'input_usd_per_m_tokens': config.pricing[p.alias]!.inputUsdPerMTokens,
      if (config.pricing[p.alias]!.outputUsdPerMTokens != null)
        'output_usd_per_m_tokens': config.pricing[p.alias]!.outputUsdPerMTokens,
    },
  if (config.voices[p.alias] != null && config.voices[p.alias]!.isNotEmpty)
    'voices': {
      for (final e in config.voices[p.alias]!.entries)
        e.key: {
          'id': e.value.id,
          if (e.value.gender != null) 'gender': e.value.gender!.label,
        },
    },
};

/// Writes [config] to [configDir] as the shared config-directory schema,
/// creating the directory as needed: a `config.json` with `default_model` +
/// the verbatim `providers` block, and one ``<alias>.json`` per model (its
/// id/wiring plus the model's `provider`, `default_voice`, `pricing`, and
/// voice library — one object per voice), each directly in [configDir].
/// Round-trips through [loadVoiceConfig] so the CLI and GUI serialize
/// identically.
///
/// Throws a [VoiceConfigurationError] when a file cannot be written.
void writeVoiceConfig(String configDir, VoiceConfig config) {
  final globalJson = <String, Object?>{
    if (config.defaultModel != null) 'default_model': config.defaultModel,
    if (config.providers.isNotEmpty) 'providers': config.providers,
  };
  try {
    File('$configDir${Platform.pathSeparator}config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(globalJson),
        flush: true,
      );
  } on FileSystemException catch (e) {
    throw VoiceConfigurationError('Cannot write voice config "$configDir": $e');
  }

  if (config.models.isEmpty) return;
  Directory(configDir).createSync(recursive: true);
  for (final entry in config.models.entries) {
    final modelJson = _modelJson(entry.value, config);
    try {
      File('$configDir${Platform.pathSeparator}${entry.key}.json')
          .writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(modelJson),
            flush: true,
          );
    } on FileSystemException catch (e) {
      throw VoiceConfigurationError('Cannot write voice config "$configDir": $e');
    }
  }
}

/// Thrown when the voice config file exists but is unreadable or malformed,
/// or when a write fails.
class VoiceConfigurationError implements Exception {
  VoiceConfigurationError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Converts a JSON numeric value to a double, or null for non-numbers.
double? _num(Object? v) => v is num ? v.toDouble() : null;
