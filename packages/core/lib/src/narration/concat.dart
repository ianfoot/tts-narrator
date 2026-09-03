import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'wav.dart';

/// Concatenates per-segment audio files into a single track written to
/// [outputPath]. Segments are joined in list order, so pass them in narration
/// (index) order.
///
/// - `format == 'pcm'`: each input must be a WAV; the PCM payload of its
///   `data` chunk is extracted and all payloads are written as one fresh WAV.
///   All segments share the profile sample rate, so the frame layout stays
///   valid and [sampleRate] drives the combined header.
/// - otherwise (MP3): files are appended byte-for-byte. Same-codec, same-
///   encoder MP3s splice cleanly; a brief silence may be audible at each
///   boundary since there is no re-encoding step.
///
/// Returns [outputPath]. Throws a [FileSystemException] when a segment is
/// missing or not the expected container.
String concatSegments(
  List<String> audioPaths, {
  required String outputPath,
  required String format,
  int sampleRate = 24000,
}) {
  if (audioPaths.isEmpty) {
    throw FileSystemException(
      'No segment audio files to concatenate.',
      outputPath,
    );
  }
  if (format == 'pcm') {
    final merged = BytesBuilder(copy: false);
    for (final path in audioPaths) {
      merged.add(_pcmPayload(_readSegment(path)));
    }
    writeWav(path: outputPath, bytes: merged, sampleRate: sampleRate);
  } else {
    final bytes = BytesBuilder(copy: false);
    for (final path in audioPaths) {
      bytes.add(_readSegment(path));
    }
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes.takeBytes(), flush: true);
  }
  return outputPath;
}

/// Whether [cleanupSegmentFiles] would do anything useful for [outDirPath]: a
/// manifest with a still-present combined file exists, segments have not been
/// deleted yet, and at least one per-segment audio file remains on disk.
bool segmentCleanupAvailable(String outDirPath) {
  final outDir = Directory(outDirPath);
  if (!outDir.existsSync()) return false;
  final manifest = _readManifest(outDir);
  if (manifest == null) return false;
  if (manifest['segments_deleted'] == true) return false;
  final combined = manifest['combined_file'];
  if (combined is! String || combined.isEmpty) return false;
  final combinedPath = '${outDir.path}${Platform.pathSeparator}$combined';
  if (!File(combinedPath).existsSync()) return false;
  final paragraphs = manifest['paragraphs'];
  if (paragraphs is! List) return false;
  return paragraphs.whereType<Map<String, dynamic>>().any((entry) {
    final wav = entry['wav'];
    return wav is String &&
        wav.isNotEmpty &&
        wav != combined &&
        File('${outDir.path}${Platform.pathSeparator}$wav').existsSync();
  });
}

/// Deletes the per-segment audio files listed in the `manifest.json` inside
/// [outDirPath], keeping the combined track and the manifest. The manifest is
/// flipped to `segments_deleted: true` so a repeat call is a no-op.
///
/// No-op (returns 0) when [outDirPath] has no cleanable run: missing manifest,
/// no combined file, or segments already deleted.
int cleanupSegmentFiles(String outDirPath) {
  final outDir = Directory(outDirPath);
  if (!outDir.existsSync()) return 0;
  final manifest = _readManifest(outDir);
  if (manifest == null) return 0;
  if (manifest['segments_deleted'] == true) return 0;
  final combined = manifest['combined_file'];
  if (combined is! String || combined.isEmpty) return 0;
  final combinedPath = '${outDir.path}${Platform.pathSeparator}$combined';
  if (!File(combinedPath).existsSync()) return 0;
  final paragraphs = manifest['paragraphs'];
  if (paragraphs is! List) return 0;
  var deleted = 0;
  for (final entry in paragraphs.whereType<Map<String, dynamic>>()) {
    final wav = entry['wav'];
    if (wav is! String || wav.isEmpty || wav == combined) continue;
    final file = File('${outDir.path}${Platform.pathSeparator}$wav');
    if (file.existsSync()) {
      file.deleteSync();
      deleted++;
    }
  }
  manifest['segments_deleted'] = true;
  final manifestFile = File(
    '${outDir.path}${Platform.pathSeparator}manifest.json',
  );
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  return deleted;
}

Map<String, dynamic>? _readManifest(Directory outDir) {
  final manifestFile = File(
    '${outDir.path}${Platform.pathSeparator}manifest.json',
  );
  if (!manifestFile.existsSync()) return null;
  try {
    final raw = jsonDecode(manifestFile.readAsStringSync());
    return raw is Map<String, dynamic> ? raw : null;
  } on Exception {
    // Unreadable/stale manifest is not fatal — treat as no cleanable run.
    return null;
  }
}

Uint8List _readSegment(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Segment audio is missing.', path);
  }
  return file.readAsBytesSync();
}

/// Extracts the PCM payload of the `data` chunk from a WAV file, validating
/// the RIFF/WAVE container so non-audio bytes are never spliced into the job.
Uint8List _pcmPayload(Uint8List wav) {
  if (wav.length < 12 ||
      _ascii(wav.sublist(0, 4)) != 'RIFF' ||
      _ascii(wav.sublist(8, 12)) != 'WAVE') {
    throw FileSystemException('Not a WAV file (bad header).');
  }
  final data = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = _ascii(wav.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + size;
    if (payloadEnd > wav.length) {
      throw FileSystemException('Not a WAV file (truncated chunk).');
    }
    if (id == 'data') {
      return Uint8List.sublistView(wav, payloadStart, payloadEnd);
    }
    offset = payloadEnd;
  }
  throw FileSystemException('Not a WAV file (no data chunk).');
}

String _ascii(List<int> bytes) => String.fromCharCodes(bytes);
