/// The audio formats a narration can produce.
///
/// These are the only two options a model may offer and the only two values
/// that ever reach a provider request. The vocabulary is deliberately closed:
/// an OpenAI-compatible `/audio/speech` endpoint that can emit neither an MP3
/// stream nor a native WAV container is not a usable backend, so there is no
/// third case to model.
///
/// Note that the output format is also the wire format. OpenRouter's
/// `/audio/speech` accepts `mp3` and `pcm` only and has no WAV mode, so a WAV
/// file can only come from a server that emits a real WAV container natively
/// (see `kokoro_local`). That constraint is why PCM does not appear here: the
/// app has no raw-sample path to wrap.
enum TtsAudioFormat {
  /// Compressed MPEG audio. Small files, playable everywhere, and the only
  /// format the hosted providers serve.
  mp3('mp3'),

  /// Uncompressed WAV container. Larger files, playable everywhere, and only
  /// available from a provider that emits the container itself.
  wav('wav');

  const TtsAudioFormat(this.wireValue);

  /// Value sent as `response_format` and used as the file extension.
  ///
  /// Both are the enum name, so this exists only to give the request and the
  /// on-disk extension one named source of truth.
  final String wireValue;

  /// File extension written to disk.
  String get extension => wireValue;

  /// Parses a model-file value, returning null for anything unsupported.
  static TtsAudioFormat? tryParse(String raw) {
    for (final format in values) {
      if (format.wireValue == raw) return format;
    }
    return null;
  }

  /// Maps the legacy single-format vocabulary onto the supported formats.
  ///
  /// Older model files declared one `format` string, which could be `pcm`:
  /// headerless samples the app wrapped in a WAV container. There is no
  /// equivalent now, so `pcm` maps to [mp3] — the only compressed format the
  /// models that used it can still produce.
  static TtsAudioFormat? fromLegacy(String raw) {
    if (raw == 'pcm') return mp3;
    return tryParse(raw);
  }
}
