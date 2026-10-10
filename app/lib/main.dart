import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import 'l10n/app_localizations.dart';
import 'src/gui/controller/app_controller.dart';
import 'src/gui/controller/config_loader.dart';
import 'src/gui/platform/app_root.dart';

/// Downloads the shipped voice config into [configDir].
///
/// [paths] are repository-relative, exactly as [fetchVoiceConfigPaths] returns
/// them, each keeping the subdirectory it sits under.
///
/// This exists because the downloader's two shapes do not match:
/// [downloadVoiceConfigFiles] takes `paths` as a *named* argument while
/// [VoiceConfigDownloader] takes it positionally. Passing the tear-off where
/// that signature is expected leaves no call signature in common, so a `??`
/// selecting it degrades to a bare `Function` and the call dispatches
/// dynamically — a `NoSuchMethodError` on first run, and not one a compiler or
/// a test that always injects a fake would ever catch.
///
/// It stays a wrapper rather than being inlined at the call site because the
/// call site is the only place the two shapes meet, and that meeting has to be
/// a compile-time check rather than a runtime one.
Future<void> fetchVoiceConfig(String configDir, List<String> paths) =>
    downloadVoiceConfigFiles(configDir, paths: paths);

/// Injectable config downloader (defaults to [downloadVoiceConfigFiles]);
/// tests inject a controllable fake so the spinner is observable.
///
/// [paths] are the repository-relative config paths to fetch, as
/// [fetchVoiceConfigPaths] returns them — the whole of `voice-config/`, models
/// and providers together, each keeping its own subdirectory.
typedef VoiceConfigDownloader = Future<void> Function(
  String configDir,
  List<String> paths,
);

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({
    super.key,
    required this.configDir,
    required this.prefs,
    this.downloader,
    this.indexLoader,
    this.defaultDownloader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]);
  /// tests inject a controllable fake so the spinner is observable.
  final VoiceConfigDownloader? downloader;

  /// Injectable config-path loader (defaults to a fetch from GitHub); tests
  /// inject a fake so the bootstrap is hermetic.
  final Future<List<String>?> Function()? indexLoader;

  /// Stands in for [fetchVoiceConfig] when [downloader] is absent.
  ///
  /// A widget test cannot make a real request, so without this the fallback
  /// branch is unreachable from the suite — which is exactly how a signature
  /// mismatch in it shipped green and crashed on the app's first run.
  final VoiceConfigDownloader? defaultDownloader;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      // Not localized: this context sits ABOVE the delegate scope it is about
      // to install, so `AppLocalizations.of(context)` cannot resolve here.
      // BootstrapApp is a transient pre-AppRoot shell anyway — AppRoot owns
      // the window title.
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
        indexLoader: indexLoader,
        defaultDownloader: defaultDownloader,
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
    this.indexLoader,
    this.defaultDownloader,
  });
  final String configDir;
  final SharedPreferences prefs;

  /// Injectable config downloader (defaults to [downloadVoiceConfigFiles]).
  final VoiceConfigDownloader? downloader;

  /// Injectable config-path loader (defaults to a fetch from GitHub); tests
  /// inject a fake so the bootstrap is hermetic.
  final Future<List<String>?> Function()? indexLoader;

  /// Stands in for [fetchVoiceConfig] when [downloader] is absent. See
  /// [BootstrapApp.defaultDownloader].
  final VoiceConfigDownloader? defaultDownloader;

  @override
  State<ConfigBootstrap> createState() => _ConfigBootstrapState();
}

class _ConfigBootstrapState extends State<ConfigBootstrap> {
  bool _downloading = false;
  bool _ready = false;

  /// The repository's config paths, fetched once and used for both the "is
  /// anything here already?" check and the download. Empty when GitHub cannot
  /// be reached, which is the offline first run: the check then asks about
  /// whatever is on disk rather than about files it cannot name.
  List<String> _remotePaths = const [];

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

