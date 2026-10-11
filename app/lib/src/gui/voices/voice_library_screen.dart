import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';

import '../../../l10n/app_localizations.dart';
import '../controller/app_controller.dart';
import '../controller/custom_voice_controller.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/app_text_field.dart';
import 'voice_name_dialog.dart';

/// The voice library: design a voice, keep the ones worth keeping, hand one to
/// the active run.
///
/// A full-screen pushed route rather than a section of the run-setup panel,
/// for the same reason the settings screen is one: designing a voice means
/// reading several generations back to back and comparing them, which the
/// 320px panel cannot hold.
///
/// The screen is deliberately one surface with two halves. A design model is
/// stochastic — the same prose gives a different voice every time — so
/// generating is not a save. The upper panel composes, and the lower list holds
/// what was kept. Between them sits the draft: the clip just generated, on
/// screen, with the choice to keep it or throw it away still open.
class VoiceLibraryScreen extends StatefulWidget {
  const VoiceLibraryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<VoiceLibraryScreen> createState() => _VoiceLibraryScreenState();
}

class _VoiceLibraryScreenState extends State<VoiceLibraryScreen> {
  /// The prose being designed from. Local to this screen rather than shared
  /// with the run-setup panel: the two describe different things — a voice to
  /// be auditioned versus a voice to be generated — and a user comparing
  /// variations is working on the former.
  late final TextEditingController _instruct = TextEditingController(
    text: widget.controller.customVoices.designModel?.defaultInstruct ?? '',
  );

  /// Which clip is playing, if any. A row id for a saved clip, or [draftKey]
  /// for the one being auditioned.
  String? _playing;

  static const _draftKey = '__draft__';

  AudioPlayer? _player;

  AppController get _controller => widget.controller;

  CustomVoiceController get _voices => _controller.customVoices;

