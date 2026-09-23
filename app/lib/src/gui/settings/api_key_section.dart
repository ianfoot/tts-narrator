import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_button.dart';
import '../platform/widgets/platform_disclosure.dart';
import '../platform/widgets/platform_text_field.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// The "API key" section of the settings rail: where the active model's key
/// comes from, a masked field to enter a new one, and Save / Remove buttons
/// backed by the OS secure store. The stored key is a fallback only — a key
/// already present in config.json or the environment keeps precedence (see
/// [SettingsController._resolveProviderSettings]). Wrapped in a collapsed
/// [PlatformDisclosure] so the key controls stay out of the way; the status
/// line serves as its caption.
class ApiKeySection extends StatefulWidget {
  const ApiKeySection({super.key, required this.controller});

  final AppController controller;

  @override
  State<ApiKeySection> createState() => _ApiKeySectionState();
}

class _ApiKeySectionState extends State<ApiKeySection> {
  late final TextEditingController _apiKey;

  /// Whether the API key disclosure is expanded. Collapsed by default so the
  /// key source/entry controls stay out of the way until opened.
  bool _apiKeyExpanded = false;

  /// Transient key-store failure shown under the API-key row (e.g. an
  /// unreachable keychain / Secret Service on save or remove).
  String? _apiKeyError;

  AppController get _controller => widget.controller;

  AppTokens get _tokens => AppTokens.of(context);

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _apiKey.dispose();
    super.dispose();
  }

  /// Clears a transient key-store failure once a key lands in the store.
  void _onControllerChanged() {
    if (_apiKeyError != null && _controller.hasStoredApiKey) {
      setState(() => _apiKeyError = null);
    }
  }

  /// Saves the entered key to the OS secure store and clears the visible
  /// field (the secret never lingers in the edit box). Empty input is a no-op.
  /// A key-store failure leaves the field populated and reports it on the
  /// status row instead of surfacing as an unhandled async error.
  Future<void> _saveApiKey() async {
    if (_apiKey.text.trim().isEmpty) return;
    try {
      await _controller.saveApiKey(_apiKey.text);
    } catch (_) {
      setState(() => _apiKeyError = TextTokens.gui_settings_apiKeyStoreError);
      return;
    }
    _apiKey.clear();
    setState(() => _apiKeyError = null);
  }

  /// Removes the stored key and clears the visible field.
  Future<void> _removeApiKey() async {
    try {
      await _controller.removeApiKey();
    } catch (_) {
      setState(() => _apiKeyError = TextTokens.gui_settings_apiKeyStoreError);
      return;
    }
    _apiKey.clear();
    setState(() => _apiKeyError = null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: PlatformDisclosure(
        key: const Key('apiKeyDisclosure'),
        label: TextTokens.gui_settings_apiKeySection,
        tooltip: TextTokens.gui_settings_apiKeySectionTooltip,
        caption: _controller.apiKeyStatusLabel,
        expanded: _apiKeyExpanded,
        onToggle: (value) => setState(() => _apiKeyExpanded = value),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingsFieldLabel(
              _tokens,
              TextTokens.gui_settings_apiKeyStatusLabel,
            ),
            Text(
              _controller.apiKeyStatusLabel,
              style: _tokens.typography.body.copyWith(
                color: _controller.apiKeyMissing
                    ? _tokens.colors.accentError
                    : _tokens.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            PlatformTextField(
              key: const Key('apiKeyField'),
              tooltip: TextTokens.gui_settings_apiKeyFieldTooltip,
              controller: _apiKey,
              obscureText: true,
              hintText: TextTokens.gui_settings_apiKeyFieldPlaceholder,
              hintStyle: _tokens.typography.body.copyWith(
                color: _tokens.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlatformButton(
                  key: const Key('apiKeySaveButton'),
                  onPressed: () => _saveApiKey(),
                  child: Text(TextTokens.gui_settings_apiKeySave),
                ),
                const SizedBox(width: 8),
                PlatformButton(
                  key: const Key('apiKeyRemoveButton'),
                  style: PlatformButtonStyle.outlined,
                  onPressed: _controller.hasStoredApiKey ? _removeApiKey : null,
                  child: Text(TextTokens.gui_settings_apiKeyRemove),
                ),
              ],
            ),
            if (_apiKeyError != null) ...[
              const SizedBox(height: 8),
              Text(
                _apiKeyError!,
                style: _tokens.typography.body.copyWith(
                  color: _tokens.colors.accentError,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
