import '../narration/abort.dart';
import '../narration/audio_format.dart';
import '../narration/model_profiles.dart';
import '../narration/speech_client.dart';
import '../narration/wav.dart';

/// The passage every designed voice is read from.
///
/// A cloning model that adopts a clip needs the words it was read from as well
/// as the voice: the audio alone fixes timbre, but the transcript is what lets
/// a model infer pace, emphasis and phrasing. That is the same `ref_text` a
/// hand-picked reference clip carries, and it is why this text is part of the
/// saved voice rather than an implementation detail of generating one.
///
/// Fixed rather than drawn from the user's document because it has to be the
/// *same* text every time. Comparing two designs only means something if the
/// difference between them is the voice, not the reading.
///
/// Sized by what it has to do rather than by a number of seconds: long enough
/// that a cloning model settles into a natural rhythm and has some range to
/// show, short enough that re-rolling is quick enough to be worth doing
/// several times.
///
/// The words themselves are the whiting and the snail from Lewis Carroll's
/// Alice's Adventures in Wonderland (1865), which is out of copyright. Public
/// domain, and already well known enough that a voice saying it sounds like a
/// voice saying something rather than reciting filler.
const String kVoiceDesignPassage = '''
Will you walk a little faster? said a whiting to a snail. There's a porpoise
close behind us, and he's treading on my tail. See how eagerly the lobsters
and the turtles all advance! They are waiting on the shingle, will you come
and join the dance?
''';

/// The audio for one designed voice, ready to audition or save.
///
/// Separate from [GeneratedAudio] because the bytes here have been through
/// [asWavBytes] and are a playable file rather than whatever the provider
/// happened to send.
class VoiceSample {
  const VoiceSample({required this.bytes, required this.attempts});

  final List<int> bytes;

  /// How many generations this design has taken so far. Carried so the UI can
  /// show that a re-roll is happening and not resetting anything.
  final int attempts;
}

/// Generates one sample clip for a voice described in prose.
///
/// A single request, deliberately not a narration: there is no segmenting, no
/// resume, no manifest and no concatenation, because the output is one clip
/// rather than a chapter. It goes through the same client and the same WAV
/// normalisation as narration, so a clip that saves cleanly is one a cloning
/// model can actually read.
///
/// [voice] is null and no reference audio is sent. That is not an oversight:
/// a design model is the source of the voice, and a design model with a
/// reference clip is being asked to imitate something while inventing it.
Future<VoiceSample> generateVoiceSample({
  required SpeechClient client,
  required TtsModelProfile profile,
  required String instruct,
  required Map<String, String> providerSettings,
  required int attempts,
  String? apiKey,
  String? language,
  double? speed,
  String passage = kVoiceDesignPassage,
  AbortToken? abort,
}) async {
  final audio = await client(
    model: profile.id,
    voice: null,
    input: inputForWire(profile, passage, instruct),
    responseFormat: TtsAudioFormat.wav,
    wavResponseFormat: profile.wavResponseFormat,
    settings: providerSettings,
    apiKey: apiKey,
    speed: profile.supportsSpeed ? speed : null,
    language: profile.sendsLanguageField ? language : null,
    // Sent only to a model with somewhere to put it: one that takes the
    // description on `input` reads an `instruct` out loud instead, so asking
    // for both would put the description in the clip twice, spoken.
    instruct: profile.instructAsInputPrefix ? null : instruct,
    abort: abort,
  );
  return VoiceSample(
    bytes: asWavBytes(
      format: TtsAudioFormat.wav,
      wavResponseFormat: profile.wavResponseFormat,
      modelId: profile.id,
      audio: audio,
    ),
    attempts: attempts,
  );
}