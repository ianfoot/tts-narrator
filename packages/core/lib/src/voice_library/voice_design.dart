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
/// Sized for the 15 to 20 seconds a cloning model wants: long enough to settle
/// into a natural rhythm and show range, short enough that re-rolling is
/// quick enough to be worth doing several times.
const String kVoiceDesignPassage = '''
The harbour lights came on one by one as the evening settled over the water.
A gull turned above the pier, and somewhere along the quay a door closed
softly. She walked the length of the wall without hurrying, listening to the
noise of the town grow quieter with every step, and did not once look back.
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
    input: passage,
    responseFormat: TtsAudioFormat.wav,
    wavResponseFormat: profile.wavResponseFormat,
    settings: providerSettings,
    apiKey: apiKey,
    speed: profile.supportsSpeed ? speed : null,
    language: profile.sendsLanguageField ? language : null,
    instruct: instruct,
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