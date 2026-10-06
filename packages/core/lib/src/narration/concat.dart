import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'audio_format.dart';
import 'manifest.dart';
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
  final manifest = readManifest(outDir);
  if (manifest == null) return null;
  final combined = manifest['combined_file'];
  if (combined is! String || combined.isEmpty) return null;
  final path = resolveInManifestDir(outDir, combined);
  return File(path).existsSync() ? path : null;
}

/// What [cleanupSegmentFiles] needs to act, gathered by one pass over the
/// guards its predicate and its action would otherwise each repeat.
class _CleanableRun {
  _CleanableRun(this.outDir, this.manifest, this.combined, this.paragraphs);

  final Directory outDir;

  /// The whole document, because cleanup writes the flag back and must not
  /// drop the keys it did not read.
  final Map<String, dynamic> manifest;

  /// The `combined_file` name, kept for the same reason cleanup must not
  /// delete the track it is keeping.
  final String combined;
  final List<Map<String, dynamic>> paragraphs;
}

/// The run in [outDir] that [cleanupSegmentFiles] could clean, or null when
/// there is nothing to do: no directory, no readable manifest, segments
/// already deleted, no combined track on disk, or no paragraph records.
///
/// Both the predicate and the action ask this, so the two cannot drift into
/// disagreeing about what "already cleaned" means.
_CleanableRun? _cleanableRun(String outDirPath) {
  final outDir = Directory(outDirPath);
  if (!outDir.existsSync()) return null;
  final manifest = readManifest(outDir);
  if (manifest == null) return null;
  if (manifest['segments_deleted'] == true) return null;
  final combined = manifest['combined_file'];
  if (combined is! String || combined.isEmpty) return null;
  if (!File(resolveInManifestDir(outDir, combined)).existsSync()) return null;
  final paragraphs = manifest['paragraphs'];
  if (paragraphs is! List) return null;
  return _CleanableRun(
    outDir,
    manifest,
    combined,
    paragraphs.whereType<Map<String, dynamic>>().toList(),
  );
}

/// Whether [cleanupSegmentFiles] would do anything useful for [outDirPath]: a
/// manifest with a still-present combined file exists, segments have not been
/// deleted yet, and at least one per-segment audio file remains on disk.
bool segmentCleanupAvailable(String outDirPath) {
  final run = _cleanableRun(outDirPath);
  if (run == null) return false;
  return run.paragraphs.any((entry) {
    final wav = entry['wav'];
    return wav is String &&
        wav.isNotEmpty &&
        wav != run.combined &&
        File(resolveInManifestDir(run.outDir, wav)).existsSync();
  });
}

/// Deletes the per-segment audio files listed in the `manifest.json` inside
/// [outDirPath], keeping the combined track and the manifest. The manifest is
/// flipped to `segments_deleted: true` so a repeat call is a no-op.
///
/// No-op (returns 0) when [outDirPath] has no cleanable run: missing manifest,
/// no combined file, or segments already deleted.
int cleanupSegmentFiles(String outDirPath) {
  final run = _cleanableRun(outDirPath);
  if (run == null) return 0;
  var deleted = 0;
  for (final entry in run.paragraphs) {
    final wav = entry['wav'];
    if (wav is! String || wav.isEmpty || wav == run.combined) continue;
    final file = File(resolveInManifestDir(run.outDir, wav));
    if (file.existsSync()) {
      file.deleteSync();
      deleted++;
    }
  }
  run.manifest['segments_deleted'] = true;
  writeManifest(run.outDir, run.manifest);
  return deleted;
}

Uint8List _readSegment(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Segment audio is missing.', path);
  }
  return file.readAsBytesSync();
}

/// Whether two `fmt ` chunks declare the same audio layout.
///
/// The counterpart to [WavFile.formatChunk]: a concatenation can copy the first
/// segment's chunk into the combined header only if every other segment's
/// samples genuinely belong to that layout, and the bytes themselves are what
/// say so. Comparing them rather than decoding into fields is what lets an
/// unmodelled chunk shape (a bit depth above 16, an extensible header) still be
/// checked for equality.
///
/// Private to concatenation because concatenation is the only thing that has to
/// answer it. [Uint8List] is a view onto bytes, so two chunks holding identical
/// bytes are still different objects and `==` would compare identity; the
/// element-wise equality is the whole point.
bool _sameFormatChunk(Uint8List a, Uint8List b) =>
    const ListEquality<int>().equals(a, b);
