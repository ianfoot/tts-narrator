import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../config/voice_config_io.dart';
import 'custom_voice.dart';

/// The outcome of writing a custom voice file.
///
/// A refusal is a value rather than a throw, for the same reason [VoiceEdit] is
/// one: the user is mid-edit in a dialog and the reason belongs next to the
/// field, not in a stack trace they never see.
class CustomVoiceEdit {
  const CustomVoiceEdit._({this.voice, this.error});

  /// The save that landed, or null when the edit was refused.
  final CustomVoice? voice;

  /// Why the edit was refused, or null when it landed.
  final String? error;

  const CustomVoiceEdit.written(CustomVoice voice) : this._(voice: voice);

  const CustomVoiceEdit.rejected(String error) : this._(error: error);

  bool get ok => error == null;
  bool get changed => ok;
}

/// A clip the user is auditioning, before they have decided to keep it.
///
/// Deliberately not persisted: a design model is stochastic, so most
/// generations get thrown away, and writing those to disk would leave a litter
/// of wav files for the user to clean up by hand.
class VoiceDraft {
  const VoiceDraft({
    required this.bytes,
    required this.modelAlias,
    required this.instruct,
    required this.transcript,
    required this.attempts,
    this.language,
  });

  /// The generated clip, in memory. Held as bytes rather than a path so that
  /// discarding it costs nothing and leaves nothing behind.
  final Uint8List bytes;

  /// Alias of the model that produced this clip, so "new variation" can replay
  /// the same design under the same engine.
  final String modelAlias;

  /// The prose this clip was generated from. Shown on the draft card, because
  /// the design panel stays editable while a draft is on screen and the two can
  /// easily drift apart.
  final String instruct;

  /// The passage the clip was read from. Travels with it on save, since a
  /// cloning model adopting the clip needs those words.
  final String transcript;

  /// How many generations produced this line of design. Rises on every
  /// "generate again" and resets when the prose changes.
  final int attempts;

  final String? language;

  VoiceDraft withAttempts(int next) => VoiceDraft(
        bytes: bytes,
        modelAlias: modelAlias,
        instruct: instruct,
        transcript: transcript,
        attempts: next,
        language: language,
      );
}

/// The saved custom voices under one config directory, and the wav clips they
/// name.
///
/// A sibling of `VoiceConfigStore` rather than a branch of it: this one has no
/// per-platform placement to mirror, because its files are not model files and
/// the config loader never walks `user/voices/`. A saved voice is therefore
/// invisible to model loading, which is what keeps the
/// `sends_voice: false => zero voices` invariant intact.
///
/// Layout under the config directory:
///
/// ```
/// user/voices/voices.json     the registry
/// user/voices/<id>.wav        one clip per entry
/// ```
class CustomVoiceStore {
  const CustomVoiceStore(this.configDir);

  /// Root of the downloaded configuration; the user's layer is beneath it.
  final String configDir;

  /// Where saved voices live, inside the user's layer alongside hand-written
  /// model overrides.
  String get voicesDir =>
      '$configDir${Platform.pathSeparator}$kVoiceConfigOverlayDirName'
      '${Platform.pathSeparator}voices';

  /// The registry file. Clip audio is the payload; this is the index.
  File get registryFile => File('$voicesDir${Platform.pathSeparator}voices.json');

  /// The clip for [id].
  File wavFile(String id) =>
      File('$voicesDir${Platform.pathSeparator}$id.wav');

  /// Every saved voice, in file order.
  ///
  /// A missing registry is an empty library -- the ordinary case before the
  /// first design is saved -- and an unreadable or malformed one is also empty
  /// rather than an exception. The voice library is an accessory to narration:
  /// a corrupt file in it should cost the user their saved voices, not their
  /// ability to run a narration.
  CustomVoiceLibrary read() {
    final file = registryFile;
    if (!file.existsSync()) return CustomVoiceLibrary.empty;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return CustomVoiceLibrary.empty;
    }
    if (decoded is! Map<String, dynamic>) return CustomVoiceLibrary.empty;
    final raw = decoded['voices'];
    if (raw is! List) return CustomVoiceLibrary.empty;

