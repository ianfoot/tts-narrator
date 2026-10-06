import 'dart:convert';
import 'dart:io';

import 'voice_config.dart';
// Prefixed so the shared readers and writers read as the io layer's primitives
// rather than as this class's own methods of the same name.
import 'voice_config_io.dart' as io;

/// One row of a model's voice list, as an editor sees it.
///
/// [key] is how the voice is filed in the model file and is what an edit
/// addresses; [label] is what the picker shows, which is the entry's `name` when
/// it has one and the key otherwise. The two differ only for a config authored
/// the other way round, and [label] is what the app writes back as the key.
class EditableVoice {
  const EditableVoice({
    required this.key,
    required this.label,
    required this.id,
    this.gender,
    this.language,
  });

  final String key;
  final String label;
  final String id;
  final VoiceGender? gender;

  /// Language code this voice speaks, when the entry tags it explicitly.
  ///
  /// Null to fall back to reading the code off the id. Only meaningful for a
  /// model that declares languages; a voice with no tag and no id prefix is
  /// simply untagged.
  final String? language;
}

/// The outcome of an edit: whether the file was written, and why not if it
/// wasn't.
///
/// A refusal is the normal answer to a bad edit rather than a thrown error: the
/// user is mid-edit in a table, and the reason belongs next to the field.
class VoiceEdit {
  const VoiceEdit.written() : changed = true, error = null;

  const VoiceEdit.rejected(this.error) : changed = false;

  final bool changed;
  final String? error;

  bool get ok => changed;
}

/// Reads and writes the user's *voice* edits to a config directory.
///
/// This is the app's only writer. The shipped layer in `config.json`,
/// `providers/` and `models/` is downloaded and left alone; every write lands in
/// [overlayDir], whose files shadow their counterparts (see
/// [loadVoiceConfig]). So an edit here can never be lost to a re-download, and
/// [revertModel] is always available because the original is still on disk.
///
/// Only voices are writable for now. Provider files, the registry and a model's
/// own metadata are readable but not editable, and adding a model or a provider
/// is still a matter of editing files by hand.
class VoiceConfigStore {
  const VoiceConfigStore(this.configDir);

  final String configDir;

  /// The directory holding the user's layer.
  String get overlayDir =>
      '$configDir${Platform.pathSeparator}${io.kVoiceConfigOverlayDirName}';

  /// Where a model file for [alias] lives, in the user's layer or the shipped
  /// one.
  File modelFile(String alias, {bool overlay = false}) {
    final root = overlay
        ? '$overlayDir${Platform.pathSeparator}'
        : '$configDir${Platform.pathSeparator}';
    return File('$root${io.kVoiceConfigModelsDir}/$alias.json');
  }

  /// Whether [alias] has a user file shadowing the downloaded one.
  bool hasOverlayModel(String alias) =>
      modelFile(alias, overlay: true).existsSync();

  /// The effective model file for [alias], the user's if there is one.
  ///
  /// Throws [VoiceConfigurationError] when the file is not a JSON object;
  /// returns null when no layer holds the model.
  Map<String, dynamic>? readModelJson(String alias) =>
      io.readModelJson(configDir, alias);

  /// The downloaded model file for [alias], ignoring the user's layer.
  Map<String, dynamic>? readDownloadedModelJson(String alias) {
    final file = modelFile(alias);
    if (!file.existsSync()) return null;
    final raw = _decode(file);
    if (raw is! Map<String, dynamic>) {
      throw VoiceConfigurationError(
        'Invalid voice config "${file.path}": top-level value must be a '
        'JSON object',
      );
    }
    return raw;
  }

