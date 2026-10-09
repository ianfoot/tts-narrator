/// The audio formats a narration can produce.
///
/// The vocabulary is deliberately closed: an OpenAI-compatible `/audio/speech`
/// endpoint that emits neither an MP3 stream nor WAV audio is not a usable backend.
///
/// Which containers a backend serves is a property of the backend, not of its
/// published schema — that schema is a lower bound and has already advertised a
/// value the provider rejects, so settle support by calling the endpoint and
/// record it in the model file.
enum TtsAudioFormat {
  /// Compressed MPEG audio. Small files, playable everywhere.
  mp3('mp3'),

  /// Uncompressed WAV container. Larger files, playable everywhere, and the
  /// app's default, since it needs no decoder to play.
  wav('wav');

  const TtsAudioFormat(this.wireValue);

  /// Used as the file extension written to disk.
  ///
  /// MP3 is also the value sent as `response_format`. WAV is *not*: some backends
  /// only produce WAV from headerless samples, so the request value comes from
  /// [TtsWavResponseFormat] on the model profile instead.
  final String wireValue;

  /// File extension written to disk.
  String get extension => wireValue;

  /// Parses a model-file value, returning null for anything unsupported.
  ///
  /// No fallback mapping for an unrecognised name: a name the app does not know
  /// means the model file describes something it cannot do, and saying so beats
  /// quietly producing a different container than the file asked for.
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
/// serves a WAV container — its `/audio/speech` schema accepts only `mp3` and
/// `pcm`, and `wav` is rejected by its own validator before a model is chosen.
/// Gemini rejects `mp3` too, so it serves `pcm` and nothing else. The local
/// mlx-audio server does return a real WAV container.
///
/// So a wav run has two paths and the model file says which: ask for `wav` and
/// write the provider's container through, or ask for `pcm` and write a header
/// ahead of the samples. That header's rate comes from the response's own
/// `Content-Type`, the only place that knows it.
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
