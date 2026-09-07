// Golden test for the design-token codegen.
//
// Regenerates `app/lib/src/gui/theme/app_tokens.g.dart` from the
// `app/assets/theme/tokens.json` source of truth and asserts the output is
// byte-identical to the checked-in file. A failure here means somebody
// edited the JSON (or the generator) and forgot to commit the regenerated
// `.g.dart` — or the generator isn't producing deterministic output.
//
// The test invokes the generator in a child `dart` process so the codegen
// runs in the same configuration as `dart run tool/generate_tokens.dart`
// from the command line.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('codegen output is byte-identical to the checked-in .g.dart', () async {
    final appRoot = _appRoot();
    final script = p.join(appRoot, 'tool', 'generate_tokens.dart');
    final tokensJson = File(p.join(appRoot, 'assets', 'theme', 'tokens.json'));
    final golden = File(
      p.join(appRoot, 'lib', 'src', 'gui', 'theme', 'app_tokens.g.dart'),
    );

    if (!File(script).existsSync()) {
      fail('Codegen script not found at $script');
    }
    if (!tokensJson.existsSync()) {
      fail('tokens.json not found at ${tokensJson.path}');
    }
    if (!golden.existsSync()) {
      fail('Golden .g.dart not found at ${golden.path}');
    }

    final temp = Directory.systemTemp.createTempSync('tts_tokens_codegen_');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    // Mirror the package layout: the codegen reads
    // <TOKENS_PACKAGE_ROOT>/assets/theme/tokens.json and writes
    // <TOKENS_PACKAGE_ROOT>/lib/src/gui/theme/app_tokens.g.dart.
    final assetsDir = Directory(p.join(temp.path, 'assets', 'theme'))
      ..createSync(recursive: true);
    tokensJson.copySync(p.join(assetsDir.path, 'tokens.json'));

    final result = await Process.run(
      _resolveDartBinary(),
      ['run', script],
      workingDirectory: appRoot,
      environment: {...Platform.environment, 'TOKENS_PACKAGE_ROOT': temp.path},
    );

    if (result.exitCode != 0) {
      fail(
        'Codegen failed (exit ${result.exitCode}).\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }

    final produced = File(
      p.join(temp.path, 'lib', 'src', 'gui', 'theme', 'app_tokens.g.dart'),
    );
    if (!produced.existsSync()) {
      fail('Codegen did not produce ${produced.path}.');
    }

    final expected = golden.readAsStringSync();
    final actual = produced.readAsStringSync();

    if (expected != actual) {
      fail(
        'Codegen output drifted from the checked-in app_tokens.g.dart.\n'
        'Re-run `dart run tool/generate_tokens.dart` and commit the result.\n'
        'First divergence (expected vs actual):\n${_firstDiff(expected, actual)}',
      );
    }
  });
}

String _appRoot() {
  // `flutter test` runs with the package's root as the working directory.
  return Directory.current.path;
}

String _resolveDartBinary() {
  final fromEnv = Platform.environment['DART_BIN'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  const candidates = [
    '/Users/ian/fvm/versions/3.47.1/bin/dart',
    '/opt/homebrew/bin/dart',
    '/usr/local/bin/dart',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}

/// Returns a short context snippet around the first byte where [a] and [b]
/// differ, with a caret marking the divergence.
String _firstDiff(String a, String b) {
  final len = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < len && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  final start = (i - 40).clamp(0, a.length);
  final aEnd = (i + 40).clamp(0, a.length);
  final bEnd = (i + 40).clamp(0, b.length);
  final aSnippet = a.substring(start, aEnd);
  final bSnippet = b.substring(start, bEnd);
  return 'expected @ $start:\n  $aSnippet\n'
      'actual @ $start:\n  $bSnippet\n'
      '  ${' ' * (i - start)}^';
}
