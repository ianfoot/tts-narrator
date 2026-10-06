import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'audio_format.dart';
import 'wav.dart';

/// Concatenates per-segment audio files into a single track written to
/// [outputPath]. Segments are joined in list order, so pass them in narration
/// (index) order.
///
/// - [TtsAudioFormat.wav]: each input must be a WAV; its `data` chunk is
///   extracted and all the samples are written as one fresh WAV. The combined
///   header is copied from the first segment, which is what makes this safe
///   without knowing the sample rate up front — every segment comes from one
///   run of one model, so they agree, and a mismatch is rejected rather than
///   silently producing a file whose header lies about its samples.
/// - [TtsAudioFormat.mp3]: files are appended byte-for-byte. Same-codec,
///   same-encoder MP3s splice cleanly; a brief silence may be audible at each
///   boundary since there is no re-encoding step.
///
/// Returns [outputPath]. Throws a [FileSystemException] when a segment is
/// missing, not the expected container, or does not match the first segment's
/// audio layout.
String concatSegments(
  List<String> audioPaths, {
  required String outputPath,
  required TtsAudioFormat format,
}) {
  if (audioPaths.isEmpty) {
    throw FileSystemException(
      'No segment audio files to concatenate.',
      outputPath,
    );
  }
  if (format == .wav) {
    final first = readWav(_readSegment(audioPaths.first));
    final merged = BytesBuilder(copy: false);
    for (final path in audioPaths) {
      // The first segment was already parsed to learn the layout.
      final segment = path == audioPaths.first
          ? first
          : readWav(_readSegment(path));
      if (!_sameFormatChunk(segment.formatChunk, first.formatChunk)) {
        throw FileSystemException(
          'Segment audio layout does not match the first segment.',
          path,
        );
      }
      merged.add(segment.data);
    }
    writeWav(path: outputPath, audio: merged, formatChunk: first.formatChunk);
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

/// Absolute path of the combined track recorded in the run's manifest inside
/// [outDirPath], or null when there is no manifest, no `combined_file` entry,
/// or the file is missing from disk. Lets callers surface/persist the finished
/// single track without re-deriving the `stem_full.ext` naming.
String? combinedFilePath(String outDirPath) {
  final outDir = Directory(outDirPath);
  if (!outDir.existsSync()) return null;
  final manifest = _readManifest(outDir);
  if (manifest == null) return null;
  final combined = manifest['combined_file'];
  if (combined is! String || combined.isEmpty) return null;
  final path = '${outDir.path}${Platform.pathSeparator}$combined';
  return File(path).existsSync() ? path : null;
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

/// Whether two `fmt ` chunks declare the same audio layout.
bool _sameFormatChunk(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
