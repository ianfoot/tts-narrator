/// Per-model request profiles.
///
/// Every TTS model served by an OpenAI-compatible provider exposes the same
/// `/audio/speech` endpoint and auth, but they differ in the request body, the
/// output format, and how voices work. A [TtsModelProfile] captures the *wiring*
/// needed to build a request for a given model.
///
/// Models are never compiled here: they come only from the user's config
/// directory (`<alias>.json`), so pointing at a different or newer model id needs
/// no rebuild. Voices and pricing are user data too, living in the same files.
library;

import 'audio_format.dart';

class TtsModelProfile {
  const TtsModelProfile({
    required this.alias,
    required this.id,
    required this.formats,
    this.wavResponseFormat = TtsWavResponseFormat.wav,
    this.promptStyle = false,
    this.sendsVoiceField = true,
    this.supportsSpeed = false,
    this.sendsLanguageField = false,
    this.sendsInstructField = false,
    this.sendsReferenceAudioField = false,
    this.instructAsInputPrefix = false,
    required this.provider,
    this.displayName,
    this.defaultInstruct,
    this.voicesEditable = false,
  });

  /// Short alias for the model, matched against [id] as a fallback.
  final String alias;

  /// Full model identifier sent in the request body.
  final String id;

  /// Optional friendly name for the GUI dropdown (e.g. "Fish Audio S2.1
  /// (Free)"). Null falls back to the `alias — id` pairing in UI labels.
  final String? displayName;

  /// Output formats this model can produce, most-preferred first.
  ///
  /// Required, and never empty: a model file that does not say what it can produce
  /// is one the app cannot act on, so the parser rejects it rather than assuming.
  /// The first entry is the default for a fresh run; a single-entry list means no
  /// choice to make, so the GUI hides the format picker.
  ///
  /// Recorded in the model file because core has no compiled-in model list and
  /// cannot probe a provider. Each name becomes the file extension, so a format
  /// listed here is a promise the backend keeps.
  final List<TtsAudioFormat> formats;

  /// The format a run uses unless the user picks another one.
  TtsAudioFormat get defaultFormat => formats.first;

  /// What to ask this model for when the run's output format is WAV.
  ///
  /// No single value works everywhere: some backends return a finished WAV
  /// container, some headerless samples that need a header the app writes.
  /// Defaults to `wav`, which writes the provider's bytes through untouched — the
  /// path that cannot mislabel anything. A model that needs `pcm` says so.
  final TtsWavResponseFormat wavResponseFormat;

  /// Whether [format] is one this model can produce.
  bool supportsFormat(TtsAudioFormat format) => formats.contains(format);

  /// Whether accent/style/[calm] directives are woven into the input text.
  /// Gemini understands these; models like Kokoro would read them aloud.
  final bool promptStyle;

  /// Whether to include a `voice` field in the request body.
  final bool sendsVoiceField;

  /// Whether the model accepts a `speed` multiplier in the request body.
  ///
  /// The OpenAI speech protocol defines the field but not every vendor honours it,
  /// so it is opt-in per model (`"speed": true`). When false the field is omitted
  /// rather than sent at a default, and the GUI hides the slider.
  final bool supportsSpeed;

  /// Whether the model accepts a `lang_code` field in the request body.
  ///
  /// Kokoro ships one multi-language voice set, where the language is named by the
  /// voice id's first character and the API also takes it as an explicit
  /// `lang_code`. Opt-in per model (`"sends_language": true`) for the same reason
  /// as [supportsSpeed].
  final bool sendsLanguageField;

  /// Whether the model accepts an `instruct` field in the request body.
  ///
  /// Qwen3 Voice Design has no voice list at all: it *writes* the voice from prose
  /// — persona and demographics, pitch and timbre, pace, emotional tone, accent.
  /// That prose travels in `instruct`, a field no other model on the protocol
  /// defines, so it is opt-in per model (`"sends_instruct": true`) exactly like
  /// [supportsSpeed]. Mutually exclusive in practice with [sendsVoiceField]: a
  /// voice-design model is described, not selected.
  final bool sendsInstructField;

