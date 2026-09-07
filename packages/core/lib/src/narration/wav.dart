import 'dart:io';
import 'dart:typed_data';

/// Wraps raw PCM audio (16-bit little-endian) into a WAV file.
///
/// Gemini TTS output is 24 kHz mono 16-bit LE, matching our defaults.
void writeWav({
  required String path,
  required BytesBuilder bytes,
  int sampleRate = 24000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final pcm = bytes.takeBytes();
  final dataSize = pcm.length;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);

  final header = BytesBuilder(copy: false);
  header.add(asciiEncode('RIFF'));
  header.add(_u32le(36 + dataSize));
  header.add(asciiEncode('WAVE'));
  header.add(asciiEncode('fmt '));
  header.add(_u32le(16)); // fmt chunk size
  header.add(_u16le(1)); // PCM
  header.add(_u16le(channels));
  header.add(_u32le(sampleRate));
  header.add(_u32le(byteRate));
  header.add(_u16le(blockAlign));
  header.add(_u16le(bitsPerSample));
  header.add(asciiEncode('data'));
  header.add(_u32le(dataSize));
  header.add(pcm);

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(header.takeBytes(), flush: true);
}

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

Uint8List asciiEncode(String s) => Uint8List.fromList(s.codeUnits);
