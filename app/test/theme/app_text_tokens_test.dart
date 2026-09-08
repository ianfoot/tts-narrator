import 'package:flutter_test/flutter_test.dart';

import 'package:tts_narrator/src/gui/theme/app_text_tokens.dart';

void main() {
  group('TextTokens', () {
    test('regular tokens resolve to their literal values', () {
      expect(TextTokens.app_title, 'TTS Narrator');
      expect(TextTokens.gui_settings_header, 'Settings');
      expect(TextTokens.gui_menu_narrate, 'Narrate');
      expect(TextTokens.defaults_minWords, 30);
    });

    test('templated tokens keep placeholders literal', () {
      expect(TextTokens.gui_narration_narratingTitle, 'Narrating: \$documentName');
      expect(
        TextTokens.gui_cleanup_removedMessage,
        'Removed \$removedCount segment \$fileWord.',
      );
    });
  });

  group('fillTextTemplate', () {
    test('fills \$name and \${name} placeholders from the value map', () {
      expect(
        fillTextTemplate(TextTokens.gui_narration_narratingTitle, {
          'documentName': 'story.txt',
        }),
        'Narrating: story.txt',
      );
      expect(
        fillTextTemplate(TextTokens.gui_narration_summaryPill, {
          'modelName': 'fish',
          'voice': '89f41ea2…',
          'segments': 3,
          'segmentLabel': 'segments',
          'minutes': 2,
          'cost': r'$0.00 (free)',
        }),
        'fish · 89f41ea2… | 3 segments · ~2 mins · ~\$0.00 (free)',
      );
    });

    test('leaves unknown or null placeholders untouched', () {
      expect(
        fillTextTemplate(TextTokens.gui_editor_cannotNarratePrefix, {}),
        'Cannot narrate: \$message',
      );
      expect(
        fillTextTemplate(TextTokens.gui_editor_cannotNarratePrefix, {
          'message': null,
        }),
        'Cannot narrate: \$message',
      );
    });

    test('is a no-op for empty templates or value maps', () {
      expect(fillTextTemplate('', {'x': 'y'}), '');
      expect(fillTextTemplate('plain text', {}), 'plain text');
    });

    test('an unescaped trailing dollar is preserved', () {
      expect(fillTextTemplate('cost: \$', {}), 'cost: \$');
    });
  });
}