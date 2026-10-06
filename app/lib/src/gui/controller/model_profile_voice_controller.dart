import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'config_loader.dart';

/// Owns the active model profile, voice selection, and narrator-gender filter
/// for the TTS Narrator GUI.
///
/// The controller loads the shared [VoiceConfig] (same directory the CLI reads,
/// via its [UserVoiceConfigLoader]) and exposes the resolved profile, the selected
/// voice, and the gender-filtered voice items. [AppController] forwards its
/// model & voice surface here and re-broadcasts notifications, so callers keep
/// a single change stream.
///
/// There is no compiled default model: when the config directory has no models
/// (or no first provider whose first model resolves to one), [profile] and
/// [modelAlias] are null and there is nothing to select or narrate with.
/// Narration is blocked until the user supplies a config (the first-run
/// download prompt guides this).
///
/// The narration-settings side effects of the gender filter (rewriting the
/// narrator phrase in the passage prefix) live in [AppController], which owns
/// that setting and reacts to [voiceGenderFilter] writes through the facade.
class ModelProfileVoiceController extends ChangeNotifier {
  ModelProfileVoiceController({UserVoiceConfigLoader? loader})
    : _loader = loader ?? UserVoiceConfigLoader() {
    _voiceConfig = _loader.load();
    final def = defaultModelFor(_voiceConfig);
    _modelAlias = def?.alias;
    final voice = _defaultVoiceFor(def);
    _voice = voice?.$1 ?? '';
    _voiceLabel = voice?.$2;
    if (def != null) _language = _voiceConfig.defaultLanguageFor(def.alias);
  }

  final UserVoiceConfigLoader _loader;

  /// The preset default model (the first model of the first provider), or null
  /// when the config has none; [changeModel] moves to other configured models.
  late String? _modelAlias;
  late VoiceConfig _voiceConfig;

  // --- Model & voice ------------------------------------------------

  /// The active model profile (alias resolved against the loaded config), or
  /// null when the config has no models / no resolvable default.
  TtsModelProfile? get profile {
    final alias = _modelAlias;
    return alias == null ? null : profileFor(alias, _voiceConfig);
  }

  VoiceConfig get voiceConfig => _voiceConfig;

  /// Warnings surfaced while loading the voice config (e.g. a skipped
  /// malformed model file). Rendered as a persistent, non-fatal banner.
  List<String> get configWarnings => _loader.warnings;

  String? get modelAlias => _modelAlias;

  /// The app's only writer for the config directory. Reads resolve through it so
  /// an overlay file the user authored is what the editor shows, and every write
  /// lands in the overlay — the downloaded files are never rewritten, so a
  /// re-download can restore them without losing anything.
  VoiceConfigStore get voiceConfigStore => _store;
  late final VoiceConfigStore _store = VoiceConfigStore(_loader.configDir);

  /// Re-reads the config directory, keeping the selected model and voice.
  ///
  /// Called after the settings screen writes an overlay file, so the picker
  /// shows what was just saved without an app restart. The model alias is
  /// re-resolved against the new config and falls back to the default model if
  /// the file it named is gone; the voice is then re-picked by **id** from
  /// whatever is still visible, which keeps the reader on the same voice when a
  /// label was renamed and moves them to the default only when their id is
  /// genuinely gone. Either way the friendly label is re-read off the surviving
  /// id, so a rename in preferences stops showing the old name.
  ///
  /// The chosen language and gender filter are kept, because editing a voice
  /// changes neither. They are reset only when the model itself changed or is
  /// gone, the one case where the old choice cannot be honoured. The gender
  /// filter is re-validated against the new list in every case: delete the last
  /// voice matching it and the picker would keep filtering to a list that no
  /// longer holds the selected voice, so nothing would be highlighted while the
  /// run config still sent the hidden id.
  void reloadConfig() {
    _voiceConfig = _loader.load();
    final alias = _modelAlias;
    final stillThere = alias != null && profileFor(alias, _voiceConfig) != null;
    if (!stillThere) {
      _modelAlias = defaultModelFor(_voiceConfig)?.alias;
      _voiceGender = VoiceGender.neutral;
      _language = _voiceConfig.defaultLanguageFor(_modelAlias ?? '');
    }
    final p = profile;
    if (p == null) {
      notifyListeners();
      return;
    }
    // Re-validate the filter against the new list, the same way the setter does:
    // keep the full list rather than an empty one. A voice edit does not change
    // the filter, but it can empty it.
    if (_voiceGender != VoiceGender.neutral &&
        !_hasVisible(p, gender: _voiceGender)) {
      _voiceGender = VoiceGender.neutral;
    }
    final visible = _visibleEntries(p);
    _keepVisibleVoice(p, visible);
    if (_voice.isNotEmpty) {
      for (final e in visible) {
        if (e.id != _voice) continue;
        // Null when the entry's label is its bare id, which is what the picker
        // itself displays — same rule as setVoice/applyVoiceId.
        _voiceLabel = e.label != _voice ? e.label : null;
        break;
      }
    }
    notifyListeners();
  }

