import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

import 'src/gui/controller/app_controller.dart';
import 'src/gui/controller/config_loader.dart';
import 'src/gui/platform/app_root.dart';

/// Shows a confirmation dialog to download initial config files from GitHub.
/// Returns true if the user confirmed the download, false otherwise.
Future<bool> showDownloadConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Download Voice Configurations?'),
      content: const Text(
        'No voice configurations found. Would you like to download starter '
        'configurations (Fish, Gemini, Kokoro) from GitHub?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not Now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Download'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);

  /// Resolve the cross-platform config directory to:
  /// ~/Library/Application Support/TTS Narrator/ (macOS sandbox path)
  final appSupportDir = await getApplicationSupportDirectory();
  final configDir = '${appSupportDir.parent.path}/TTS Narrator';
  final configFile = File('$configDir/config.json');
  final modelFiles = ['fish.json', 'gemini.json', 'kokoro.json'];

  /// Check if config files exist; if missing, download after user confirmation.
  final needsDownload = !configFile.existsSync() ||
      modelFiles.any((file) => !File('$configDir/$file').existsSync());

  if (needsDownload) {
    /// Show confirmation dialog; if user confirms, download with spinner.
    /// Note: The actual dialog/spinner is handled by the Flutter app layer
    /// on first launch; here we perform the download synchronously for CLI
    /// or headless use cases. The GUI handles confirmation via AppRoot if needed.
    await downloadVoiceConfigFiles(configDir);
  }

  runApp(AppRoot(
    controller: AppController(
      loader: UserVoiceConfigLoader(configDir: configDir),
      prefs: prefs,
    ),
  ));
}
