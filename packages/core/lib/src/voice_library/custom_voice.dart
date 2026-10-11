/// Stable, filesystem-safe identifier for a saved custom voice.
///
/// Also the stem of its clip: `<configDir>/user/voices/<id>.wav`. Allocation is
/// the store's job, so an id is always unique within one library and survives a
/// rename — renaming changes what the user sees, never where the audio lives.
extension type CustomVoiceId(String value);

/// The label the user gave a saved custom voice.
///
/// Free text and not unique: two clips can both be called "Warm", and a rename
/// to an existing label is allowed. Only the [CustomVoiceId] disambiguates.
extension type CustomVoiceName(String value);

/// A voice the user designed and kept.
///
/// A design model does not select a voice, it writes one: prose describing a
/// narrator goes out as `instruct`, and what comes back is an arbitrary voice
/// that will not be the same voice next time the same prose is sent. So a
/// custom voice is fundamentally *an audio clip* — [transcript] travels with it
/// because a cloning model that adopts the clip needs the words it was read
/// from to imitate the voice rather than just the timbre.
///
/// [instruct], [designModel] and [language] are kept only so the same prose can
/// be re-rolled into a fresh variation later. They never travel with the clip
/// when it is used; only [transcript] does.
class CustomVoice {
  const CustomVoice({
    required this.id,
    required this.name,
    required this.designModel,
    required this.instruct,
    required this.transcript,
    required this.createdAt,
    this.language,
  });

  /// Unique within a library, and the clip's filename stem.
  final CustomVoiceId id;

  /// What the user calls this voice in the library list.
  final CustomVoiceName name;

  /// Alias of the model that produced the clip, for display and re-rolling.
  final String designModel;

  /// The prose that produced the clip. Replayed by "new variation" only.
  final String instruct;

  /// The language the clip was generated in, when the design model was told one.
  final String? language;

  /// Verbatim text of the standard design passage as read by the clip.
  ///
  /// Sent as `ref_text` whenever this voice is used as a reference clip.
  final String transcript;

  /// When the clip was saved, kept so the library can be ordered by age.
  final DateTime createdAt;
}

/// Every custom voice saved under one config directory.
///
/// A plain list wrapper rather than a bare `List` so the lookup by id has a
/// home, and so an empty library is a normal value the app can hold from
/// startup instead of a nullable it has to test on every read.
class CustomVoiceLibrary {
  const CustomVoiceLibrary({this.voices = const []});

  /// An empty library, for a directory that has never held a custom voice.
  static const empty = CustomVoiceLibrary();

  final List<CustomVoice> voices;

  bool get isEmpty => voices.isEmpty;

  bool get isNotEmpty => voices.isNotEmpty;

  /// The voice with [id], or null when it has been removed.
  ///
  /// Takes the raw type so a caller holding an untyped string from the UI does
  /// not have to convert first.
  CustomVoice? byId(String id) {
    for (final voice in voices) {
      if (voice.id.value == id) return voice;
    }
    return null;
  }
}