  /// Raw provider voice id; an empty string means "use the model default".
  String _voice = '';

  /// Friendly voice label when one was picked; null means the raw id.
  String? _voiceLabel;

  String get voice => _voice;

  String? get voiceLabel => _voiceLabel;

  /// Cost data for the active model (free until the config sets pricing, and
  /// always free when no model is configured).
  AudioPricing get pricing {
    final p = profile;
    return p == null ? freePricing : pricingFor(_voiceConfig, p.alias);
  }

  /// Resolves the provider settings block for [profile] (see
  /// `resolveSettings` in the core); used when assembling the run config.
  /// [overrides] are merged over the raw block before `${ENV}` expansion (see
  /// [UserVoiceConfigLoader.resolveProviderSettings]).
  Map<String, String> resolveProviderSettings(
    TtsModelProfile profile, {
    Map<String, String>? overrides,
  }) => _loader.resolveProviderSettings(profile, overrides: overrides);

  /// The raw (unexpanded) `settings` block for [profile] straight from
  /// `providers/<name>.json`, or an empty map when the provider has no block.
  /// The run-setup panel uses this to tell whether a key came from config (literal
  /// or `${ENV}` reference) vs the secure store.
  Map<String, String> rawProviderSettings(TtsModelProfile profile) =>
      _voiceConfig.providers[profile.provider]?.settings ?? const {};

  /// The environment the loader expands `${ENV}` references against. Exposed so
  /// the run-setup panel resolves an `api_key` reference against the same map the
  /// run config is built from, rather than a second copy of the process
  /// environment.
  Map<String, String> get environment => _loader.environment;

  /// The editable GUI options for the active model, derived from the
  /// capabilities it declares in its config file. Empty when no model is
  /// configured or the model declares none — the app has no per-model UI
  /// knowledge of its own.
  ModelUiSpec get modelUiSpec {
    final p = profile;
    return p == null ? const ModelUiSpec.empty() : ModelUiSpec.forProfile(p);
  }

  /// Default voice for the active [profile] from the config, or null when the
  /// model has no default configured (or no model is active).
  (String, String)? get defaultVoice => _defaultVoiceFor(profile);

  /// Default voice for [model] from the config, or null when the model has no
  /// default configured.
  (String, String)? _defaultVoiceFor(TtsModelProfile? model) {
    if (model == null) return null;
    try {
      return defaultVoiceFor(model, _voiceConfig);
    } on VoiceConfigurationError {
      return null;
    }
  }

  /// Switches the active model, preserving a user-set raw voice and resetting
  /// to the new model's default voice only when the current raw voice was
  /// (or equals) the previous model's default.
  void changeModel(String alias) {
    if (alias == _modelAlias) return;
    final next = profileFor(alias, _voiceConfig);
    if (next == null) return;
    final previousDefaultsTo = _defaultVoiceFor(profile)?.$1;
    if (_voice.isEmpty || _voice == previousDefaultsTo) {
      final def = _defaultVoiceFor(next);
      _voice = def?.$1 ?? '';
      _voiceLabel = def?.$2;
    } else {
      // A user-set raw voice survives the switch; the previous model's
      // friendly label no longer describes that id, so drop it.
      _voiceLabel = null;
    }
    _modelAlias = alias;
    // Gender tags and language tables are per-model; neither filter carries
    // across a switch. The surviving voice is left alone even when the new
    // model has no entry for it — a raw id is unvalidated passthrough, and the
    // picker just shows nothing highlighted.
    _voiceGender = VoiceGender.neutral;
    _language = _voiceConfig.defaultLanguageFor(alias);
    notifyListeners();
  }

  /// Sets a raw voice id (free-form ids and aliases both work; unvalidated —
  /// providers add/remove voices).
  void setVoice(String rawId, {String? label}) {
    _voice = rawId.trim();
    _voiceLabel = (label != null && label != _voice) ? label : null;
    notifyListeners();
  }

  /// Applies a voice picked from the list, by id.
  ///
  /// The list's value is the id, not the label, so a model with two voices of the
  /// same name (Kokoro has three Santas) selects the one the reader actually
  /// clicked. [label] is passed alongside for display only.
  /// Returns false (leaving the selection unchanged) when no model is active.
  bool applyVoiceId(String id, {String? label}) {
    final p = profile;
    if (p == null) return false;
    // Look the label up from the entry the id came from, so a pick from the
    // dropdown keeps its friendly name without the caller having to pass the
    // display string back through the widget.
    var friendly = label;
    for (final e in _visibleEntries(p)) {
      if (e.id == id) {
        friendly = e.label;
        break;
      }
    }
    setVoice(id, label: friendly);
    return true;
  }