    final voices = <CustomVoice>[];
    for (final entry in raw) {
      final voice = _voiceFromJson(entry);
      if (voice != null) voices.add(voice);
    }
    return CustomVoiceLibrary(voices: voices);
  }

  /// Saves [bytes] as a new voice called [name] and adds it to the registry.
  ///
  /// The id is allocated rather than supplied: it has to be a valid filename
  /// stem on every platform, it has to be unique, and it has to stay put across
  /// a rename, so none of that is the caller's problem. [name] is free text
  /// and may repeat.
  ///
  /// [bytes] is written before the registry is touched, so a write failure
  /// leaves no row pointing at a clip that does not exist. The reverse gap --
  /// a clip on disk with no row -- is harmless and is cleaned up by the next
  /// successful save of the same name.
  CustomVoiceEdit add({
    required String name,
    required Uint8List bytes,
    required String modelAlias,
    required String instruct,
    required String transcript,
    String? language,
    DateTime? createdAt,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const CustomVoiceEdit.rejected('A voice needs a name.');
    }

    final json = _readRegistryJson();
    final library = CustomVoiceLibrary(voices: _voicesFrom(json));
    final id = _allocateId(trimmed, library.voices.map((v) => v.id.value));
    final voice = CustomVoice(
      id: CustomVoiceId(id),
      name: CustomVoiceName(trimmed),
      designModel: modelAlias,
      instruct: instruct,
      language: language,
      transcript: transcript,
      createdAt: createdAt ?? DateTime.now(),
    );

    try {
      final wav = wavFile(id);
      wav.parent.createSync(recursive: true);
      wav.writeAsBytesSync(bytes, flush: true);
    } on FileSystemException catch (e) {
      return CustomVoiceEdit.rejected('Cannot save the voice clip: $e');
    }

    return _writeRegistry(json, [...library.voices, voice], affected: voice);
  }

  /// Renames the voice filed under [id].
  ///
  /// Touches nothing but the label. The clip is not rewritten and the id does
  /// not move, so a run already configured against this voice keeps working
  /// across the rename.
  CustomVoiceEdit rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const CustomVoiceEdit.rejected('A voice needs a name.');
    }

    final json = _readRegistryJson();
    final voices = _voicesFrom(json);
    final existing = voices.where((v) => v.id.value == id).firstOrNull;
    if (existing == null) {
      return CustomVoiceEdit.rejected('That voice is no longer in the library.');
    }
    final renamed = CustomVoice(
      id: existing.id,
      name: CustomVoiceName(trimmed),
      designModel: existing.designModel,
      instruct: existing.instruct,
      language: existing.language,
      transcript: existing.transcript,
      createdAt: existing.createdAt,
    );
    return _writeRegistry(json, [
      for (final voice in voices)
        if (voice.id.value == id) renamed else voice,
    ], affected: renamed);
  }

  /// Removes the voice filed under [id], along with its clip.
  ///
  /// A missing clip is not an error: the registry is the authority on what
  /// exists, and a clip deleted behind the app's back has already left the row
  /// as close to correct as it can get.
  CustomVoiceEdit remove(String id) {
    final json = _readRegistryJson();
    final voices = _voicesFrom(json);
    final existing = voices.where((v) => v.id.value == id).firstOrNull;
    if (existing == null) {
      return const CustomVoiceEdit.rejected('That voice is no longer in the library.');
    }

    try {
      final wav = wavFile(id);
      if (wav.existsSync()) wav.deleteSync();
    } on FileSystemException catch (e) {
      return CustomVoiceEdit.rejected('Cannot delete the voice clip: $e');
    }
    return _writeRegistry(json, [
      for (final voice in voices)
        if (voice.id.value != id) voice,
    ], affected: existing);
  }

  /// A filesystem-safe stem for [name] that no voice in [taken] already uses.
  ///
  /// Two designs can legitimately be called the same thing, so the collision is
  /// resolved numerically rather than refused: a user rolling variations of
  /// "Warm narrator" should not have to invent names for the third one.
  ///
  /// Slugging rather than escaping keeps the clip filenames readable, which
  /// matters because a user dropping one into another tool will see this name.
  static String _allocateId(String name, Iterable<String> taken) {
    final used = taken.toSet();
    final slug = _slugify(name);
    if (!used.contains(slug)) return slug;
    for (var suffix = 2; ; suffix++) {
      final candidate = '$slug-$suffix';
      if (!used.contains(candidate)) return candidate;
    }
  }

  static final _unsafe = RegExp('[^a-z0-9]+');
  static final _leadDashes = RegExp('^-+');
  static final _trailDashes = RegExp(r'-+$');

  /// Lowercases [value] to a stem safe on every platform's filesystem.
  ///
  /// Windows additionally reserves a handful of device names, and a clip called
  /// `con.wav` cannot be written on the one platform where the app runs a local
  /// design model least. Rather than carry that list around for one edge case,
  /// a name that slugs to nothing falls back to a fixed stem.
  static String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(_unsafe, '-')
        .replaceAll(_leadDashes, '')
        .replaceAll(_trailDashes, '');
    if (slug.isEmpty || _reservedWindowsNames.contains(slug)) {
      return 'custom-voice';
    }
    return slug;
  }

  static const _reservedWindowsNames = {
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// The registry as a mutable map, so a write can preserve keys this schema
  /// does not define.
  Map<String, dynamic> _readRegistryJson() {
    final file = registryFile;
    if (!file.existsSync()) return <String, dynamic>{};
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return <String, dynamic>{};
    }
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    return decoded;
  }

  List<CustomVoice> _voicesFrom(Map<String, dynamic> json) {
    final raw = json['voices'];
    if (raw is! List) return const [];
    final voices = <CustomVoice>[];
    for (final entry in raw) {
      final voice = _voiceFromJson(entry);
      if (voice != null) voices.add(voice);
    }
    return voices;
  }

  /// Writes [voices] into the registry and returns the result of that write.
  ///
  /// Every key of [json] other than `voices` is carried across untouched. The
  /// registry is the user's file as much as a model's is, and there is no
  /// reason a rename should be the thing that drops a field written by hand or
  /// by a future version.
  CustomVoiceEdit _writeRegistry(
    Map<String, dynamic> json,
    List<CustomVoice> voices, {
    required CustomVoice affected,
  }) {
    json['voices'] = [for (final voice in voices) _voiceToJson(voice)];
    final file = registryFile;
    final temp = File('${file.path}.tmp');
    try {
      file.parent.createSync(recursive: true);
      temp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
      // Atomic: a rename replaces the target in one step, so a crash or a full
      // disk leaves the previous registry intact rather than a half-written one.
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } on FileSystemException {
          // Leaving a stray temp file behind is better than masking the cause.
        }
      }
      return CustomVoiceEdit.rejected('Cannot save the voice library: $e');
    }
    return CustomVoiceEdit.written(affected);
  }

  /// Decodes one registry entry, or null when it is unusable.
  ///
  /// An entry missing an id or transcript is skipped rather than fatal: the id
  /// names the clip on disk and the transcript is what a cloning model reads
  /// with it, so an entry lacking either cannot be used and is not worth
  /// taking the whole library down for.
  static CustomVoice? _voiceFromJson(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final id = entry['id'];
    final transcript = entry['transcript'];
    if (id is! String || id.trim().isEmpty) return null;
    if (transcript is! String || transcript.trim().isEmpty) return null;
    final name = entry['name'];
    final language = entry['language'];
    return CustomVoice(
      id: CustomVoiceId(id),
      name: CustomVoiceName(name is String && name.isNotEmpty ? name : id),
      designModel: entry['design_model'] is String
          ? entry['design_model'] as String
          : '',
      instruct: entry['instruct'] is String ? entry['instruct'] as String : '',
      language: language is String && language.isNotEmpty ? language : null,
      transcript: transcript,
      createdAt: DateTime.tryParse('${entry['created_at']}') ?? DateTime.now(),
    );
  }

  static Map<String, dynamic> _voiceToJson(CustomVoice voice) => {
        'id': voice.id.value,
        'name': voice.name.value,
        'design_model': voice.designModel,
        'instruct': voice.instruct,
        if (voice.language != null) 'language': voice.language,
        'transcript': voice.transcript,
        'created_at': voice.createdAt.toIso8601String(),
      };
}