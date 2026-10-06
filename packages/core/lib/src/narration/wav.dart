import 'dart:io';
import 'dart:typed_data';

/// A WAV file split into the two parts a concatenation needs: the `fmt ` chunk
/// describing the audio layout, and the `data` chunk holding the audio.
class WavFile {
  WavFile({required this.formatChunk, required this.data});

  /// The `fmt ` chunk exactly as the encoder wrote it, id and size included.
  ///
  /// Carried verbatim rather than decoded into sample rate and channel count
  /// because nothing downstream needs those numbers: a combined file just has
  /// to declare the same layout its samples actually have. Reusing the bytes
  /// means the app never has to know or guess the rate, and a chunk shape it
  /// does not model (a bit depth above 16, an extensible header) still
  /// round-trips intact.
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

Uint8List _asciiEncode(String s) => Uint8List.fromList(s.codeUnits);

String _ascii(List<int> bytes) => String.fromCharCodes(bytes);

List<int> _u32le(int value) {
  final b = ByteData(4);
  b.setUint32(0, value, Endian.little);
  return b.buffer.asUint8List();
}