  // --- Voice gender -------------------------------------------------

  /// Narrator-gender selection. Two uses, both flowing through this one field:
  /// narrowing the voice picker for models whose config tags voices with a
  /// gender, and (via a provider's `gender` model option) driving
  /// the narrator phrase in the passage prefix for prompt-style models. The
  /// passage-prefix side effect is applied by [AppController], which owns that
  /// setting. [VoiceGender.neutral] is "any / unselected".
  VoiceGender _voiceGender = VoiceGender.neutral;

  /// The active narrator gender; [VoiceGender.neutral] is "any".
  VoiceGender get voiceGenderFilter => _voiceGender;

  set voiceGenderFilter(VoiceGender value) {
    if (value == _voiceGender) return;
    _voiceGender = value;
    final p = profile;
    if (p != null) {
      if (value != VoiceGender.neutral && !_hasVisible(p, gender: value)) {
        // Nothing to narrow to: keep the full list rather than an empty one.
        _voiceGender = VoiceGender.neutral;
      }
      _keepVisibleVoice(p, _visibleEntries(p));
    }
    notifyListeners();
  }

  /// Whether the active model takes a voice at all.
  ///
  /// False for a model that writes its voice from prose instead (`"sends_voice":
  /// false`, as Qwen3 Voice Design does): it has no voices to choose between,
  /// and the picker has no row to select, so "Model & voice" drops the
  /// dropdown rather than showing an empty one.
  ///
  /// True while no model is selected, because "does not take a voice" is
  /// something a model has to declare; an empty config says nothing either way,
  /// and the section still shows its pickers rather than blanking itself before
  /// the user has chosen anything.
  bool get takesVoice => profile?.sendsVoiceField ?? true;

  /// Whether the active model has any voice of a known gender — tagged with
  /// `gender` in its config, or named by one (`<lang><gender>_<name>` ids read
  /// their gender off the id). Drives the voice-picker gender control in
  /// "Model & voice".
  bool get hasGenderTags {
    final p = profile;
    return p != null && _hasGenders(p);
  }

  // --- Voice language -----------------------------------------------

  /// The last language chosen in the picker, or the model's configured
  /// `default_language` when nothing has been chosen; null for a model that
  /// declares none.
  ///
  /// Backed by state rather than read straight off the voice so a model switch
  /// can restore the *new* model's default, and so a free-form voice id with no
  /// language prefix still leaves the picker on a real language. [language]
  /// prefers the selected voice and falls back to this.
  String? _language;

  /// The language the selected voice speaks, or null when the active model
  /// declares no languages.
  ///
  /// Read off the voice id, so the picker and the voice cannot disagree: any
  /// voice whose id starts with one of the model's declared codes *is* that
  /// language's voice. A raw id with no such prefix (or no voice selected yet)
  /// falls back to the last chosen language, then the model's default, then the
  /// first code it declares — so the picker always shows a concrete language
  /// rather than a blank.
  String? get language {
    final p = profile;
    if (p == null) return null;
    final codes = _voiceConfig.languagesFor(p.alias);
    if (codes.isEmpty) return null;
    final fromVoice = _voiceConfig.languageForId(p.alias, _voice);
    if (fromVoice != null) return fromVoice;
    final chosen = _language;
    if (chosen != null && codes.containsKey(chosen)) return chosen;
    final configured = _voiceConfig.defaultLanguageFor(p.alias);
    return configured != null && codes.containsKey(configured)
        ? configured
        : codes.keys.first;
  }

  /// Whether the active model declares a language table (drives the language
  /// dropdown in "Model & voice"); false for single-language models.
  bool get hasLanguages {
    final p = profile;
    return p != null && _voiceConfig.languagesFor(p.alias).isNotEmpty;
  }

  /// Selectable languages for the active model as `(code, label)`, in the order
  /// the model file declares them — the declaration order is the display order,
  /// so a config can put British English first.
  List<(String, String)> get languageItems {
    final p = profile;
    if (p == null) return const [];
    return [
      for (final e in _voiceConfig.languagesFor(p.alias).entries)
        (e.key, e.value),
    ];
  }

