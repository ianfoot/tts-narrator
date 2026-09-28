import 'dart:convert';
import 'dart:io';

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

/// Per-platform starter model file lists, parsed from the repo's
/// `voice-config/manifest.json`.
///
/// Maps a platform tag (`macos` / `linux` / `windows`) to the list of starter
/// model `<alias>.json` file names that ship by default on that platform.
/// `config.json` is always downloaded and is not listed here.
///
/// A platform with no starter files is expressed by omitting its key entirely
/// (filesFor then returns an empty list).
class ManifestVoiceConfig {
  ManifestVoiceConfig._(Map<String, List<String>> platforms)
    : _platforms = platforms;

  factory ManifestVoiceConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['platforms'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('manifest.json must be a {"platforms": ...} object');
    }
    final platforms = <String, List<String>>{};
    raw.forEach((tag, entries) {
      if (entries is! List) {
        throw FormatException('manifest platform "$tag" must be a list of files');
      }
      final files = <String>[];
      for (final e in entries) {
        if (e is! String || e.isEmpty) {
          throw FormatException('manifest platform "$tag" has a non-string entry');
        }
        files.add(e);
      }
      platforms[tag] = files;
    });
    return ManifestVoiceConfig._(platforms);
  }

  final Map<String, List<String>> _platforms;

  /// The starter file names (e.g. `['fish.json', 'kokoro.json']`) for
  /// [platformTag], or an empty list when the platform has no manifest entry.
  List<String> filesFor(String platformTag) =>
      _platforms[platformTag] ?? const [];

  /// Whether [platformTag] has an explicit entry in the manifest.
  bool hasPlatform(String platformTag) => _platforms.containsKey(platformTag);

  /// Round-trips back to the canonical manifest shape for local caching.
  Map<String, dynamic> toJson() => {
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
/// platform's starter list from a [ManifestVoiceConfig]); `config.json` is
/// always fetched first. Downloads are best-effort: a failure for one file
/// continues with the rest, matching legacy behavior.
Future<void> downloadVoiceConfigFiles(
  String configDir, {
  List<String>? files,
  HttpClient Function()? clientFactory,
  String? repoUrl,
  String? branch,
}) async {
  final requested = files ?? const <String>[];
  final all = <String>{'config.json', ...requested};

  final separator = Platform.pathSeparator;

  final dir = Directory(configDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final httpClient =
      (clientFactory ??
      () => HttpClient()..connectionTimeout = const Duration(seconds: 5))();
  try {
    for (final file in all) {
      final localFile = File('$configDir$separator$file');
      if (!localFile.existsSync()) {
        final base = repoUrl ?? _repoUrl;
        final br = branch ?? _branch;
        final url = '$base/raw/$br/$_voiceConfigDir/$file';
        try {
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode == 200) {
            final content = await response.transform(utf8.decoder).join();
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