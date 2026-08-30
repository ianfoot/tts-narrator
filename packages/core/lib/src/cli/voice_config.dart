import 'dart:convert';
import 'dart:io';

import '../narration/cost.dart';
import '../narration/model_profiles.dart';

/// A single selectable voice for the GUI voice picker and CLI listing.
class VoiceEntry {
  const VoiceEntry({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
  });

  /// Model alias this voice belongs to (e.g. `gemini`, `fish`).
  final String model;

  /// Provider voice id sent in the request body.
  final String id;

  /// Human-readable label: the friendly alias when [isAlias], else the raw id.
  final String label;

  /// Whether [label] is a friendly alias from the config (vs a raw id).
  final bool isAlias;
}

/// Voice data, model wiring, and the optional API key, loaded from a single
/// JSON file.
///
/// Schema:
///   {
///     "api_key": "sk-or-...",            // optional
///     "models": {                        // optional per-model request wiring
///       "fish":   { "id": "fish-audio/s2.1-pro-free", "format": "mp3" },
///       "gemini": { "id": "google/gemini-3.1-flash-tts-preview",
///                   "format": "pcm", "sample_rate": 24000, "prompt_style": true }
///     },
///     "defaults": {                      // optional per-model default voice
///       "fish": "British Female Narrator"
///     },
///     "pricing": {                       // optional per-model cost data
///       "gemini": { "input_usd_per_m_tokens": 1.0, "output_usd_per_m_tokens": 20.0 },
///       "kokoro": { "usd_per_m_chars": 0.62 }
///     },
///     "voices": {
///       "fish":   { "British Female Narrator": "89f41ea2..." },
///       "kokoro": { "Emma": "bf_emma" }
///     }
///   }
///
/// Models, voices, and pricing live here rather than in code because providers
/// add/remove voices, prices drift, and model ids change (e.g. a gemini
/// preview id being replaced by a GA id) — all without a rebuild. The file is
/// optional: when no default config exists and `--config` was not given, an
/// empty config is used and everything degrades gracefully — fish's compiled
/// bootstrap remains the default; other models require a config `models`
/// entry; models without pricing are treated as free.
class VoiceConfig {
  const VoiceConfig({
    this.apiKey,
    this.defaultProvider,
    this.providers = const {},
    this.models = const {},
    this.defaults = const {},
    this.pricing = const {},
    this.aliases = const {},
  });

  /// Optional OpenRouter API key from the config file.
  final String? apiKey;

  /// Default provider id (`default_provider`) for models without an explicit
  /// `provider` in the `models` block; null falls back to the compiled
  /// `'openrouter'` default.
  final String? defaultProvider;

  /// Opaque per-provider settings (`providers.<id>` → string→string). Keys and
  /// values are never interpreted here — this is the raw block, round-tripped
  /// verbatim; `${ENV}` references are resolved at run-config build time via
  /// [resolveSettings], not at load/save time.
  final Map<String, Map<String, String>> providers;

  /// Per-model request wiring (model alias → profile), overriding or extending
  /// the compiled fish bootstrap.
  final Map<String, TtsModelProfile> models;

  /// Per-model default voice label (model alias → friendly name from [aliases]).
  final Map<String, String> defaults;

  /// Per-model cost data (model alias → pricing), for dry-run estimates.
  final Map<String, AudioPricing> pricing;

  /// Friendly-name → provider voice id, keyed by model alias.
  final Map<String, Map<String, String>> aliases;

  bool get isEmpty =>
      apiKey == null &&
      defaultProvider == null &&
      providers.isEmpty &&
      models.isEmpty &&
      defaults.isEmpty &&
      pricing.isEmpty &&
      aliases.isEmpty;

  /// Pricing for [modelAlias], or [freePricing] when unconfigured.
  AudioPricing pricingFor(String modelAlias) => pricing[modelAlias] ?? freePricing;

