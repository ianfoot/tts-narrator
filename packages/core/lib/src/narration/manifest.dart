import 'dart:convert';
import 'dart:io';

/// The run manifest: the one record of what a narration run produced, shared by
/// the run loop that writes it, the resume path that reads it back, and the
/// segment-retention policy that flips `segments_deleted` on it.
///
/// This module owns the filename, the path arithmetic, and the policy that an
/// unreadable or stale manifest means "no run here".
///
/// Keys are read and written as raw JSON rather than through a class: the
/// manifest is a compatibility surface that files from earlier versions are still
/// resumed from, so a reader that silently defaulted a missing key would hide the
/// difference between "written by an older version" and "corrupt".

/// Name of the manifest file inside a run directory.
const manifestFileName = 'manifest.json';

/// The manifest of the run in [outDir], or null when there is none.
///
/// A missing file, unreadable file, non-JSON file, and JSON that is not an object
/// all read as null: every caller wants "is there usable state here", and none can
/// act on a partially-understood manifest.
Map<String, dynamic>? readManifest(Directory outDir) {
  final file = File(_manifestPathIn(outDir));
  if (!file.existsSync()) return null;
  try {
    final raw = jsonDecode(file.readAsStringSync());
    return raw is Map<String, dynamic> ? raw : null;
  } on Exception {
    // Not fatal: resume re-narrates and cleanup treats the run as uncleanable.
    return null;
  }
}

/// Writes [manifest] into [outDir], pretty-printed with two-space indent so a
/// hand-inspected manifest stays readable and a hand-edited one stays diffable.
void writeManifest(Directory outDir, Map<String, dynamic> manifest) {
  File(_manifestPathIn(outDir))
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}

/// The per-paragraph records of the run in [outDir], or empty when there is no
/// usable manifest.
///
/// One entry per paragraph, in narration order. A manifest whose `paragraphs` is
/// absent or not a list reads as no records, so a manifest written before
/// paragraphs were recorded behaves like a fresh run.
List<Map<String, Object?>> paragraphRecords(Directory outDir) {
  final paragraphs = readManifest(outDir)?['paragraphs'];
  if (paragraphs is! List) return const [];
  return paragraphs
      .whereType<Map<String, dynamic>>()
      .cast<Map<String, Object?>>()
      .toList();
}

/// Resolves a filename recorded in the manifest against [outDir].
String resolveInManifestDir(Directory outDir, String name) =>
    '${outDir.path}${Platform.pathSeparator}$name';

String _manifestPathIn(Directory outDir) =>
    resolveInManifestDir(outDir, manifestFileName);
