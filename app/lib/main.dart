import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'l10n/app_localizations.dart';
import 'src/gui/controller/app_controller.dart';
import 'src/gui/controller/config_loader.dart';
import 'src/gui/platform/app_root.dart';
import 'src/gui/platform/platform_detection.dart';

/// Injectable config downloader (defaults to [downloadVoiceConfigFiles]);
/// tests inject a controllable fake so the spinner is observable.
///
/// [providers] is the manifest's provider file list: a model file is
/// meaningless without the block that names it, so provider files travel with
/// the models rather than in a separate download.
typedef VoiceConfigDownloader =
    Future<void> Function(
      String configDir,
      List<String> files, {
      List<String> providers,
    });

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
  final VoiceConfigDownloader? downloader;

  /// Injectable starter-manifest loader (defaults to a cached-fetch from
  /// GitHub); tests inject a fake so the bootstrap is hermetic.
  final Future<ManifestVoiceConfig?> Function()? manifestLoader;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      // Not localized: this widget's context sits ABOVE the delegate scope it
      // is about to install, so `AppLocalizations.of(context)` cannot resolve
      // here. BootstrapApp is a transient pre-AppRoot shell anyway — AppRoot
      // installs the real app and owns the window title.
      title: 'TTS Narrator',
      debugShowCheckedModeBanner: false,
      // Matches the delegate set in `platform/app_root.dart`, and for the same
      // reason: no GlobalMaterialLocalizations. See the comment there.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
  final VoiceConfigDownloader? downloader;

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

  /// The provider files every platform needs (from the manifest). Kept apart
  /// from [_starterFiles] because they are fetched alongside the models but are
  /// not models, so naming them in the download prompt would be wrong.
  List<String> _starterProviders = const [];

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
  ///
  /// Also records the manifest's provider files, which every platform needs
  /// regardless of which models it starts with.
  Future<List<String>> _loadStarterFiles() async {
    final manifest = await _loadManifest();
    _starterProviders = manifest?.providers ?? const [];
    return manifest?.filesFor(platformTag) ?? _fallbackStarterFiles;
  }

  /// Platform-neutral starter set used when the manifest is unreachable
  /// (mlx_kokoro.json is macOS-only data, so it is never in this fallback).
  ///
  /// With no manifest there are no provider files to fetch, so the fallback
  /// ships models only; the loader ignores models no provider claims anyway.
  static const _fallbackStarterFiles = [
    'fish.json',
    'gemini.json',
    'kokoro.json',
  ];

  /// Whether [file] exists under [subdir] of the config directory.
  bool _existsIn(String subdir, String file) =>
      File('${widget.configDir}/$subdir/$file').existsSync();

  void _checkConfig() async {
    _starterFiles = await _loadStarterFiles();
    final registry = File(
      '${widget.configDir}/$kVoiceConfigRegistryName',
    ).existsSync();
    // A config is complete only when the registry, every provider it needs, and
    // every starter model are on disk: the loader reaches models through
    // providers, so a missing provider file makes a downloaded model unusable.
    final missing =
        !registry ||
        _starterProviders.any((f) => !_existsIn(kVoiceConfigProvidersDir, f)) ||
        _starterFiles.any((f) => !_existsIn(kVoiceConfigModelsDir, f));

    if (missing) {
      await _promptDownload();
    } else {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _promptDownload() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.gui_bootstrap_downloadTitle),
        content: Text(
          l10n.gui_bootstrap_downloadPrompt(
            _starterFiles.map(_starterDisplayName).join(', '),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.gui_bootstrap_notNow),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.gui_bootstrap_download),
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
        (String configDir, List<String> files, {List<String> providers = const []}) =>
            downloadVoiceConfigFiles(
              configDir,
              files: files,
              providers: providers,
            );
    if (mounted) setState(() => _downloading = true);
    try {
      await downloader(
        widget.configDir,
        _starterFiles,
        providers: _starterProviders,
      );
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
    final l10n = AppLocalizations.of(context);
    if (_downloading) {
      return CupertinoPageScaffold(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CupertinoActivityIndicator(radius: 16),
              const SizedBox(height: 16),
              Text(l10n.gui_bootstrap_downloading),
            ],
          ),
        ),
      );
    }

    if (_ready) {
      return AppRoot(controller: _ensureController());
    }

    // Waiting for user confirmation
    return CupertinoPageScaffold(
      child: Center(child: Text(l10n.gui_bootstrap_initializing)),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final appSupportDir = await getApplicationSupportDirectory();
  final configDir = appSupportDir.path;

  runApp(BootstrapApp(configDir: configDir, prefs: prefs));
}
