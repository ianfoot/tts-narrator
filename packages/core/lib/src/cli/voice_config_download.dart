import 'dart:convert';
import 'dart:io';

/// Downloads voice config files from GitHub repository if they don't exist locally.
/// Uses the project's repository URL to fetch the config files.
Future<void> downloadVoiceConfigFiles(String configDir) async {
  const repoUrl = 'https://github.com/ianfoot/tts-narrator';
  const branch = 'main';
  final files = ['config.json', 'fish.json', 'gemini.json', 'kokoro.json'];
  final separator = Platform.pathSeparator;

  // Create config directory if it doesn't exist
  final dir = Directory(configDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  for (final file in files) {
    final localFile = File('$configDir$separator$file');
    if (!localFile.existsSync()) {
      final url = '$repoUrl/raw/$branch/voice-config/$file';
      try {
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final content = await response.transform(utf8.decoder).join();
          await localFile.writeAsString(content);
        }
        httpClient.close();
      } catch (e) {
        // If download fails, continue with existing behavior
        // The app will fall back to fish bootstrap
      }
    }
  }
}
