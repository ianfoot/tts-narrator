import 'package:flutter/material.dart';
import 'package:tts_narrator_core/tts_narrator_core.dart';
import 'package:tts_narrator_openrouter/openrouter_tts_provider.dart';

import 'src/gui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ttsProviderRegistry.register('openrouter', OpenRouterTtsProvider.new);
  runApp(const TtsNarratorApp());
}