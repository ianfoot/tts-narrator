import 'model_profiles.dart';

/// Declarative UI for a model's adjustable options.
///
/// [ModelUiSpec.forProfile] derives the controls from the model's own declared
/// capabilities ([TtsModelProfile.promptStyle] and [TtsModelProfile.supportsSpeed]),
/// and the app renders whatever comes back generically. Core ships no per-model
/// branches, and the app has none either.
///
/// Option keys are a convention the app interprets against the model-agnostic
/// narration settings:
///   `accent`/`style`/`passagePrefix` — editable text against the matching
///   narration settings;
///   `gender` — a narrator-gender (male/female/any) segmented control that the
///   app wires to its voice/narrator gender state;
///   `speed` — a speech-rate slider bound to the `NarrationConfig.speed`
///   setting (1.0 = normal).
///
/// A model declaring neither capability gets no model-option controls.
class ModelUiSpec {
  const ModelUiSpec([this.options = const <ModelUiControl>[]]);

  const ModelUiSpec.empty() : options = const <ModelUiControl>[];

  /// The controls [model] supports, derived from the profile's capabilities.
  ///
  /// `promptStyle` models understand accent/style/prefix directives woven into
  /// the text, so they get those fields plus a narrator-gender control the app
  /// rewrites into the narrated prose. `supportsSpeed` models get the speed
  /// slider. A model can qualify for either, both, or neither.
  factory ModelUiSpec.forProfile(TtsModelProfile model) {
    final options = <ModelUiControl>[];
    if (model.promptStyle) {
      options.addAll(const [
        ModelUiControl(
          key: 'gender',
          label: 'Narrator gender',
          type: ModelUiOptionType.gender,
        ),
        ModelUiControl(
          key: 'accent',
          label: 'Accent',
          hint: 'e.g., Southern British English',
        ),
        ModelUiControl(
          key: 'style',
          label: 'Style / register',
          hint: 'e.g., Warm, composed, literary',
        ),
        ModelUiControl(
          key: 'passagePrefix',
          label: 'Passage prefix',
          hint:
              'An opening directive woven into the first passage, read aloud '
              'before the story starts. Add `[calm] ` here for a calm style.',
          type: ModelUiOptionType.multiline,
        ),
      ]);
    }
    if (model.supportsSpeed) {
      options.add(
        const ModelUiControl(
          key: 'speed',
          label: 'Speed',
          type: ModelUiOptionType.speed,
        ),
      );
    }
    return ModelUiSpec(options);
  }

  /// The editable controls the model exposes, in display order.
  final List<ModelUiControl> options;

  bool get isEmpty => options.isEmpty;
}

/// A single editable option offered for a model.
class ModelUiControl {
  const ModelUiControl({
    required this.key,
    required this.label,
    this.type = ModelUiOptionType.text,
    this.hint,
  });

  /// Declarative key the app binds against a narration setting or narrator
  /// state (`accent`, `style`, `passagePrefix`, `gender`, `speed`).
  final String key;

  /// User-facing label for the control.
  final String label;

  /// How the option is edited.
  final ModelUiOptionType type;

  /// Optional placeholder hint.
  final String? hint;
}

/// How a [ModelUiControl] is edited in the GUI.
enum ModelUiOptionType { text, multiline, bool, gender, speed }
