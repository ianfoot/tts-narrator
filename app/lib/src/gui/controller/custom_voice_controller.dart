import 'package:flutter/foundation.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'model_profile_voice_controller.dart';
import 'settings_controller.dart';

/// Design, audition and keep the voices a user invents for themselves.
///
/// A design model does not select a voice, it writes one: prose describing a
/// narrator goes out as `instruct` and what comes back is an arbitrary voice
/// that will differ every time the same prose is sent. So the shape of this
/// whole feature is a loop rather than a form -- generate, listen, then keep or
/// throw away -- and the state it exists to hold is the throw-away part.
///
/// A generation therefore lives in [draft] and in memory only. Nothing reaches
/// disk until [saveDraft] says it was worth keeping, so the common outcome --
/// most generations being rejected -- costs the user nothing and leaves no
/// litter for them to clean up by hand.
class CustomVoiceController extends ChangeNotifier {
  CustomVoiceController({
    required ModelProfileVoiceController model,
    required SettingsController settings,
    required SpeechClient client,
    CustomVoiceStore? store,
  }) {
    // Assigned in the body, as [AppController] does with its own sub-controllers:
    // it keeps the public parameter names plain, which `this._field` initialising
    // formals would not.
    _model = model;
    _settings = settings;
    _client = client;
    // Taken from the model controller's own store rather than a second config-dir
    // source, so the voice library and the voice config can only ever disagree
    // about where they live if the loader itself moves.
    _store = store ?? CustomVoiceStore(model.voiceConfigStore.configDir);
    _library = _store.read();
    _syncDesignModel();
  }

  late final ModelProfileVoiceController _model;
  late final SettingsController _settings;
  late final SpeechClient _client;
  late final CustomVoiceStore _store;

  late CustomVoiceLibrary _library;

  VoiceDraft? _draft;
  bool _generating = false;
  String? _error;
  String? _designModelAlias;
  String? _designLanguage;

  /// Every saved voice, in the order they were saved.
  CustomVoiceLibrary get library => _library;

  /// The voices that can be described rather than selected.
  ///
  /// Filtered on the profile flag rather than on a name, so a model added to the
  /// shipped config later appears here without this file knowing it exists.
  List<TtsModelProfile> get designModels => effectiveModels(_model.voiceConfig)
      .where((profile) => profile.sendsInstructField)
      .toList();

  /// Whether any model on offer can design a voice at all.
  bool get canDesign => designModels.isNotEmpty;

  /// Where the clip for [voice] is on disk.
  ///
  /// Exposed because `ref_audio` is a path on the provider's filesystem rather
  /// than an upload, so adopting a saved voice means handing over a location.
  /// The store owns that location; nothing else should be guessing at it.
  String clipPathFor(CustomVoice voice) => _store.wavFile(voice.id.value).path;

  /// The clip being auditioned, or null when nothing has been generated.
  ///
  /// Held as bytes rather than a path precisely so discarding it is free.
  VoiceDraft? get draft => _draft;

  /// Whether a generation is in flight. A second one is refused rather than
  /// queued, because two overlapping designs would race for the same draft.
  bool get generating => _generating;

  /// Why the last save, rename, delete or generation failed, or null.
  String? get error => _error;

  /// The model the design panel will speak to.
  TtsModelProfile? get designModel {
    final models = designModels;
    if (models.isEmpty) return null;
    return models.firstWhere(
      (profile) => profile.alias == _designModelAlias,
      orElse: () => models.first,
    );
  }

  /// The language the design panel will request, or null to leave it unset.
  String? get designLanguage => _designLanguage;

  /// The languages [designModel] offers, as `(code, label)` rows.
  List<(String, String)> get designLanguageItems =>
      _model.voiceConfig
          .languagesFor(designModel?.alias ?? '')
          .entries
          .map((entry) => (entry.key, entry.value))
          .toList();

  /// Chooses the model the panel speaks to, dropping a language the new model
  /// does not offer.
  void selectDesignModel(String? alias) {
    if (alias == null || _designModelAlias == alias) return;
    _designModelAlias = alias;
    _syncDesignLanguage();
    notifyListeners();
  }

  /// Chooses the language the clip is read in.
  void selectDesignLanguage(String? code) {
    if (_designLanguage == code) return;
    _designLanguage = code;
    notifyListeners();
  }