  /// Writes [json] as the user's model file for [alias], replacing any previous
  /// one, and returns the path written.
  ///
  /// The write is atomic: the bytes go to a sibling temp file that is then
  /// renamed over the target, so a crash or a full disk leaves the previous file
  /// intact rather than a half-written one. The whole file is replaced, because
  /// the user's layer shadows the shipped one file-for-file.
  String writeModelJson(String alias, Map<String, dynamic> json) {
    final file = modelFile(alias, overlay: true);
    final temp = File('${file.path}.tmp');
    try {
      file.parent.createSync(recursive: true);
      temp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
      // A rename replaces an existing target in one step, so the previous file
      // stays intact right up to the moment the new one takes its place. That
      // holds on Windows too: dart:io documents that an existing file at the
      // destination "is removed first", and removes it as part of the same call
      // rather than refusing the rename.
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } on FileSystemException {
          // Leaving a stray temp file behind is better than masking the cause.
        }
      }
      throw VoiceConfigurationError(
        'Cannot write voice config "${file.path}": $e',
      );
    }
    return file.path;
  }

  /// Deletes the user's file for [alias], so the downloaded one shows through
  /// again. Returns whether there was one to delete.
  bool revertModel(String alias) {
    final file = modelFile(alias, overlay: true);
    if (!file.existsSync()) return false;
    try {
      file.deleteSync();
    } on FileSystemException catch (e) {
      throw VoiceConfigurationError('Cannot delete "${file.path}": $e');
    }
    return true;
  }

  /// The voices of [alias] as editable rows, in file order.
  List<EditableVoice> voicesFor(String alias) {
    final json = readModelJson(alias);
    return json == null ? const [] : _rowsOf(json);
  }

  /// The file key of [alias]'s default voice, or null when it configures none.
  ///
  /// Resolved through the same key-then-label scan as a write, so a config that
  /// names its default by label rather than by key still reports a key — which
  /// is what a caller compares a row's key against.
  String? defaultVoiceKey(String alias) {
    final json = readModelJson(alias);
    if (json == null) return null;
    return _configuredDefaultKey(json, _rowsOf(json));
  }

  /// Adds or updates one voice of [alias] and rewrites the file.
  ///
  /// [key] addresses an existing voice to update, or is null to add a new one.
  /// [label] is the display label and becomes the file key; [id] is what the
  /// provider is sent and cannot repeat within a model, because
  /// [voiceEntries] dedupes on it and a second row with the same id would
  /// silently vanish from the picker.
  ///
  /// A rename carries `default_voice` across, since that is a key into this same
  /// map and [defaultVoiceFor] throws when it stops resolving -- which would
  /// break selecting the model at all, not just the default.
  VoiceEdit saveVoice(
    String alias, {
    String? key,
    required String label,
    required String id,
    VoiceGender? gender,
    String? language,
  }) {
    final newLabel = label.trim();
    final newId = id.trim();
    if (newLabel.isEmpty) {
      return const VoiceEdit.rejected('A voice needs a label.');
    }
    if (newId.isEmpty) {
      return const VoiceEdit.rejected('A voice needs an id.');
    }

    final json = readModelJson(alias);
    if (json == null) {
      return VoiceEdit.rejected('There is no config file for "$alias".');
    }
    final rows = _rowsOf(json);
    final byKey = {for (final r in rows) r.key: r};

    if (key != null && !byKey.containsKey(key)) {
      return VoiceEdit.rejected('That voice is no longer in "$alias".');
    }
    for (final r in rows) {
      if (r.key == key) continue;
      if (r.label == newLabel) {
        return VoiceEdit.rejected('"$newLabel" is already a voice here.');
      }
      if (r.id == newId) {
        return VoiceEdit.rejected(
          'That id is already used by "${r.label}"; two voices cannot share '
          'one id.',
        );
      }
    }

    final existing = key == null ? null : byKey[key];
    final updated = EditableVoice(
      key: existing?.key ?? newLabel,
      label: newLabel,
      id: newId,
      gender: gender,
      // An explicit language survives an edit that never mentions one: dropping
      // it would re-tag a UUID voice as untagged and lose its language. A new
      // language replaces the old.
      language: language ?? existing?.language,
    );

    final next = [
      for (final r in rows)
        if (r.key == key) updated else r,
    ];
    if (existing == null) next.add(updated);
    return _writeVoices(
      alias,
      json,
      next,
      defaultLabel: _carriedDefaultLabel(json, rows, key, newLabel),
    );
  }

  /// Removes the voice filed under [key] from [alias].
  ///
  /// Refuses to remove the default voice: clearing `default_voice` makes
  /// [defaultVoiceFor] throw, so the model could no longer be selected at all.
  /// The user has to point the default somewhere else first.
  VoiceEdit removeVoice(String alias, String key) {
    final json = readModelJson(alias);
    if (json == null) {
      return VoiceEdit.rejected('There is no config file for "$alias".');
    }
    final rows = _rowsOf(json);
    final target = rows.where((r) => r.key == key).firstOrNull;
    if (target == null) {
      return VoiceEdit.rejected('That voice is no longer in "$alias".');
    }
    if (_configuredDefaultKey(json, rows) == key) {
      return VoiceEdit.rejected(
        '"${target.label}" is the default voice. Choose another default '
        'before removing it.',
      );
    }
    return _writeVoices(alias, json, [
      for (final r in rows)
        if (r.key != key) r,
    ], defaultLabel: _carriedDefaultLabel(json, rows, null, null));
  }

  /// Makes the voice filed under [key] the default for [alias].
  VoiceEdit setDefaultVoice(String alias, String key) {
    final json = readModelJson(alias);
    if (json == null) {
      return VoiceEdit.rejected('There is no config file for "$alias".');
    }
    final rows = _rowsOf(json);
    final target = rows.where((r) => r.key == key).firstOrNull;
    if (target == null) {
      return VoiceEdit.rejected('That voice is no longer in "$alias".');
    }
    return _writeVoices(alias, json, rows, defaultLabel: target.label);
  }

  /// The label the model's `default_voice` should carry forward as, given that
  /// the voice filed under [renamedFrom] is becoming [renamedTo] -- or that
  /// neither is null when nothing is being renamed.
  ///
  /// `default_voice` is a key into the same map being rewritten, and
  /// [defaultVoiceFor] throws when it stops resolving, so a rename has to bring
  /// it along or the model becomes unselectable.
  ///
  /// Null means the file's `default_voice` should be left as it stands -- either
  /// there is none, or it names something no row matches and the write has no
  /// opinion about it. See [_writeVoices].
  String? _carriedDefaultLabel(
    Map<String, dynamic> json,
    List<EditableVoice> rows,
    String? renamedFrom,
    String? renamedTo,
  ) {
    final key = _configuredDefaultKey(json, rows);
    if (key == null) return null;
    if (renamedFrom != null && key == renamedFrom) return renamedTo;
    return rows.firstWhere((r) => r.key == key).label;
  }

  /// Replaces the voice list of [alias] and writes the file.
  ///
  /// The list is normalised to the one shape the app writes -- key is the label,
  /// id always explicit, no `name` -- so a file the user hand-edited and one the
  /// app wrote read the same way after a save. [defaultLabel], when given,
  /// becomes the `default_voice` value.
  ///
  /// A `default_voice` this call does not set is carried through verbatim rather
  /// than dropped, including one that matches no row -- see below.
  ///
  /// Everything else in [json] is left exactly as it was found, including keys
  /// this schema does not define: the file is the user's to hold vendor quirks
  /// in, and a voice edit should not be the thing that drops them.
  ///
  /// Refused, rather than written, when two rows share a label -- see below.
  VoiceEdit _writeVoices(
    String alias,
    Map<String, dynamic> json,
    List<EditableVoice> rows, {
    String? defaultLabel,
  }) {
    // The key a voice is filed under becomes its label here, so two rows with
    // one label would collapse into a single entry -- dropping a voice from the
    // file because of an edit that did not mention it. Kokoro ships three
    // "Santa"s and the README tells users to copy that model into their layer,
    // so this is reachable on a shipped file, not a malformed one. Refuse
    // instead: the user can rename one, which they can see and reason about.
    final collision = _duplicateLabel(rows);
    if (collision != null) {
      return VoiceEdit.rejected(
        '"$alias" has more than one voice labelled "$collision"; rename one of '
        'them before saving, because both cannot be filed under that label.',
      );
    }

    json['voices'] = {
      for (final r in rows)
        r.label: io.canonicalVoiceEntryJson(
          Voice(id: r.id, gender: r.gender, language: r.language),
        ),
    };
    // Only ever set, never cleared. A null [defaultLabel] means "this call has
    // no opinion", not "there is no default": it covers both a file that
    // configures none and a `default_voice` naming something no row matches --
    // an id that is not in `voices`, which [VoiceConfig.resolveVoice] still
    // honours by falling back to the raw string, and which the Fish config's own
    // README documents. Removing it in either case would let an edit to an
    // unrelated voice un-default the model, after which [defaultVoiceFor] throws
    // and the model cannot be selected at all.
    if (defaultLabel != null) json['default_voice'] = defaultLabel;

    writeModelJson(alias, json);
    return const VoiceEdit.written();
  }

  /// The key `default_voice` currently points at, resolving the label a
  /// name-keyed entry is filed under, or null when it points at nothing in the
  /// list.
  ///
  /// [VoiceConfig.resolveVoice] resolves a key first, then names, then the bare
  /// id, so a config may legitimately name any of the three; once the list is
  /// normalised the names are gone, so this has to be resolved before the write,
  /// not after.
  ///
  /// Matching the id as well as the key and label is what stops an unrelated
  /// edit from deleting a `default_voice` the loader still honours, which
  /// un-defaults the model and makes [defaultVoiceFor] throw. A null from here
  /// means the value names nothing at all -- a caller must then leave the file's
  /// own `default_voice` alone rather than treat the model as having none.
  String? _configuredDefaultKey(
    Map<String, dynamic> json,
    List<EditableVoice> rows,
  ) {
    final raw = json['default_voice'];
    if (raw is! String || raw.trim().isEmpty) return null;
    final value = raw.trim();
    for (final r in rows) {
      if (r.key == value || r.label == value) return r.key;
    }
    for (final r in rows) {
      if (r.id == value) return r.key;
    }
    return null;
  }

  /// The first label used by more than one of [rows], or null if each is unique.
  String? _duplicateLabel(List<EditableVoice> rows) {
    final seen = <String>{};
    for (final r in rows) {
      if (!seen.add(r.label)) return r.label;
    }
    return null;
  }

  /// The `voices` block of [json] as editable rows, in file order.
  ///
  /// Entries the loader would reject are left out, matching what the app can
  /// actually use; [loadVoiceConfig] reports them as warnings.
  List<EditableVoice> _rowsOf(Map<String, dynamic> json) {
    // Both shapes the loader accepts are read here, so a model whose voices
    // arrived as a bare id list is as editable as one keyed by label: returning
    // an empty list for the list form would show the user no voices at all
    // rather than the ones their model file declares.
    final raw = json['voices'];
    final entries = switch (raw) {
      final Map<String, dynamic> map => map.entries.map(
        (e) => (e.key, e.value),
      ),
      final List<Object?> list => list.map((id) => ('$id', id)),
      _ => const <(String, Object?)>[],
    };
    final rows = <EditableVoice>[];
    for (final (key, value) in entries) {
      final voice = io.voiceFromEntry(key, value).voice;
      if (voice == null) continue;
      rows.add(
        EditableVoice(
          key: key,
          label: voice.name ?? key,
          id: voice.id,
          gender: voice.gender,
        ),
      );
    }
    return rows;
  }

  Object? _decode(File file) {
    try {
      return jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw VoiceConfigurationError(
        'Invalid voice config "${file.path}": ${e.message}',
      );
    } on IOException catch (e) {
      throw VoiceConfigurationError(
        'Cannot read voice config "${file.path}": $e',
      );
    }
  }
}
