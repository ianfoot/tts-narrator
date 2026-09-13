import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

import 'src/gui/controller/app_controller.dart';
import 'src/gui/controller/config_loader.dart';
import 'src/gui/platform/app_root.dart';
import 'src/gui/platform/widgets/platform_activity_indicator.dart';

/// Root app that provides a Navigator so ConfigBootstrap can show dialogs.
class BootstrapApp extends StatelessWidget {
  const BootstrapApp({
    super.key,
    required this.configDir,
    required this.prefs,
    this.downloader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]);
  /// tests inject a controllable fake so the spinner is observable.
  final Future<void> Function(String configDir)? downloader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTS Narrator',
      debugShowCheckedModeBanner: false,
      home: ConfigBootstrap(
        configDir: configDir,
        prefs: prefs,
        downloader: downloader,
      ),
    );
  }
}

/// Handles first-run config download: shows confirmation dialog,
/// then spinner, then launches AppRoot.
class ConfigBootstrap extends StatefulWidget {
  const ConfigBootstrap({
    super.key,
    required this.configDir,
    required this.prefs,
    this.downloader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]).
  final Future<void> Function(String configDir)? downloader;

  @override
  State<ConfigBootstrap> createState() => _ConfigBootstrapState();
}

class _ConfigBootstrapState extends State<ConfigBootstrap> {
  bool _downloading = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConfig());
  }

  void _checkConfig() async {
    final configFile = File('${widget.configDir}/config.json');
    final modelFiles = ['fish.json', 'gemini.json', 'kokoro.json'];
    final missing =
        !configFile.existsSync() ||
        modelFiles.any((f) => !File('${widget.configDir}/$f').existsSync());

    if (missing) {
      await _promptDownload();
    } else {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _promptDownload() async {
    final confirmed = await showDialog<bool>(
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

    if (confirmed == true) {
      await _downloadWithSpinner();
    } else {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _downloadWithSpinner() async {
    final downloader =
        widget.downloader ??
        (String configDir) => downloadVoiceConfigFiles(configDir);
    if (mounted) setState(() => _downloading = true);
    try {
      await downloader(widget.configDir);
    } finally {
      if (mounted) setState(() => _downloading = false);
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PlatformActivityIndicator(size: 32),
              SizedBox(height: 16),
              Text('Downloading voice configurations...'),
            ],
          ),
        ),
      );
    }

    if (_ready) {
      return AppRoot(
        controller: AppController(
          loader: UserVoiceConfigLoader(configDir: widget.configDir),
          prefs: widget.prefs,
        ),
      );
    }

    // Waiting for user confirmation
    return const Scaffold(body: Center(child: Text('Initializing...')));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);

  final appSupportDir = await getApplicationSupportDirectory();
  final configDir = '${appSupportDir.parent.path}/TTS Narrator';

  runApp(BootstrapApp(configDir: configDir, prefs: prefs));
}