  /// Generates a clip from [instruct] and puts it up for audition.
  ///
  /// Any existing draft is thrown away first, so the card leaves as soon as a
  /// new generation starts rather than sitting under the request being made.
  /// The attempt counter rises when the same prose is re-rolled and resets when
  /// the prose changes, so the card can tell the user which of the two they are
  /// looking at.
  Future<void> generate(String instruct) async {
    final profile = designModel;
    if (profile == null || _generating) return;

    final trimmed = instruct.trim();
    if (trimmed.isEmpty) {
      _error = 'Describe the voice before generating.';
      notifyListeners();
      return;
    }

    final previous = _draft;
    final sameProse = previous != null && previous.instruct == trimmed;
    _draft = null;
    _generating = true;
    _error = null;
    notifyListeners();

    try {
      final request = _settings.providerRequestFor(profile);
      final sample = await generateVoiceSample(
        client: _client,
        profile: profile,
        instruct: trimmed,
        providerSettings: request.settings,
        apiKey: request.apiKey,
        language: _designLanguage,
        attempts: sameProse ? previous.attempts + 1 : 1,
      );
      _draft = VoiceDraft(
        bytes: sample.bytes as Uint8List,
        modelAlias: profile.alias,
        instruct: trimmed,
        transcript: kVoiceDesignPassage,
        attempts: sample.attempts,
        language: _designLanguage,
      );
    } on AbortException {
      // Cancelled on purpose, and the draft it replaced is already gone.
    } catch (e) {
      _error = '$e';
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  /// Keeps the current clip under [name] and clears the draft.
  ///
  /// The name is asked for only now, because until this point the user has been
  /// auditioning an anonymous clip: asking up front would mean inventing a name
  /// for every throwaway generation.
  CustomVoiceEdit? saveDraft(String name) {
    final draft = _draft;
    if (draft == null) return null;

    final result = _store.add(
      name: name,
      bytes: draft.bytes,
      modelAlias: draft.modelAlias,
      instruct: draft.instruct,
      transcript: draft.transcript,
      language: draft.language,
    );
    if (!result.ok) {
      _error = result.error;
      notifyListeners();
      return result;
    }
    _library = _store.read();
    _draft = null;
    _error = null;
    notifyListeners();
    return result;
  }

  /// Restores the panel to [voice]'s design so the next generation explores
  /// around the one that was kept.
  ///
  /// Seeds no audio: a new variation is a first generation like any other, and
  /// the clip the user already has must stay on disk untouched. Adopting the
  /// model and language as well as the prose matters — the same sentence through
  /// a different design model is a different voice entirely, not a variation of
  /// the saved one.
  void seedVariation(CustomVoice voice) {
    _designModelAlias = voice.designModel;
    _designLanguage = voice.language;
    _syncDesignLanguage();
    notifyListeners();
  }

  /// Reloads the library from disk.
  ///
  /// Called after a config reload so a registry hand-edited while the app was
  /// open is picked up.
  void refresh() {
    _library = _store.read();
    notifyListeners();
  }

  /// Renames a saved voice. Touches nothing but the label.
  CustomVoiceEdit rename(String id, String name) =>
      _apply(_store.rename(id, name));

  /// Deletes a saved voice along with its clip.
  CustomVoiceEdit delete(String id) => _apply(_store.remove(id));

  CustomVoiceEdit _apply(CustomVoiceEdit result) {
    if (result.ok) {
      _library = _store.read();
      _error = null;
    } else {
      _error = result.error;
    }
    notifyListeners();
    return result;
  }

  /// Clears [error] so the message does not outlive the thing it described.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void _syncDesignModel() {
    if (_designModelAlias != null &&
        designModels.any((profile) => profile.alias == _designModelAlias)) {
      return;
    }
    _designModelAlias = designModels.firstOrNull?.alias;
    _syncDesignLanguage();
  }

  /// Keeps the language one the chosen model actually offers.
  ///
  /// The two shipped design models offer different tables, and mlx-audio reads
  /// an absent `lang_code` as a Kokoro code rather than "nothing", so a stale
  /// language is worse than none.
  void _syncDesignLanguage() {
    final codes = designLanguageItems.map((item) => item.$1).toSet();
    if (_designLanguage == null || codes.contains(_designLanguage)) return;
    _designLanguage = null;
  }
}