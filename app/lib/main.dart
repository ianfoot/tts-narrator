import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';
import 'package:tts_narrator_mlx_audio/mlx_audio_tts_provider.dart';

import 'src/gui/controller/app_controller.dart';
import 'src/gui/controller/config_loader.dart';
import 'src/gui/platform/app_root.dart';
import 'src/gui/platform/platform_detection.dart';
import 'src/gui/theme/app_text_tokens.dart' show TextTokens, fillTextTemplate;

/// Root app that provides a Navigator so ConfigBootstrap can show dialogs.
class BootstrapApp extends StatelessWidget {
  const BootstrapApp({
    super.key,
    required this.configDir,
    required this.prefs,
    this.downloader,
    this.manifestLoader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]);
  /// tests inject a controllable fake so the spinner is observable.
  final Future<void> Function(String configDir, List<String> files)?
      downloader;

  /// Injectable starter-manifest loader (defaults to a cached-fetch from
  /// GitHub); tests inject a fake so the bootstrap is hermetic.
  final Future<ManifestVoiceConfig?> Function()? manifestLoader;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: TextTokens.app_title,
      debugShowCheckedModeBanner: false,
      home: ConfigBootstrap(
        configDir: configDir,
        prefs: prefs,
        downloader: downloader,
        manifestLoader: manifestLoader,
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
    this.manifestLoader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]).
  final Future<void> Function(String configDir, List<String> files)?
      downloader;

  /// Injectable starter-manifest loader (defaults to a cached-fetch from
  /// GitHub); tests inject a fake so the bootstrap is hermetic.
  final Future<ManifestVoiceConfig?> Function()? manifestLoader;

  @override
  State<ConfigBootstrap> createState() => _ConfigBootstrapState();
}

class _ConfigBootstrapState extends State<ConfigBootstrap> {
  bool _downloading = false;
  bool _ready = false;

  /// The starter model files expected on this platform (from the manifest).
  /// Populated before the download prompt; reused by the downloader.
  List<String> _starterFiles = const [];

  /// Created once and reused across rebuilds (including hot reload), so the
  /// controller identity stays stable and widget listeners stay attached.
  AppController? _controller;

  AppController _ensureController() => _controller ??= AppController(
    loader: UserVoiceConfigLoader(configDir: widget.configDir),
    prefs: widget.prefs,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConfig());
  }

  @override
  void dispose() {
    // Subtree children unmount before parent dispose, so their listeners are
    // removed before the controller dies.
    _controller?.dispose();
    super.dispose();
  }

  /// Loads the starter manifest: injectable loader, else a locally cached
  /// `manifest.json` in the config dir, else a fetch from GitHub (cached for
  /// offline later runs). Returns null when unavailable (offline first run).
  Future<ManifestVoiceConfig?> _loadManifest() async {
    final injected = widget.manifestLoader;
    if (injected != null) return injected();

    final cacheFile = File('${widget.configDir}/$kVoiceConfigManifestName');
    if (cacheFile.existsSync()) {
      try {
        return ManifestVoiceConfig.fromJson(
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        // Corrupt cache: refetch below.
      }
    }
    try {
      final manifest = await fetchVoiceConfigManifest();
      await cacheFile.writeAsString(jsonEncode(manifest.toJson()));
      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// The starter model files for this platform: from the manifest when
  /// available, else a platform-neutral fallback without macOS-only models
  /// (offline first run still offers the cloud starters).
  Future<List<String>> _loadStarterFiles() async {
    final manifest = await _loadManifest();
    return manifest?.filesFor(platformTag) ?? _fallbackStarterFiles;
  }

  /// Platform-neutral starter set used when the manifest is unreachable
  /// (mlx_kokoro.json is macOS-only data, so it is never in this fallback).
  static const _fallbackStarterFiles = [
    'fish.json',
    'gemini.json',
    'kokoro.json',
  ];

  void _checkConfig() async {
    _starterFiles = await _loadStarterFiles();
    final configFile = File('${widget.configDir}/config.json');
    final missing =
        !configFile.existsSync() ||
        _starterFiles.any((f) => !File('${widget.configDir}/$f').existsSync());

    if (missing) {
      await _promptDownload();
    } else {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _promptDownload() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: const Text(TextTokens.gui_bootstrap_downloadTitle),
        content: Text(
          fillTextTemplate(TextTokens.gui_bootstrap_downloadPrompt, {
            'files': _starterFiles.map(_starterDisplayName).join(', '),
          }),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TextTokens.gui_bootstrap_notNow),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TextTokens.gui_bootstrap_download),
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
        (String configDir, List<String> files) =>
            downloadVoiceConfigFiles(configDir, files: files);
    if (mounted) setState(() => _downloading = true);
    try {
      await downloader(widget.configDir, _starterFiles);
    } finally {
      if (mounted) setState(() => _downloading = false);
      if (mounted) setState(() => _ready = true);
    }
  }

  /// Stems whose display name is not plain title-casing.
  static const _stemOverrides = {'mlx': 'MLX'};

  /// 'mlx_kokoro.json' -> 'MLX Kokoro'; 'fish.json' -> 'Fish'.
  static String _starterDisplayName(String file) {
    return _withoutExtension(file).split('_').map(_capitalizeWord).join(' ');
  }

  static String _withoutExtension(String file) => file.endsWith('.json')
      ? file.substring(0, file.length - '.json'.length)
      : file;

  static String _capitalizeWord(String word) {
    final override = _stemOverrides[word];
    if (override != null) return override;
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      return const CupertinoPageScaffold(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(radius: 16),
              SizedBox(height: 16),
              Text(TextTokens.gui_bootstrap_downloading),
            ],
          ),
        ),
      );
    }

    if (_ready) {
      return AppRoot(controller: _ensureController());
    }

    // Waiting for user confirmation
    return const CupertinoPageScaffold(
      child: Center(child: Text(TextTokens.gui_bootstrap_initializing)),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Providers are registered on every platform: the local OpenAI-compatible
  // provider (id `mlx_audio`) is a plain HTTP client and works anywhere a
  // compatible server answers; per-platform differences live in data (which
  // starter voice-config files ship, via voice-config/manifest.json).
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);
  ttsProviderRegistry.register('mlx_audio', MlxAudioTtsProvider.new);

  final appSupportDir = await getApplicationSupportDirectory();
  final configDir = appSupportDir.path;

  runApp(BootstrapApp(configDir: configDir, prefs: prefs));
}