  /// Resolves a `--voice` value to the provider voice id for [modelAlias].
  ///
  /// If [value] matches a friendly alias for the model, the mapped raw id is
  /// returned. Otherwise the value is returned unchanged (free-form ids and
  /// raw id passthrough keep working exactly as before).
  (String id, String label) resolveVoice(String modelAlias, String value) {
    final modelAliases = aliases[modelAlias];
    if (modelAliases != null) {
      final id = modelAliases[value];
      if (id != null) return (id, value);
    }
    return (value, value);
  }
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

/// Resolves a friendly alias (or the raw id) for [modelAlias] to a provider id,
/// returning null when [value] matches neither.
String? _resolveAlias(VoiceConfig config, String modelAlias, String value) {
  final modelAliases = config.aliases[modelAlias];
  return modelAliases?[value] ?? (value.isNotEmpty ? value : null);
}

/// The default voice (+ friendly label) for [model], used when `--voice` /
/// the GUI voice field is empty.
///
/// Resolution order:
///   1. `defaults` in the config: the named voice must resolve via the model's
///      aliases (or be a raw id);
///   2. fish's compiled bootstrap ([kDefaultProfile]) when no config default is
///      set — the app's out-of-box, cost-free fallback;
///   3. otherwise a [VoiceConfigError]: model needs a `--voice` or a config
///      default.
(String id, String label) defaultVoiceFor(
  TtsModelProfile model,
  VoiceConfig config,
) {
  final configured = config.defaults[model.alias];
  if (configured != null && configured.trim().isNotEmpty) {
    final id = _resolveAlias(config, model.alias, configured);
    if (id != null) return (id, configured);
    throw VoiceConfigError(
      'Default voice "$configured" for "${model.alias}" is not a configured '
      'voice or raw id.',
    );
  }
  if (model.alias == kDefaultProfile.profile.alias) {
    return (kDefaultProfile.voice, kDefaultProfile.voiceLabel);
  }
  throw VoiceConfigError(
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
List<VoiceEntry> voiceEntries({
  TtsModelProfile? model,
  required VoiceConfig config,
}) {
  final profiles = model != null ? [model] : effectiveModels(config);
  final entries = <VoiceEntry>[];
  for (final p in profiles) {
    void add(String id, String label, bool isAlias) {
      if (entries.any((e) => e.model == p.alias && e.id == id)) return;
      entries.add(VoiceEntry(model: p.alias, id: id, label: label, isAlias: isAlias));
    }

    for (final e in (config.aliases[p.alias] ?? const <String, String>{}).entries) {
      add(e.value, e.key, true);
    }
    try {
      final (id, label) = defaultVoiceFor(p, config);
      add(id, label, false);
    } on VoiceConfigError {
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

/// Default config file location, shared by the CLI and GUI.
///
/// macOS/Linux: `~/.config/tts-narrator/voice_config.json`
/// Windows:     `%APPDATA%\tts-narrator\voice_config.json`
String defaultConfigPath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    return appData != null
        ? '$appData\\tts-narrator\\voice_config.json'
        : 'voice_config.json';
  }
  final home = Platform.environment['HOME'];
  final base = home != null ? '$home/.config/tts-narrator' : '.';
  return '$base/voice_config.json';
}

/// Loads a [VoiceConfig] from [path].
///
/// Throws a [VoiceConfigError] when the file exists but can't be read or
/// parsed. A missing file (whether default or explicitly requested) yields an
/// empty config — `--config` pointing at a bad file should still fail loudly
/// on read errors, which is handled by the caller.
VoiceConfig loadVoiceConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) return const VoiceConfig();
  try {
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('top-level value must be a JSON object');
    }
    final apiKey = raw['api_key'];
    if (apiKey != null && apiKey is! String) {
      throw const FormatException('"api_key" must be a string');
    }

    final defaultProviderRaw = raw['default_provider'];
    if (defaultProviderRaw != null && defaultProviderRaw is! String) {
      throw const FormatException('"default_provider" must be a string');
    }

    final providersOut = <String, Map<String, String>>{};
    final providersRaw = raw['providers'];
    if (providersRaw is Map<String, dynamic>) {
      providersRaw.forEach((id, settings) {
        if (settings is! Map<String, dynamic>) {
          throw FormatException('"providers.$id" must be an object');
        }
        final out = <String, String>{};
        settings.forEach((key, value) {
          if (value is! String) {
            throw FormatException('"providers.$id.$key" must be a string');
          }
          out[key] = value;
        });
        // Preserved as-is (even when empty) so the block round-trips verbatim.
        providersOut[id] = out;
      });
    }

    final models = <String, TtsModelProfile>{};
    final modelsRaw = raw['models'];
    if (modelsRaw is Map<String, dynamic>) {
      modelsRaw.forEach((alias, spec) {
        if (spec is! Map<String, dynamic>) {
          throw FormatException('"models.$alias" must be an object');
        }
        final id = spec['id'];
        if (id is! String || id.isEmpty) {
          throw FormatException('"models.$alias" needs a non-empty "id"');
        }
        final format = spec['format'];
        if (format != null && format is! String) {
          throw FormatException('"models.$alias.format" must be a string');
        }
        final sampleRate = spec['sample_rate'];
        if (sampleRate != null && sampleRate is! num) {
          throw FormatException('"models.$alias.sample_rate" must be a number');
        }
        final promptStyle = spec['prompt_style'];
        if (promptStyle != null && promptStyle is! bool) {
          throw FormatException('"models.$alias.prompt_style" must be a bool');
        }
        final sendsVoice = spec['sends_voice'];
        if (sendsVoice != null && sendsVoice is! bool) {
          throw FormatException('"models.$alias.sends_voice" must be a bool');
        }
        final provider = spec['provider'];
        if (provider != null && provider is! String) {
          throw FormatException('"models.$alias.provider" must be a string');
        }
        models[alias] = TtsModelProfile(
          alias: alias,
          id: id,
          format: format ?? 'mp3',
          promptStyle: promptStyle ?? false,
          sendsVoiceField: sendsVoice ?? true,
          sampleRate: sampleRate?.toInt(),
          provider: provider ?? 'openrouter',
        );
      });
    }

    final defaults = <String, String>{};
    final defaultsRaw = raw['defaults'];
    if (defaultsRaw is Map<String, dynamic>) {
      defaultsRaw.forEach((model, label) {
        if (label is String && label.isNotEmpty) defaults[model] = label;
      });
    }

    final pricingOut = <String, AudioPricing>{};
    final pricingRaw = raw['pricing'];
    if (pricingRaw is Map<String, dynamic>) {
      pricingRaw.forEach((model, spec) {
        if (spec is Map<String, dynamic>) {
          pricingOut[model] = AudioPricing(
            inputUsdPerMTokens: _num(spec['input_usd_per_m_tokens']),
            outputUsdPerMTokens: _num(spec['output_usd_per_m_tokens']),
            usdPerMChars: _num(spec['usd_per_m_chars']),
          );
        }
      });
    }

    final voicesOut = <String, Map<String, String>>{};
    final voices = raw['voices'];
    if (voices is Map<String, dynamic>) {
      voices.forEach((model, aliases) {
        final modelAliases = <String, String>{};
        if (aliases is Map<String, dynamic>) {
          aliases.forEach((label, id) {
            if (id is String && id.isNotEmpty) modelAliases[label] = id;
          });
        }
        if (modelAliases.isNotEmpty) voicesOut[model] = modelAliases;
      });
    }
    return VoiceConfig(
      apiKey: apiKey as String?,
      defaultProvider: defaultProviderRaw as String?,
      providers: providersOut,
      models: models,
      defaults: defaults,
      pricing: pricingOut,
      aliases: voicesOut,
    );
  } on FormatException catch (e) {
    throw VoiceConfigError('Invalid voice config "$path": ${e.message}');
  } on IOException catch (e) {
    throw VoiceConfigError('Cannot read voice config "$path": $e');
  }
}

Map<String, Object?> _modelJson(TtsModelProfile p) => {
      'id': p.id,
      'format': p.format,
      if (p.sampleRate != null) 'sample_rate': p.sampleRate,
      if (p.promptStyle) 'prompt_style': p.promptStyle,
      if (!p.sendsVoiceField) 'sends_voice': p.sendsVoiceField,
      // Only emit a per-model provider when it overrides the compiled default.
      if (p.provider != 'openrouter') 'provider': p.provider,
    };

/// Writes [config] to [path] as the shared `voice_config.json` schema,
/// creating parent directories as needed. Round-trips `api_key`,
/// `default_provider`, the verbatim `providers` block, `models`, `defaults`,
/// `pricing`, and the per-model voice aliases so the CLI and GUI serialize
/// identically.
///
/// Throws a [VoiceConfigError] when the file cannot be written.
void writeVoiceConfig(String path, VoiceConfig config) {
  final json = <String, Object?>{
    if (config.apiKey != null) 'api_key': config.apiKey,
    if (config.defaultProvider != null)
      'default_provider': config.defaultProvider,
    if (config.providers.isNotEmpty) 'providers': config.providers,
    if (config.models.isNotEmpty)
      'models': {for (final e in config.models.entries) e.key: _modelJson(e.value)},
    if (config.defaults.isNotEmpty) 'defaults': config.defaults,
    if (config.pricing.isNotEmpty)
      'pricing': {
        for (final e in config.pricing.entries)
          e.key: {
            if (e.value.usdPerMChars != null)
              'usd_per_m_chars': e.value.usdPerMChars,
            if (e.value.inputUsdPerMTokens != null)
              'input_usd_per_m_tokens': e.value.inputUsdPerMTokens,
            if (e.value.outputUsdPerMTokens != null)
              'output_usd_per_m_tokens': e.value.outputUsdPerMTokens,
          },
      },
    if (config.aliases.isNotEmpty) 'voices': config.aliases,
  };
  try {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  } on FileSystemException catch (e) {
    throw VoiceConfigError('Cannot write voice config "$path": $e');
  }
}

/// Thrown when the voice config file exists but is unreadable or malformed,
/// or when a write fails.
class VoiceConfigError implements Exception {
  VoiceConfigError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Converts a JSON numeric value to a double, or null for non-numbers.
double? _num(Object? v) => v is num ? v.toDouble() : null;