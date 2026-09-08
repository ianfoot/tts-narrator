import 'dart:io';

import 'package:flutter/foundation.dart';

import '../theme/app_text_tokens.dart' show TextTokens;

/// Owns the in-memory document for the TTS Narrator GUI: the text, its backing
/// path, the dirty flag, and the save/load surface.
///
/// [AppController] forwards its document surface to this controller and
/// re-broadcasts notifications (the whole-file cap check lives there because it
/// also reads narration settings).
class DocumentController extends ChangeNotifier {
  String _text = '';
  String? _documentPath;
  bool _dirty = false;

  String get text => _text;

  /// Absolute path of the open document, or null for an in-memory `untitled`
  /// document.
  String? get documentPath => _documentPath;

  /// Whether the document has unsaved edits (load sets false; every text edit
  /// sets it true).
  bool get dirty => _dirty;

  String get documentName => _documentPath == null
      ? TextTokens.app_untitledDocument
      : _documentPath!.split(Platform.pathSeparator).last;

  /// Replaces the document text (typing/paste path). Marks the document dirty.
  void setText(String value) {
    if (value == _text) return;
    _text = value;
    _dirty = true;
    notifyListeners();
  }

  /// Loads a `.txt` document from [path], replacing the in-memory text. Clears
  /// the dirty flag. Throws a [FileSystemException] when the file is missing.
  void loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException(
        TextTokens.gui_controller_errors_cannotOpenTextFile,
        path,
      );
    }
    _text = file.readAsStringSync();
    _documentPath = file.absolute.path;
    _dirty = false;
    notifyListeners();
  }

  /// Resolves a destination for Save As (and the first save of an untitled
  /// document); returns null when the user cancels. Wired by the platform
  /// shell to the native save picker — platform-neutral so Linux/Windows bind
  /// their own picker.
  Future<String?> Function()? saveLocationPicker;

  /// Writes [text] to [path] and adopts it as the document: the dirty flag
  /// clears and future saves keep that path. Throws a [FileSystemException]
  /// when the file cannot be written.
  void saveTo(String path) {
    File(path).writeAsStringSync(_text);
    _documentPath = File(path).absolute.path;
    _dirty = false;
    notifyListeners();
  }

  /// Saves to the current document path, or prompts (via [saveAs]) when the
  /// document has not been saved yet. Swallows write errors the way the open
  /// path does.
  Future<void> save() async {
    if (_documentPath == null) {
      await saveAs();
      return;
    }
    try {
      saveTo(_documentPath!);
    } on FileSystemException {
      // Ignore write failures; the document stays dirty.
    }
  }

  /// Prompts for a save location and writes the text there, adopting the new
  /// path. The old path stays intact until the user confirms a location.
  Future<void> saveAs() async {
    final path = await saveLocationPicker?.call();
    if (path == null) return;
    try {
      saveTo(path);
    } on FileSystemException {
      // Ignore write failures; the document stays dirty.
    }
  }

  /// Non-whitespace words in the document.
  int get wordCount =>
      _text.trim().isEmpty ? 0 : _text.trim().split(RegExp(r'\s+')).length;

  int get charCount => _text.length;

  /// Clears the document text. Disabled (greyed) when no text to clear.
  /// Marks document dirty so the cleared state can be saved.
  void clearText() {
    if (_text.isEmpty) return;
    _text = '';
    _dirty = true;
    notifyListeners();
  }
}
