import 'dart:io';
import 'dart:typed_data';

import 'audio_format.dart';
import 'speech_client.dart';

/// A WAV file split into the two parts a concatenation needs: the `fmt ` chunk
/// describing the audio layout, and the `data` chunk holding the audio.
class WavFile {
  WavFile({required this.formatChunk, required this.data});

  /// The `fmt ` chunk exactly as the encoder wrote it, id and size included.
  ///
  /// Carried verbatim rather than decoded, because nothing downstream needs the
  /// numbers: a combined file just has to declare the same layout its samples
  /// actually have. Reusing the bytes means the app never has to know or guess
  /// the rate, and a chunk shape it does not model (a bit depth above 16, an
  /// extensible header) still round-trips intact.
  final Uint8List formatChunk;

  /// Audio samples, without the surrounding container.
  final Uint8List data;
}

/// Splits the RIFF/WAVE container in [bytes] into its format and data chunks.
///
/// Throws a [FileSystemException] when the bytes are not a WAV file, so
/// non-audio content is rejected instead of being spliced into a narration.
WavFile readWav(Uint8List bytes) {
  if (bytes.length < 12 ||
      _ascii(bytes.sublist(0, 4)) != 'RIFF' ||
      _ascii(bytes.sublist(8, 12)) != 'WAVE') {
    throw FileSystemException('Not a WAV file (bad header).');
  }
  final data = ByteData.sublistView(bytes);
  Uint8List? formatChunk;
  Uint8List? samples;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _ascii(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + size;
    if (payloadEnd > bytes.length) {
      throw FileSystemException('Not a WAV file (truncated chunk).');
    }
    if (id == 'fmt ' && formatChunk == null) {
      formatChunk = Uint8List.sublistView(bytes, offset, payloadEnd);
    } else if (id == 'data' && samples == null) {
      samples = Uint8List.sublistView(bytes, payloadStart, payloadEnd);
    }
    // Chunks are word-aligned, so an odd-sized one is followed by a pad byte
    // that is not counted in its size. Real encoder output includes it.
    offset = payloadEnd + (size.isOdd ? 1 : 0);
  }
  if (formatChunk == null) {
    throw FileSystemException('Not a WAV file (no format chunk).');
  }
  if (samples == null) {
    throw FileSystemException('Not a WAV file (no data chunk).');
  }
  return WavFile(formatChunk: formatChunk, data: samples);
}

/// Builds a 44-byte WAV header for [dataBytes] of headerless samples.
///
/// The counterpart to [writeWav] for a provider returning raw samples instead of
/// a container. The result is the same canonical layout every probed backend
/// serves natively — 16-bit linear PCM — so a pcm-sourced file and a
/// natively-served one are indistinguishable to a player. [sampleRate] and
/// [channels] come from the response, the only place that knows them.
Uint8List wavHeader({
  required int sampleRate,
  required int channels,
  required int dataBytes,
}) {
  const bytesPerSample = 2;
  final byteRate = sampleRate * channels * bytesPerSample;
  final header = BytesBuilder(copy: false);
  header.add(_asciiEncode('RIFF'));
  header.add(_u32le(36 + dataBytes));
  header.add(_asciiEncode('WAVE'));
  header.add(_asciiEncode('fmt '));
  header.add(_u32le(16)); // Size of the format chunk that follows.
  header.add(_u16le(1)); // Format tag: linear PCM.
  header.add(_u16le(channels));
  header.add(_u32le(sampleRate));
  header.add(_u32le(byteRate));
  header.add(_u16le(channels * bytesPerSample)); // Block align.
  header.add(_u16le(8 * bytesPerSample)); // Bits per sample.
  header.add(_asciiEncode('data'));
  header.add(_u32le(dataBytes));
  return header.takeBytes();
}

/// Writes [audio] as a WAV file at [path], declaring [formatChunk] verbatim as
/// its layout.
void writeWav({
  required String path,
  required BytesBuilder audio,
  required Uint8List formatChunk,
}) {
  final samples = audio.takeBytes();
  final header = BytesBuilder(copy: false);
  header.add(_asciiEncode('RIFF'));
  // Everything after the RIFF size field: WAVE, the format chunk, and the data
  // chunk's id and size.
  header.add(_u32le(4 + formatChunk.length + 8 + samples.length));
  header.add(_asciiEncode('WAVE'));
  header.add(formatChunk);
  header.add(_asciiEncode('data'));
  header.add(_u32le(samples.length));
  header.add(samples);

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(header.takeBytes(), flush: true);
}

/// [audio] as the bytes to write for [format].
///
/// A wav run against a model that serves headerless samples is the one case where
/// the provider's bytes are not yet a file: they need a header saying what rate
/// and channel layout they have, or nothing will play them. Everything else — mp3
/// and natively-served wav — is already a finished container.
///
/// The rate comes from the response rather than from config. A response that
/// omits it is a hard error naming [modelId], since a header with an invented rate
/// plays at the wrong pitch, which is worse than no file.
///
/// Shared by narration and voice design so a generated voice clip obeys the same
/// rule as a narrated segment: a custom voice that will be handed to a cloning
/// model must be a playable file, not a headerless blob.
Uint8List asWavBytes({
  required TtsAudioFormat format,
  required TtsWavResponseFormat wavResponseFormat,
  required String modelId,
  required GeneratedAudio audio,
}) {
  final pcmSourced =
      format == TtsAudioFormat.wav && wavResponseFormat == TtsWavResponseFormat.pcm;
  if (!pcmSourced) return Uint8List.fromList(audio.bytes);

  final rate = audio.sampleRate;
  if (rate == null) {
    throw StateError(
      'Model "$modelId" returned raw samples without a sample '
      'rate, so a WAV header cannot be written. Set "wav_response_format" to '
      '"wav" if the provider serves WAV containers directly.',
    );
  }
  return Uint8List.fromList([
    ...wavHeader(
      sampleRate: rate,
      channels: audio.channels ?? 1,
      dataBytes: audio.bytes.length,
    ),
    ...audio.bytes,
  ]);
}

Uint8List _asciiEncode(String s) => Uint8List.fromList(s.codeUnits);

String _ascii(List<int> bytes) => String.fromCharCodes(bytes);

List<int> _u32le(int value) {
  final b = ByteData(4);
  b.setUint32(0, value, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u16le(int value) {
  final b = ByteData(2);
  b.setUint16(0, value, Endian.little);
  return b.buffer.asUint8List();
}
