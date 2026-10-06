import 'dart:typed_data';

/// Builds a complete WAV file's bytes for [pcm] at [sampleRate].
///
/// Core no longer synthesises audio, so tests need a *provider* that emits a
/// real container rather than a header helper that wraps raw samples. This
/// stands in for that: it mirrors the canonical 44-byte layout (16-byte PCM
/// `fmt ` chunk) that a streaming TTS server sends.
Uint8List wavFileBytes(List<int> pcm, {int sampleRate = 24000}) {
  final bytes = BytesBuilder(copy: false);
  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => bytes.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );

  final byteRate = sampleRate * 2;
  ascii('RIFF');
  u32(36 + pcm.length);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(byteRate);
  u16(2); // block align
  u16(16); // bits per sample
  ascii('data');
  u32(pcm.length);
  bytes.add(pcm);
  return bytes.takeBytes();
}