  /// Applies a language choice from the picker: keeps the current voice when it
  /// already speaks [code], otherwise switches to the model default voice in
  /// that language, else the first voice that speaks it.
  ///
  /// The language the reader picked always wins. When it is the *gender* filter
  /// that would empty the list — French has one voice and it is female, so Male +
  /// French leaves nothing — the gender filter is cleared rather than the
  /// language silently snapping back, which is the same bargain the gender setter
  /// makes in the other order. Only a language with no voice at all behind it is
  /// refused outright.
  ///
  /// That refusal is a rule about the voice list, so it does not apply to a model
  /// that has no voice list. Qwen3 Voice Design ships no voices at all and takes
  /// its language as the `lang_code` it synthesises in, so there is nothing for
  /// the list to hold behind any code: every language looked empty, every pick
  /// was refused, and the dropdown snapped back to the default however many times
  /// it was used. Such a model takes the choice as written.
  void applyLanguage(String code) {
    final p = profile;
    if (p == null) return;
    if (!_voiceConfig.languagesFor(p.alias).containsKey(code)) return;
    if (p.sendsVoiceField && !_hasVisible(p, language: code)) {
      if (!_hasVisible(p, language: code, gender: VoiceGender.neutral)) return;
      _voiceGender = VoiceGender.neutral;
    }
    _language = code;
    _keepVisibleVoice(p, _filteredEntries(p, language: code));
    notifyListeners();
  }

  /// The language the voice list is actually narrowed by: the [language] getter,
  /// so the list can never disagree with the dropdown that chose it.
  ///
  /// Filtering used to read the [_language] field, which left the two out of step
  /// whenever the language came from somewhere other than the picker — a voice id
  /// typed into Advanced Voice ID, say, which moves the dropdown without touching
  /// the field.
  String? get _activeLanguage => language;

  /// Whether the active model would show any voice under the given filters.
  /// Unset arguments fall back to the active [_activeLanguage] /
  /// [voiceGenderFilter].
  bool _hasVisible(
    TtsModelProfile p, {
    String? language,
    VoiceGender? gender,
  }) => _filteredEntries(
    p,
    language: language ?? _activeLanguage,
    gender: gender ?? _voiceGender,
  ).isNotEmpty;

  /// Voices the picker shows for the active model under the active filters.
  List<VoiceOption> _visibleEntries(TtsModelProfile p) =>
      _filteredEntries(p, language: _activeLanguage);

  /// Selectable voices for the active model, narrowed to [language] and
  /// [voiceGenderFilter]. Each entry is `(id, displayLabel)`: the id is the value
  /// because it is the only thing that distinguishes two voices sharing a name,
  /// and tagged voices get a compact ` (m)`/` (f)`/` (n)` suffix so gender is
  /// visible in the dropdown.
  List<(String, String)> get voiceItems {
    final p = profile;
    return p == null
        ? const <(String, String)>[]
        : [
            for (final e in _visibleEntries(p))
              (
                e.id,
                e.gender == null
                    ? e.label
                    : '${e.label} (${e.gender!.shorthand})',
              ),
          ];
  }

  /// Voices for [p] under an explicit language and gender filter.
  ///
  /// A model with no voice of a known gender has nothing to narrow against: a
  /// gender set via a prompt-style model's option still keeps the full list.
  List<VoiceOption> _filteredEntries(
    TtsModelProfile p, {
    String? language,
    VoiceGender? gender,
  }) {
    final entries = voiceEntries(
      model: p,
      config: _voiceConfig,
      language: language,
    );
    final g = gender ?? _voiceGender;
    if (g == VoiceGender.neutral) return entries;
    if (!_hasGenders(p)) return entries;
    return [
      for (final e in entries)
        if (e.gender == g) e,
    ];
  }

  /// Whether any of [p]'s selectable voices resolves to a gender, whether from a
  /// config tag or from its id.
  bool _hasGenders(TtsModelProfile p) =>
      voiceEntries(model: p, config: _voiceConfig).any((e) => e.gender != null);

  /// Makes sure the selected voice is one of [matches], so the picker never
  /// highlights a value the filters hide.
  ///
  /// Prefers the model default when it is visible — mirrors changeModel's
  /// reset-to-default semantics — and falls back to the first visible voice.
  void _keepVisibleVoice(TtsModelProfile p, List<VoiceOption> matches) {
    if (matches.isEmpty) return;
    // Match on the id, never the label: two voices may share a name (Kokoro
    // has three Santas), so a label match would keep a voice the filters hide.
    final current = _voice;
    final stillVisible = current.isNotEmpty
        ? matches.any((e) => e.id == current)
        : matches.any((e) => e.label == _voiceLabel);
    if (stillVisible) return;
    final def = _defaultVoiceFor(p);
    final defEntries = def == null
        ? const <VoiceOption>[]
        : matches.where((e) => e.id == def.$1);
    final pick = defEntries.isNotEmpty ? defEntries.first : matches.first;
    _voice = pick.id;
    _voiceLabel = pick.label;
  }
}