  /// Loads the list of config paths the repository ships: the injected loader
  /// when there is one, else the GitHub tree. Returns an empty list when GitHub
  /// is unreachable (offline first run).
  Future<List<String>> _loadIndex() async {
    final injected = widget.indexLoader;
    if (injected != null) return (await injected()) ?? const [];

    try {
      return await fetchVoiceConfigPaths();
    } catch (_) {
      return const [];
    }
  }

  /// Whether `providers/` holds at least one file. Non-empty rather than
  /// "the ones the index names": nothing lists them any more, so the question is
  /// whether there are any, and a directory that exists but is empty has not
  /// been downloaded.
  bool _hasAnyProviderFile() {
    final dir = Directory('${widget.configDir}/$kVoiceConfigProvidersDir');
    if (!dir.existsSync()) return false;
    return dir.listSync().any((e) => e is File && e.path.endsWith('.json'));
  }

  /// Whether `models/` holds at least one model file, counting any platform
  /// subdirectory as well as the top-level files.
  bool _hasAnyModelFile() {
    final dir = Directory('${widget.configDir}/$kVoiceConfigModelsDir');
    if (!dir.existsSync()) return false;
    if (dir.listSync().any((e) => e is File && e.path.endsWith('.json'))) {
      return true;
    }
    return dir.listSync().whereType<Directory>().any(
      (sub) => sub
          .listSync()
          .any((e) => e is File && e.path.endsWith('.json')),
    );
  }

  void _checkConfig() async {
    _remotePaths = await _loadIndex();
    final hasMarker = File(
      '${widget.configDir}/$kVoiceConfigRegistryName',
    ).existsSync();
    // With no index to compare against, the only honest question is whether the
    // directory holds a usable config: the marker plus something to reach a
    // provider with and something for it to serve.
    final missing = !hasMarker || !_hasAnyProviderFile() || !_hasAnyModelFile();

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
          l10n.gui_bootstrap_downloadPrompt(_modelNamesToDisplay()),
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
    // A wrapper, not the tear-off of `downloadVoiceConfigFiles`: that takes
    // `paths` as a *named* argument while [VoiceConfigDownloader] takes it
    // positionally, so the two share no call signature. `?? downloadVoiceConfigFiles`
    // left the result a bare `Function` and the call dispatched dynamically — a
    // NoSuchMethodError on first run, invisible to 312 passing tests because
    // every one of them injected `downloader` and none reached this branch.
    final download = widget.downloader ??
        widget.defaultDownloader ??
        (configDir, paths) => fetchVoiceConfig(configDir, paths);
    if (mounted) setState(() => _downloading = true);
    try {
      await download(widget.configDir, _remotePaths);
    } finally {
      if (mounted) setState(() => _downloading = false);
      if (mounted) setState(() => _ready = true);
    }
  }

  /// The model names to name in the download prompt.
  ///
  /// Every model file in the index, this platform's directory included — the
  /// download is of the whole config, so a prompt that listed only one platform's
  /// would be describing something narrower than what happens. With no index
  /// (offline first run) the cloud starters stand in, which are the ones that
  /// need nothing running locally.
  String _modelNamesToDisplay() {
    final paths = _remotePaths.isEmpty ? _fallbackPaths : _remotePaths;
    return paths
        .where((p) => p.startsWith('$kVoiceConfigModelsDir/'))
        .map((p) => _starterDisplayName(p.split('/').last))
        .join(', ');
  }

  /// Platform-neutral starters used when the index is unreachable. No macOS-only
  /// models here: those are files the index would have named, and a guess that
  /// names a model this platform cannot run is worse than saying less.
  static const _fallbackPaths = [
    '$kVoiceConfigModelsDir/fish.json',
    '$kVoiceConfigModelsDir/gemini.json',
    '$kVoiceConfigModelsDir/kokoro.json',
  ];

  /// 'kokoro_local.json' -> 'Kokoro Local'; 'fish.json' -> 'Fish'.
  static String _starterDisplayName(String file) {
    return _withoutExtension(file).split('_').map(_capitalizeWord).join(' ');
  }

  static String _withoutExtension(String file) => file.endsWith('.json')
      ? file.substring(0, file.length - '.json'.length)
      : file;

  static String _capitalizeWord(String word) {
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
