/// Prints the HTTP request the TTS client sends, as a curl you can paste into a
/// terminal and re-run against the same server.
///
/// Off unless the app is compiled with
/// `--dart-define=tts.debug_http=true`. An api key is never printed.
library;

/// Whether [logHttpRequest] and [logHttpResponse] print anything. A `const` from
/// a dart define, so a build that was not passed one cannot log at all.
const bool kHttpDebugEnabled = bool.fromEnvironment('tts.debug_http');

/// The curl that reproduces [body] sent to [uri], as one pasteable line.
String formatCurl({
  required Uri uri,
  required String body,
  String? apiKey,
}) {
  final key = apiKey?.trim() ?? '';
  final buffer = StringBuffer('curl -X POST ')
    ..write(_shellQuote(uri.toString()))
    ..write(" -H 'Content-Type: application/json'");
  if (key.isNotEmpty) {
    buffer.write(" -H 'Authorization: Bearer ***'");
  }
  buffer
    ..write(' -d ')
    ..write(_shellQuote(body));
  if (key.isNotEmpty) {
    buffer.write(' # api_key withheld; add -H with a Bearer token to re-run');
  }
  return buffer.toString();
}

/// Prints the curl for a request about to be sent, if [kHttpDebugEnabled].
void logHttpRequest({
  required Uri uri,
  required String body,
  String? apiKey,
}) {
  if (!kHttpDebugEnabled) return;
  print('[tts.http] request:');
  print(formatCurl(uri: uri, body: body, apiKey: apiKey));
}

/// Prints a one-line summary of what came back, if [kHttpDebugEnabled].
void logHttpResponse({
  required int statusCode,
  required int byteCount,
  String? contentType,
  String? generationId,
}) {
  if (!kHttpDebugEnabled) return;
  final buffer = StringBuffer('[tts.http] <- $statusCode');
  final type = contentType?.trim() ?? '';
  if (type.isNotEmpty) {
    buffer.write(' $type');
  }
  buffer.write(' $byteCount bytes');
  final id = generationId?.trim() ?? '';
  if (id.isNotEmpty) {
    buffer.write(' gen=$id');
  }
  print(buffer);
}

/// Wraps [value] in single quotes for a POSIX shell, `'` becoming `'\''`.
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";