  @override
  void initState() {
    super.initState();
    _instruct.text = _voices.designModel?.defaultInstruct ?? '';
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _instruct.dispose();
    // Stopped rather than merely released: a player outliving the screen would
    // keep talking over whatever the user moves on to.
    unawaited(_player?.dispose());
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
    player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped && mounted) {
        setState(() => _playing = null);
      }
    });
    _player = player;
    return player;
  }

  /// Plays [source], or stops whichever clip is currently playing when [source]
  /// is that same one.
  ///
  /// A single toggle rather than one play and one stop button per row: there is
  /// only ever one clip audible, and a row that switches between the two words
  /// says which of them is currently true.
  Future<void> _togglePlay(String key, Source source) async {
    if (_playing == key) {
      await _player?.stop();
      return;
    }
    final player = await _ensurePlayer();
    try {
      await player.play(source);
    } on Exception {
      // A clip that cannot be played is not worth an error dialog: the user's
      // next move is probably to delete it, and the row is still there.
      if (mounted) setState(() => _playing = null);
      return;
    }
    if (mounted) setState(() => _playing = key);
  }

  Future<void> _stop() async {
    await _player?.stop();
  }

  Future<void> _generate() async {
    await _stop();
    await _voices.generate(_instruct.text);
    if (!mounted) return;
    // Played on arrival so the decision the screen exists for — keep or throw
    // away — can be made from what it sounds like, not from the name.
    final draft = _voices.draft;
    if (draft == null) return;
    await _togglePlay(_draftKey, BytesSource(Uint8List.fromList(draft.bytes)));
  }

  Future<void> _saveDraft() async {
    final l10n = AppLocalizations.of(context);
    final draft = _voices.draft;
    if (draft == null) return;
    final name = await showVoiceNameDialog(
      context,
      title: l10n.gui_voiceLibrary_saveNameTitle,
      label: l10n.gui_voiceLibrary_saveNameLabel,
      saveLabel: l10n.gui_voiceLibrary_save,
      fieldKey: const Key('saveVoiceNameField'),
      saveKey: const Key('saveVoiceDialogSaveButton'),
    );
    if (name == null) return;
    await _stop();
    _voices.saveDraft(name);
  }

  Future<void> _rename(CustomVoice voice) async {
    final l10n = AppLocalizations.of(context);
    final name = await showVoiceNameDialog(
      context,
      title: l10n.gui_voiceLibrary_renameTitle,
      label: l10n.gui_voiceLibrary_renameLabel,
      saveLabel: l10n.gui_voiceLibrary_save,
      fieldKey: const Key('renameVoiceNameField'),
      saveKey: const Key('renameVoiceDialogSaveButton'),
      initialName: voice.name.value,
    );
    if (name == null) return;
    _voices.rename(voice.id.value, name);
  }

  Future<void> _delete(CustomVoice voice) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.gui_voiceLibrary_deleteTitle),
        content: Text(l10n.gui_voiceLibrary_deleteMessage(voice.name.value)),
        actions: [
          CupertinoDialogAction(
            key: const Key('deleteVoiceCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.gui_voiceLibrary_cancel),
          ),
          CupertinoDialogAction(
            key: const Key('deleteVoiceConfirmButton'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.gui_voiceLibrary_delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_playing == voice.id.value) await _stop();
    _voices.delete(voice.id.value);
  }

  /// Adopts [voice] as the active run's reference clip and closes.
  ///
  /// Returns to the editor rather than staying put, because the point of the
  /// choice is the run that follows it. The run-setup panel is revealed on the
  /// way out so the reference clip it now points at is visible rather than a
  /// setting the user changed and cannot see.
  void _use(CustomVoice voice) {
    _controller.useCustomVoice(voice);
    if (!_controller.runSetupPanelVisible) {
      _controller.toggleRunSetupPanel();
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final library = _voices.library;

    return CupertinoPageScaffold(
      backgroundColor: tokens.colors.bgApp,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, l10n),
            if (_voices.error != null)
              _errorBanner(context, _voices.error!, tokens),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _designPanel(context, l10n, tokens),
                  if (_voices.draft case final draft?)
                    _draftCard(context, l10n, tokens, draft),
                  const SizedBox(height: 24),
                  if (library.isEmpty)
                    _emptyState(context, l10n, tokens)
                  else ...[
                    _sectionLabel(l10n.gui_voiceLibrary_savedTitle, tokens),
                    const SizedBox(height: 8),
                    for (final voice in library.voices)
                      _voiceRow(context, l10n, tokens, voice),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l10n) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.gui_voiceLibrary_title,
              style: tokens.typography.headerSemibold.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          AppButton(
            key: const Key('closeVoiceLibraryButton'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.gui_voiceLibrary_close),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(
    BuildContext context,
    String message,
    AppTokens tokens,
  ) {
    final l10n = AppLocalizations.of(context);
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.colors.accentError.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: tokens.typography.body.copyWith(
                  color: tokens.colors.accentError,
                ),
              ),
            ),
            AppButton(
              key: const Key('voiceLibraryDismissErrorButton'),
              compact: true,
              onPressed: _voices.clearError,
              child: Text(l10n.gui_voiceLibrary_cancel),
            ),
          ],
        ),
      );
  }

  Widget _designPanel(
    BuildContext context,
    AppLocalizations l10n,
    AppTokens tokens,
  ) {
    if (!_voices.canDesign) {
      return _note(context, tokens, l10n.gui_voiceLibrary_noDesignModels);
    }
    final model = _voices.designModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(l10n.gui_voiceLibrary_designSection, tokens),
        const SizedBox(height: 8),
        _label(l10n.gui_voiceLibrary_modelLabel, tokens),
        AppDropdown<String>(
          key: const Key('designVoiceModelDropdown'),
          value: model?.alias,
          items: [
            for (final profile in _voices.designModels)
              (profile.alias, profile.displayName ?? profile.alias),
          ],
          onChanged: _voices.selectDesignModel,
        ),
        if (_voices.designLanguageItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          _label(l10n.gui_voiceLibrary_languageLabel, tokens),
          AppDropdown<String>(
            key: const Key('designVoiceLanguageDropdown'),
            value: _voices.designLanguage,
            hint: l10n.gui_voiceLibrary_languageAny,
            items: [
              for (final (code, name) in _voices.designLanguageItems)
                (code, name),
            ],
            onChanged: _voices.selectDesignLanguage,
          ),
        ],
        const SizedBox(height: 12),
        _label(l10n.gui_voiceLibrary_instructLabel, tokens),
        AppTextField(
          key: const Key('designVoiceInstructField'),
          controller: _instruct,
          maxLines: 4,
          hintText: l10n.gui_voiceLibrary_instructHint,
        ),
        const SizedBox(height: 12),
        _passagePreview(context, l10n, tokens),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const Key('designVoiceGenerateButton'),
            style: AppButtonStyle.filled,
            icon: const Icon(CupertinoIcons.waveform, size: 18),
            onPressed: _voices.generating ? null : _generate,
            child: Text(
              _voices.generating
                  ? l10n.gui_voiceLibrary_generating
                  : l10n.gui_voiceLibrary_generate,
            ),
          ),
        ),
      ],
    );
  }

  /// The passage every voice is designed from, shown so it is not a mystery.
  ///
  /// Read-only rather than editable on purpose. Comparing two designs only
  /// means something if the words are identical and only the voice differs, so
  /// making it editable would invite a user to change the one variable that
  /// should be held still and then read nothing into the difference.
  Widget _passagePreview(
    BuildContext context,
    AppLocalizations l10n,
    AppTokens tokens,
  ) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _label(l10n.gui_voiceLibrary_passageLabel, tokens),
              ),
              Flexible(
                child: Text(
                  l10n.gui_voiceLibrary_passageHint,
                  style: tokens.typography.mono.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.colors.bgSurface,
              borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
            ),
            child: Text(
              kVoiceDesignPassage.trim(),
              key: const Key('voiceDesignPassagePreview'),
              style: tokens.typography.body.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ),
        ],
      );

  /// The clip just generated, with the decision it exists for still open.
  ///
  /// The prose is shown because the panel above stays editable while this is on
  /// screen, so the words in the panel may no longer be the ones that produced
  /// the clip being judged. Without the caption, "generate again" would look
  /// like it rolls the clip the user is looking at rather than the design.
  Widget _draftCard(
    BuildContext context,
    AppLocalizations l10n,
    AppTokens tokens,
    VoiceDraft draft,
  ) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.colors.bgSurface,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.gui_voiceLibrary_draftTitle,
                    style: tokens.typography.control.copyWith(
                      color: tokens.colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  l10n.gui_voiceLibrary_draftAttempts(draft.attempts),
                  style: tokens.typography.mono.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.gui_voiceLibrary_draftFrom(draft.instruct),
              key: const Key('voiceDraftInstructCaption'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.mono.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  key: const Key('voiceDraftPlayButton'),
                  compact: true,
                  icon: Icon(
                    _playing == _draftKey
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.play_fill,
                    size: 16,
                  ),
                  onPressed: () => _togglePlay(
                    _draftKey,
                    BytesSource(Uint8List.fromList(draft.bytes)),
                  ),
                  child: Text(
                    _playing == _draftKey
                        ? l10n.gui_voiceLibrary_stop
                        : l10n.gui_voiceLibrary_play,
                  ),
                ),
                // Plain rather than destructive: throwing a generation away is
                // the ordinary move, not a mistake to be confirmed.
                AppButton(
                  key: const Key('voiceDraftCancelButton'),
                  compact: true,
                  onPressed: () async {
                    await _stop();
                    _voices.discardDraft();
                  },
                  child: Text(l10n.gui_voiceLibrary_cancel),
                ),
                AppButton(
                  key: const Key('voiceDraftRegenerateButton'),
                  style: AppButtonStyle.outlined,
                  compact: true,
                  onPressed: _voices.generating ? null : _generate,
                  child: Text(l10n.gui_voiceLibrary_generateAgain),
                ),
                AppButton(
                  key: const Key('voiceDraftSaveButton'),
                  style: AppButtonStyle.filled,
                  compact: true,
                  onPressed: _voices.generating ? null : _saveDraft,
                  child: Text(l10n.gui_voiceLibrary_save),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _voiceRow(
    BuildContext context,
    AppLocalizations l10n,
    AppTokens tokens,
    CustomVoice voice,
  ) {
    final playing = _playing == voice.id.value;
    final usable = _controller.usesCustomVoices;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            voice.name.value,
            style: tokens.typography.control.copyWith(
              color: tokens.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.gui_voiceLibrary_designedWith(voice.designModel),
            style: tokens.typography.mono.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                key: Key('voicePlay_${voice.id.value}'),
                compact: true,
                icon: Icon(
                  playing
                      ? CupertinoIcons.stop_fill
                      : CupertinoIcons.play_fill,
                  size: 16,
                ),
                onPressed: () => _togglePlay(
                  voice.id.value,
                  DeviceFileSource(
                    _voices.clipPathFor(voice),
                  ),
                ),
                child: Text(
                  playing
                      ? l10n.gui_voiceLibrary_stop
                      : l10n.gui_voiceLibrary_play,
                ),
              ),
              AppButton(
                key: Key('voiceUse_${voice.id.value}'),
                style: AppButtonStyle.filled,
                compact: true,
                // Disabled rather than hidden, with the reason underneath:
                // a model that cannot take a clip is the common case here, and a
                // missing button would read as an empty library rather than as
                // a mismatch the user can fix in the panel.
                onPressed: usable ? () => _use(voice) : null,
                child: Text(l10n.gui_voiceLibrary_use),
              ),
              AppButton(
                key: Key('voiceVariation_${voice.id.value}'),
                style: AppButtonStyle.outlined,
                compact: true,
                // A new draft, never a re-roll of the saved clip: the voice the
                // user kept has to survive the temptation to improve on it.
                onPressed: () {
                  _instruct.text = voice.instruct;
                  _voices.seedVariation(voice);
                },
                child: Text(l10n.gui_voiceLibrary_newVariation),
              ),
              AppButton(
                key: Key('voiceRename_${voice.id.value}'),
                compact: true,
                onPressed: () => _rename(voice),
                child: Text(l10n.gui_voiceLibrary_rename),
              ),
              AppButton(
                key: Key('voiceDelete_${voice.id.value}'),
                compact: true,
                onPressed: () => _delete(voice),
                child: Text(l10n.gui_voiceLibrary_delete),
              ),
            ],
          ),
          if (!usable) ...[
            const SizedBox(height: 8),
            Text(
              l10n.gui_voiceLibrary_useUnavailable,
              style: tokens.typography.mono.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    AppLocalizations l10n,
    AppTokens tokens,
  ) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.gui_voiceLibrary_emptyTitle,
            style: tokens.typography.control.copyWith(
              color: tokens.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.gui_voiceLibrary_emptyCaption,
            style: tokens.typography.body.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ],
      );

  Widget _sectionLabel(String text, AppTokens tokens) => Text(
        text,
        style: tokens.typography.mono.copyWith(
          color: tokens.colors.textSecondary,
        ),
      );

  Widget _label(String text, AppTokens tokens) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: tokens.typography.body),
      );

  Widget _note(BuildContext context, AppTokens tokens, String text) => Text(
        text,
        style: tokens.typography.body.copyWith(
          color: tokens.colors.textSecondary,
        ),
      );
}