  /// Whether the model accepts `ref_audio` and `ref_text` to clone a voice from a
  /// reference clip instead of selecting a preset one.
  ///
  /// `ref_audio` is a path on the *provider's* filesystem, not an upload, so this
  /// only works where the TTS server shares a filesystem with the app — which is
  /// exactly the `local` provider case. Opt-in per model
  /// (`"sends_reference_audio": true`) for the same reason as [sendsInstructField]:
  /// a hosted vendor with no such field would reject the request.
  final bool sendsReferenceAudioField;

  /// Whether the voice description is prepended to `input` in brackets rather
  /// than sent in `instruct`.
  ///
  /// Most voice-design models take prose in `instruct` and use it as a
  /// description. mlx-audio's Fish Audio S2 Pro has no such field: asked for one
  /// it reads it out loud, so the narration opens with the instruction spoken
  /// instead of the text. It takes the description as a bracketed prefix on the
  /// words themselves — `[a calm male narrator] The harbour lights…` — and
  /// nothing else, which is why [inputForWire] prepends and [sendsInstructField]
  /// still governs only whether the app offers the Voice design box.
  ///
  /// Opt-in per model (`"instruct_as_input_prefix": true`) because this is a
  /// property of one server rather than of the protocol — there is no documented
  /// field for it, only this build's behaviour. A model that starts wanting a
  /// real `instruct` field is one line of config away from no longer asking.
  final bool instructAsInputPrefix;

  /// Name of the `providers.<name>` block that serves this model. Required in
  /// the model config file, and opaque to core: it is a lookup key into user
  /// config, never a vendor the code knows about.
  final String provider;

  /// The `instruct` prose a [sendsInstructField] model starts from, if the model
  /// file supplies one.
  ///
  /// Voice design has no "unset" state to fall back to — the model is described or
  /// it is not. Carrying it on the profile is what lets the GUI prefill an editable
  /// control without core knowing anything about GUI defaults.
  final String? defaultInstruct;

  /// Whether the user may edit this model's voice list from the app.
  ///
  /// Some models have a closed voice set the provider defines (Gemini's 30 named
  /// voices, Kokoro's 54 language-prefixed ids); Fish accepts any id, so there the
  /// useful thing is a user-curated list. Opt-in per model
  /// (`"voices_editable": true`), defaulting to false.
  ///
  /// This gates the *UI affordance* only: a hand-written overlay can change any
  /// model's voices, and the loader honours it regardless of this flag.
  final bool voicesEditable;

  TtsModelProfile copyWith({
    String? id,
    String? provider,
    List<TtsAudioFormat>? formats,
    TtsWavResponseFormat? wavResponseFormat,
  }) => TtsModelProfile(
    alias: alias,
    id: id ?? this.id,
    formats: formats ?? this.formats,
    wavResponseFormat: wavResponseFormat ?? this.wavResponseFormat,
    promptStyle: promptStyle,
    sendsVoiceField: sendsVoiceField,
    supportsSpeed: supportsSpeed,
    sendsLanguageField: sendsLanguageField,
    sendsInstructField: sendsInstructField,
    sendsReferenceAudioField: sendsReferenceAudioField,
    instructAsInputPrefix: instructAsInputPrefix,
    provider: provider ?? this.provider,
    displayName: displayName,
    defaultInstruct: defaultInstruct,
    voicesEditable: voicesEditable,
  );
}

/// The `input` to send for [profile], given the text [input] to speak.
///
/// Models that take their voice description as a bracketed prefix get it
/// prepended here, because there is no separate field for it: the description
/// has to sit on the front of the words being spoken to be read as a direction
/// rather than as something to say out loud. A blank description is left off
/// entirely rather than sending a bare `[]`.
///
/// Every other model gets [input] untouched, which is the whole behaviour for
/// all but [TtsModelProfile.instructAsInputPrefix].
String inputForWire(TtsModelProfile profile, String input, String? instruct) {
  if (!profile.instructAsInputPrefix) return input;
  final description = instruct?.trim() ?? '';
  if (description.isEmpty) return input;
  return '[$description] $input';
}
