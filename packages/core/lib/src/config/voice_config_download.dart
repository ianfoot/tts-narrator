import 'dart:convert';
import 'dart:io';

import 'voice_config_io.dart';

const _repoUrl = 'https://github.com/ianfoot/tts-narrator';
const _apiUrl = 'https://api.github.com';
const _branch = 'main';
const _voiceConfigDir = 'voice-config';

/// The paths of every config file the repository ships, relative to its
/// `voice-config/` directory — `config.json`, `providers/local.json`,
/// `models/kokoro.json`, `models/macos/kokoro_local.json`.
///
/// Read out of the git tree rather than out of a file the repository would have
/// to maintain: the tree already is the answer, so listing a model is the same
/// act as adding one, and there is no index to fall out of step with the
/// directories beside it.
///
/// One request covers the whole directory. Walking the contents API instead
/// would cost a request per subdirectory and then one per file to download,
/// against an unauthenticated rate limit of sixty an hour that nothing here
/// holds a token for.
///
/// Throws on network failure or an unreadable response; callers decide how to
/// degrade, which for the GUI means running on whatever is already on disk.
Future<List<String>> fetchVoiceConfigPaths({
  HttpClient Function()? clientFactory,
  String? repoUrl,
  String? apiUrl,
  String? branch,
}) async {
  final httpClient =
      (clientFactory ??
      () => HttpClient()..connectionTimeout = const Duration(seconds: 5))();
  try {
    final br = branch ?? _branch;
    final base = (apiUrl ?? _apiUrl).replaceFirst(RegExp(r'/+$'), '');
    final url =
        '$base/repos/${_repoSlug(repoUrl)}/git/trees/$br?recursive=1';
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to list voice config (HTTP ${response.statusCode})',
      );
    }
    final content = await response.transform(utf8.decoder).join();
    return voiceConfigPathsFromTree(content);
  } finally {
    httpClient.close(force: true);
  }
}

/// Extracts the `voice-config/` paths from a git tree response body.
///
/// Exposed for tests: the response is the contract, and a fake tree is a better
/// test than a fake HTTP client.
List<String> voiceConfigPathsFromTree(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('git tree response must be a JSON object');
  }
  final tree = decoded['tree'];
  if (tree is! List) {
    throw const FormatException('git tree response has no "tree" list');
  }
  final prefix = '$_voiceConfigDir/';
  final paths = <String>[];
  for (final entry in tree) {
    if (entry is! Map<String, dynamic>) continue;
    if (entry['type'] != 'blob') continue;
    final path = entry['path'];
    if (path is! String || !path.startsWith(prefix)) continue;
    if (!path.toLowerCase().endsWith('.json')) continue;
    // POSIX in, POSIX out: the tree is a git path list, never a local one.
    final relative = path.substring(prefix.length);
    if (relative.split('/').contains('..')) continue;
    paths.add(relative);
  }
  paths.sort();
  return paths;
}

/// `owner/repo` out of a repository URL, so one [repoUrl] can serve both the API
/// and the raw downloads.
String _repoSlug(String? repoUrl) {
  final base = (repoUrl ?? _repoUrl).replaceFirst(RegExp(r'/+$'), '');
  final match = RegExp(
    r'^https?://[^/]+/([^/]+/[^/]+?)(?:\.git)?$',
  ).firstMatch(base);
  if (match == null) {
    throw FormatException('Not a repository URL: $base');
  }
  return match.group(1)!;
}

/// Downloads voice config files from the GitHub repository into [configDir].
///
/// [paths] are the repo-relative paths from [fetchVoiceConfigPaths] — relative to
/// `voice-config/`, not to the config directory — and each keeps its own
/// subdirectory, so `models/macos/kokoro_local.json` lands there rather than
/// flattened into `models/`. `config.json` is fetched whether or not the tree
/// lists it, since its absence is what marks a directory as not yet a config.
///
/// A file already on disk is left alone unless [overwrite] is set, which is what
/// a re-sync wants: the user's `user/` layer is a separate directory and is never
/// touched here.
///
/// Downloads are best-effort: a failure for one file continues with the rest.
Future<void> downloadVoiceConfigFiles(
  String configDir, {
  List<String>? paths,
  bool overwrite = false,
  HttpClient Function()? clientFactory,
  String? repoUrl,
  String? branch,
}) async {
  final separator = Platform.pathSeparator;
  // A set keyed by destination path, so a path named twice is fetched once.
  final all = <String>{
    '$configDir$separator$kVoiceConfigRegistryName',
    for (final p in paths ?? const <String>[])
      '$configDir$separator${p.split('/').join(separator)}',
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
      if (localFile.existsSync() && !overwrite) continue;
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
      } catch (_) {
        // Best-effort: carry on with the rest.
      }
    }
  } finally {
    httpClient.close(force: true);
  }
}