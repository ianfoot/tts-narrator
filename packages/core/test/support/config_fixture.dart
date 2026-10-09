import 'dart:io';

import 'package:tts_narrator_core/src/config/voice_config_io.dart';

/// A config directory on disk, plus the writers that populate it.
///
/// `loadVoiceConfig` reads two layers: the config root, where the shipped
/// starter files live, and the `user` overlay, where a user's own files land and
/// merge with the baseline. Every writer takes the layer it targets and defaults
/// to the root, so the common case reads `writeModel('one', ...)` and a test only
/// spells out [overlay] where the layering is the thing under test.
class ConfigFixture {
  ConfigFixture(this.dir);

  /// The config root, where the downloaded starter files live.
  static const base = '.';

  /// The overlay root, where everything the user authors lands.
  static const overlay = kVoiceConfigOverlayDirName;

  final Directory dir;

  /// The path of [file] inside [dirName] under this config root.
  String at(String dirName, String file) =>
      '${dir.path}${Platform.pathSeparator}$dirName'
      '${Platform.pathSeparator}$file';

  /// [relative] under [layer]. The root layer is the config directory itself.
  String _under(String layer, String relative) =>
      layer == base ? at(base, relative) : at(layer, relative);

  void _write(String path, String contents) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  /// The `config.json` registry for [layer].
  void writeRegistry(String contents, [String layer = base]) =>
      _write(_under(layer, kVoiceConfigRegistryName), contents);

  /// A `providers/<name>.json` block in [layer].
  void writeProvider(String name, String contents, [String layer = base]) =>
      _write(_under(layer, '$kVoiceConfigProvidersDir/$name.json'), contents);

  /// A `models/<alias>.json` file in [layer].
  void writeModel(String alias, String contents, [String layer = base]) =>
      _write(_under(layer, '$kVoiceConfigModelsDir/$alias.json'), contents);
}