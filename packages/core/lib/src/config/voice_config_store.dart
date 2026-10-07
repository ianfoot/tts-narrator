import 'dart:convert';
import 'dart:io';

import 'voice_config.dart';
// Prefixed so the shared readers and writers read as the io layer's primitives
// rather than as this class's own methods of the same name.
import 'voice_config_io.dart' as io;

/// One row of a model's voice list, as an editor sees it.
  ///
  /// [key] is how the voice is filed in the model file and is what an edit
  /// addresses; it is always the voice's [id], whatever shape the file it was
  /// read from used. [label] is what the picker shows, which is the entry's
  /// `name` when it has one and the id otherwise; it is written back as a `name`,
  /// not as the key. The two differ only for a config authored the other way
  /// round -- a voice filed under its label -- and the next write re-files it
  /// under the id.
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
  /// names its default by label rather than by key still reports a key -- which
  /// is what a caller compares a row's key against. The key returned is always
  /// the voice's id.
  String? defaultVoiceKey(String alias) {
    final json = readModelJson(alias);
    if (json == null) return null;
    return _configuredDefaultKey(json, _rowsOf(json));
  }

  /// Adds or updates one voice of [alias] and rewrites the file.
  ///
  /// [key] addresses an existing voice to update -- it is that voice's id -- or is
  /// null to add a new one. [label] is the display label and is written as the
  /// entry's `name`; it may repeat, because the file is keyed by [id] rather than
  /// by label. [id] is what the provider is sent and cannot repeat within a
  /// model, because [voiceEntries] dedupes on it and a second row with the same
  /// id would silently vanish from the picker.
  ///
  /// An edit that changes [id] changes the key, and carries `default_voice`
  /// across, since that is a key into this same map and [defaultVoiceFor] throws
  /// when it stops resolving -- which would break selecting the model at all, not
  /// just the default.
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
    // A repeated label is allowed: the file is keyed by id, so two voices may be
    // called the same thing and still be two entries. A repeated id is not -- it
    // is what the map is keyed by, so the second would overwrite the first, and
    // [voiceEntries] would have dropped one from the picker anyway.
    for (final r in rows) {
      if (r.key == key) continue;
      if (r.id == newId) {
        return VoiceEdit.rejected(
          'That id is already used by "${r.label}"; two voices cannot share '
          'one id.',
        );
      }
    }

    final existing = key == null ? null : byKey[key];
    final updated = EditableVoice(
      key: existing?.key ?? newId,
      label: newLabel,
      id: newId,
      // An explicit gender and language survive an edit that never mentions
      // them: dropping either would re-tag a voice the file describes as
      // untagged, and a Fish UUID carries its language nowhere else. A new
      // value replaces the old.
      gender: gender ?? existing?.gender,
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
      defaultId: _carriedDefaultId(json, rows, key, newId),
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
    ], defaultId: _carriedDefaultId(json, rows, null, null));
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
    return _writeVoices(alias, json, rows, defaultId: target.id);
  }

  /// The id the model's `default_voice` should carry forward as, given that the
  /// voice filed under [renamedFrom] is becoming [renamedTo] -- or that neither
  /// is null when nothing is being renamed.
  ///
  /// `default_voice` is a key into the same map being rewritten, and
  /// [defaultVoiceFor] throws when it stops resolving, so a rename has to bring
  /// it along or the model becomes unselectable. The value written is the id
  /// because that is what the rewritten map is keyed by.
  ///
  /// Null means the file's `default_voice` should be left as it stands -- either
  /// there is none, or it names something no row matches and the write has no
  /// opinion about it. See [_writeVoices].
  String? _carriedDefaultId(
    Map<String, dynamic> json,
    List<EditableVoice> rows,
    String? renamedFrom,
    String? renamedTo,
  ) {
    final key = _configuredDefaultKey(json, rows);
    if (key == null) return null;
    if (renamedFrom != null && key == renamedFrom) return renamedTo;
    return rows.firstWhere((r) => r.key == key).id;
  }

  /// Replaces the voice list of [alias] and writes the file.
  ///
  /// The list is normalised to the one shape the app writes -- every voice
  /// keyed by its id, the label in a `name` when it differs -- so a file the
  /// user hand-edited and one the app wrote read the same way after a save.
  /// [defaultId], when given, becomes the `default_voice` value.
  ///
  /// A `default_voice` this call does not set is carried through verbatim rather
  /// than dropped, including one that matches no row -- see below.
  ///
  /// Everything else in [json] is left exactly as it was found, including keys
  /// this schema does not define: the file is the user's to hold vendor quirks
  /// in, and a voice edit should not be the thing that drops them.
  ///
  /// Nothing is refused here. Keying by id is what makes an edit safe to write
  /// unconditionally: the id is unique, so two voices can never collapse into
  /// one entry no matter what they are called. Kokoro ships three "Santa"s and
  /// the README tells users to copy that model into their layer, so a repeated
  /// name is reachable on a shipped file, not a malformed one.
  VoiceEdit _writeVoices(
    String alias,
    Map<String, dynamic> json,
    List<EditableVoice> rows, {
    String? defaultId,
  }) {
    json['voices'] = {
      for (final r in rows)
        r.id: io.voiceEntryJson(
          r.id,
          Voice(
            id: r.id,
            // A label that repeats the id would be noise, and the reader takes
            // the id for the label when there is no `name` anyway.
            name: r.label == r.id ? null : r.label,
            gender: r.gender,
            language: r.language,
          ),
        ),
    };
    // Only ever set, never cleared. A null [defaultId] means "this call has
    // no opinion", not "there is no default": it covers both a file that
    // configures none and a `default_voice` naming something no row matches --
    // an id that is not in `voices`, which [VoiceConfig.resolveVoice] still
    // honours by falling back to the raw string, and which the Fish config's own
    // README documents. Removing it in either case would let an edit to an
    // unrelated voice un-default the model, after which [defaultVoiceFor] throws
    // and the model cannot be selected at all.
    if (defaultId != null) json['default_voice'] = defaultId;

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

  /// The `voices` block of [json] as editable rows, in file order.
  ///
  /// Every row is keyed by its voice id, whatever shape the file used: an
  /// entry filed under a name reads that name as the label and hands the id to
  /// [EditableVoice.key], so the next write re-files it under the id. That is
  /// the one shape the app writes (see [_writeVoices]) and the one that makes a
  /// name safe to repeat, which is why an id — not a name — is the key.
  ///
  /// Entries the loader would reject are left out, matching what the app can
  /// actually use; [loadVoiceConfig] reports them as warnings.
  List<EditableVoice> _rowsOf(Map<String, dynamic> json) {
    // Both shapes the loader accepts are read here, so a model whose voices
    // arrived as a bare id list is as editable as one keyed by id: returning
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
          key: voice.id,
          // A name the entry states outright wins. Failing that, a file key that
          // differs from the id was a label — that is how the name-keyed shape
          // keeps its names through the re-file. Otherwise there is no label but
          // the id, and the picker shows the id.
          label: voice.name ?? (key == voice.id ? voice.id : key),
          id: voice.id,
          gender: voice.gender,
          language: voice.language,
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
