import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

import 'src/gui/controller/app_controller.dart';
import 'src/gui/platform/app_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);
  runApp(AppRoot(controller: AppController(prefs: prefs)));
}