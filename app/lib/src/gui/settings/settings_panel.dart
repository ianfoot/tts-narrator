import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'api_key_section.dart';
import 'model_options_section.dart';
import 'model_voice_section.dart';
import 'run_section.dart';

/// Left-side settings rail beside the editor: model & voice, styling, and run
/// options. Every control writes straight to [AppController], which notifies
/// the editor so the status-bar estimate stays live. The rail is hidden via the
/// editor toolbar's toggle; narration is initiated from the toolbar, not here.
///
/// A thin composition root: each section is its own widget owning its local
/// controls and syncing back from the controller.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      key: const Key('settingsPanel'),
      width: AppMetrics.railWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: tokens.colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Text(
              TextTokens.gui_settings_header,
              style: tokens.typography.headerSemibold.copyWith(
                color: tokens.colors.accentPrimary,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                ModelVoiceSection(controller: controller),
                // Model options are declared by the active model's plugin (the
                // provider package); the app has no per-model UI knowledge.
                // The section renders nothing when no options are declared.
                ModelOptionsSection(controller: controller),
                ApiKeySection(controller: controller),
                RunSection(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
