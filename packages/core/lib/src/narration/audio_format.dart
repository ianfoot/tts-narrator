/// The audio formats a narration can produce.
///
/// These are the only two options a model may offer. The vocabulary is
/// deliberately closed: an OpenAI-compatible `/audio/speech` endpoint that can
/// emit neither an MP3 stream nor WAV audio is not a usable backend, so there is
/// no third case to model.
///
/// Which containers a backend actually serves is a property of the backend, not
/// of its published schema. That schema is a lower bound on what works and has
/// already been observed to advertise a value its provider rejects, so settle
/// support by calling the endpoint and record the result in the model file
/// rather than inferring it from documentation.
enum TtsAudioFormat {
  /// Compressed MPEG audio. Small files, playable everywhere.
  mp3('mp3'),

  /// Uncompressed WAV container. Larger files, playable everywhere, and the
  /// app's default, since it needs no decoder to play.
  wav('wav');

  const TtsAudioFormat(this.wireValue);

  /// Used as the file extension written to disk.
  ///
  /// MP3 is also the value sent as `response_format`, since every backend probed
  /// serves it directly. WAV is *not* sent as `wav` unconditionally: some
  /// backends only produce WAV from headerless samples, so the request value for
  /// a wav run comes from [TtsWavResponseFormat] on the model profile instead.
  /// See that type for why.
  final String wireValue;

  /// File extension written to disk.
  String get extension => wireValue;

  /// Parses a model-file value, returning null for anything unsupported.
  ///
  /// There is no fallback mapping for an unrecognised name. A name the app does
  /// not know means the model file describes something it cannot do, and saying
  /// so is more useful than quietly producing a different container than the
  /// file asked for.
  static TtsAudioFormat? tryParse(String raw) {
    for (final format in values) {
      if (format.wireValue == raw) return format;
    }
    return null;
  }
}

/// The `response_format` value a model is asked for when the run's output format
/// is WAV.
///
/// Probing every shipped model on 2026-10-06 settled this: no OpenRouter model
/// serves a WAV container at all. Its `/audio/speech` request schema accepts
/// only `mp3` and `pcm`, and a `wav` request is rejected by OpenRouter's own
/// validator before a model is even chosen. Gemini goes further and rejects
/// `mp3` too, so it serves `pcm` and nothing else. The local mlx-audio server
/// does return a real WAV container, rate and all.
///
/// So a wav run has two possible paths and the model file says which: ask for
/// `wav` and write the provider's finished container through untouched, or ask
/// for `pcm` and write a header ahead of the samples. The rate for that header
/// comes from the response's own `Content-Type` rather than from config,
/// because only the response knows it.
enum TtsWavResponseFormat {
  /// The backend returns a finished WAV container. Its bytes are written to disk
  /// as they arrived.
  wav('wav'),

  /// The backend returns headerless samples. The app writes a WAV header ahead of
  /// them, so the file on disk is still a WAV.
  pcm('pcm');

  const TtsWavResponseFormat(this.wireValue);

  /// Value sent as `response_format` for a wav run.
  final String wireValue;

  /// Parses a model-file value, returning null for anything unsupported.
  static TtsWavResponseFormat? tryParse(String raw) {
    for (final format in values) {
      if (format.wireValue == raw) return format;
    }
    return null;
  }
}
