/// Declarative UI for a model's adjustable options.
///
/// Which controls a model gets in the GUI is owned by the model's plugin (the
/// provider package): a provider overrides `TtsProvider.modelUiSpecFor` per
/// model and the app renders whatever options come back, generically. Core
/// ships no model-specific UI knowledge and the app has no per-model branches.
///
/// Option keys are a convention the app interprets against the model-agnostic
/// narration settings: `accent`, `style`, `passagePrefix`, and `useCalmTag`
/// bind to the corresponding `NarrationConfig` fields. A model whose plugin
/// declares no spec gets no model-option controls.
/// Options binding conventions the app interprets (see the rail):
///   `accent`/`style`/`passagePrefix` — editable text against the matching
///   narration settings;
///   `useCalmTag` — a bool toggle against the matching setting;
///   `gender` — a narrator-gender (male/female/any) segmented control that the
///   app wires to its voice/narrator gender state.
///
/// A model whose plugin declares no spec gets no model-option controls.
class ModelUiSpec {
  const ModelUiSpec([this.options = const <ModelUiControl>[]]);

  const ModelUiSpec.empty() : options = const <ModelUiControl>[];

  /// The editable controls the model exposes, in display order.
  final List<ModelUiControl> options;

  bool get isEmpty => options.isEmpty;
}

/// A single editable option declared by a model's plugin.
class ModelUiControl {
  const ModelUiControl({
    required this.key,
    required this.label,
    this.type = ModelUiOptionType.text,
    this.hint,
  });

  /// Declarative key the app binds against a narration setting or narrator
  /// state (`accent`, `style`, `passagePrefix`, `useCalmTag`, `gender`).
  final String key;

  /// User-facing label for the control.
  final String label;

  /// How the option is edited.
  final ModelUiOptionType type;

  /// Optional placeholder hint.
  final String? hint;
}

/// How a [ModelUiControl] is edited in the GUI.
enum ModelUiOptionType { text, multiline, bool, gender }
