import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../platform/widgets/platform_slider.dart';
import '../theme/app_text_tokens.dart' show TextTokens;
import '../theme/app_tokens.dart';
import 'settings_labels.dart';

/// A speech-rate slider bound to the controller's `speed` setting. Rendered for
/// models whose plugin declares a `speed` model option (e.g. kokoro); the value
/// readout mirrors the min-words badge so the current rate stays visible under
/// the macOS track-scaled knob.
class SpeedWidget extends StatelessWidget {
  const SpeedWidget({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsFieldLabel(tokens, TextTokens.gui_settings_speedLabel),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PlatformSlider(
                key: const Key('speedSlider'),
                tooltip: TextTokens.gui_settings_speedTooltip,
                value: controller.speed,
                onChanged: (v) => controller.speed = v,
                min: 0.25,
                max: 2.0,
                divisions: 35,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              key: const Key('speedBadge'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.colors.bgSurfaceElevated,
                borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
              ),
              child: Text(
                '${controller.speed.toStringAsFixed(2)}×',
                style: tokens.typography.mono,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
