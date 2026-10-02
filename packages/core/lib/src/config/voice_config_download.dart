import 'dart:convert';
import 'dart:io';

import 'voice_config_io.dart';

const _repoUrl = 'https://github.com/ianfoot/tts-narrator';
const _branch = 'main';
const _voiceConfigDir = 'voice-config';

/// Name of the per-platform starter manifest file inside the voice config
/// directory (both in the repo and when cached locally).
const kVoiceConfigManifestName = 'manifest.json';

/// Platform tags used as manifest keys.
///
/// Single source of truth for the tag strings: app code (see
/// `platform_detection.dart`) maps a running platform to a tag via these
/// constants instead of repeating the literals.
const kPlatformTagMacos = 'macos';
const kPlatformTagLinux = 'linux';
const kPlatformTagWindows = 'windows';

/// Starter file lists, parsed from the repo's `voice-config/manifest.json`.
///
/// Two kinds of file ship by default:
///   * `providers` — provider files, fetched for every platform, because a
///     model file is meaningless without the block that names it.
///   * `platforms` — a platform tag (`macos` / `linux` / `windows`) mapped to
///     the starter model `<alias>.json` file names to fetch on that platform.
///
/// Entries are bare file names, never paths: the subdirectory each kind lives
/// in is the downloader's business, which keeps a manifest free of platform
/// path separators.
///
/// `config.json` is always downloaded and is listed in neither. A platform with
/// no starter files is expressed by omitting its key entirely (filesFor then
/// returns an empty list), and `platforms` may be omitted altogether.
class ManifestVoiceConfig {
  ManifestVoiceConfig._(Map<String, List<String>> platforms, this.providers)
    : _platforms = platforms;

  factory ManifestVoiceConfig.fromJson(Map<String, dynamic> json) {
    final platforms = <String, List<String>>{};
    final raw = json['platforms'];
    if (raw != null) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException(
          'manifest.json "platforms" must be an object',
        );
      }
      raw.forEach((tag, entries) {
        if (entries is! List) {
          throw FormatException(
            'manifest platform "$tag" must be a list of files',
          );
        }
        platforms[tag] = [
          for (final e in entries)
            if (e is! String || e.isEmpty)
              throw FormatException(
                'manifest platform "$tag" has a non-string entry',
              )
            else
              e,
        ];
      });
    }
    final rawProviders = json['providers'];
    if (rawProviders != null && rawProviders is! List) {
      throw const FormatException('manifest.json "providers" must be a list');
    }
    final providers = <String>[];
    for (final e in (rawProviders ?? const [])) {
      if (e is! String || e.isEmpty) {
        throw const FormatException(
          'manifest.json "providers" has a non-string entry',
        );
      }
      providers.add(e);
    }
    return ManifestVoiceConfig._(platforms, providers);
  }

  final Map<String, List<String>> _platforms;

  /// Provider file names to fetch on every platform (e.g. `['openrouter.json']`).
  final List<String> providers;

  /// The starter model file names (e.g. `['fish.json', 'kokoro.json']`) for
  /// [platformTag], or an empty list when the platform has no manifest entry.
  List<String> filesFor(String platformTag) =>
      _platforms[platformTag] ?? const [];

  /// Whether [platformTag] has an explicit entry in the manifest.
  bool hasPlatform(String platformTag) => _platforms.containsKey(platformTag);

  /// Round-trips back to the canonical manifest shape for local caching.
  Map<String, dynamic> toJson() => {
    'providers': providers,
    'platforms': {
      for (final entry in _platforms.entries) entry.key: entry.value,
    },
  };
}

/// Fetches the per-platform starter manifest from the repo's voice-config
/// directory.
///
/// Throws on network failure or an unparseable manifest; callers decide how to
/// degrade (the GUI falls back to no starter model files).
Future<ManifestVoiceConfig> fetchVoiceConfigManifest({
  HttpClient Function()? clientFactory,
  String? repoUrl,
  String? branch,
}) async {
  final httpClient =
      (clientFactory ??
      () => HttpClient()..connectionTimeout = const Duration(seconds: 5))();
  try {
    final base = repoUrl ?? _repoUrl;
    final br = branch ?? _branch;
    final url = '$base/raw/$br/$_voiceConfigDir/$kVoiceConfigManifestName';
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch voice config manifest (HTTP ${response.statusCode})',
      );
    }
    final content = await response.transform(utf8.decoder).join();
    return ManifestVoiceConfig.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
  } finally {
    httpClient.close(force: true);
  }
}

/// Downloads voice config files from the GitHub repository into [configDir]
/// when they don't exist locally.
///
/// [files] names the model files to fetch (e.g. `['fish.json']`, typically the
/// platform's starter list from a [ManifestVoiceConfig]); [providers] names the
/// provider files to fetch alongside them. `config.json` is always fetched.
///
/// Files land in the subdirectory their kind belongs to: providers in
/// `providers/`, models in `models/`. The manifest carries bare file names and
/// the split happens here, so nothing has to reason about path separators.
///
/// Downloads are best-effort: a failure for one file continues with the rest,
/// matching legacy behavior.
Future<void> downloadVoiceConfigFiles(
  String configDir, {
  List<String>? files,
  List<String>? providers,
  HttpClient Function()? clientFactory,
  String? repoUrl,
  String? branch,
}) async {
  final separator = Platform.pathSeparator;
  // config.json first, then each kind into its own subdirectory. A set keyed by
  // destination path, so a name appearing in both lists is fetched once.
  final all = <String>{
    '$configDir$separator$kVoiceConfigRegistryName',
    for (final f in providers ?? const <String>[])
      '$configDir$separator$kVoiceConfigProvidersDir$separator$f',
    for (final f in files ?? const <String>[])
      '$configDir$separator$kVoiceConfigModelsDir$separator$f',
  };

  final dir = Directory(configDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final httpClient =
      (clientFactory ??
      () => HttpClient()..connectionTimeout = const Duration(seconds: 5))();
  try {
    for (final localPath in all) {
      final localFile = File(localPath);
      if (!localFile.existsSync()) {
        final base = repoUrl ?? _repoUrl;
        final br = branch ?? _branch;
        final remote = localPath
            .substring(configDir.length + 1)
            .split(separator)
            .join('/');
        final url = '$base/raw/$br/$_voiceConfigDir/$remote';
        try {
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode == 200) {
            final content = await response.transform(utf8.decoder).join();
            await localFile.parent.create(recursive: true);
            await localFile.writeAsString(content);
          }
        } catch (e) {
          // If download fails, continue with existing behavior
        }
      }
    }
  } finally {
    httpClient.close(force: true);
  }
}
