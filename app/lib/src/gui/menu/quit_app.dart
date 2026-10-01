import 'package:flutter/services.dart';

/// Ends the app process.
///
/// Shared by the Linux/Windows in-app File menu's Quit item and the matching
/// `Ctrl+Q` accelerator, so both quit through the same path.
///
/// [SystemNavigator.pop] asks the engine for an orderly window close rather than
/// calling `dart:io exit` directly: the embedded engine treats an
/// unrequested `exit` as a crash and pops a "report an issue" dialog on some
/// platforms.
void quitApp() => SystemNavigator.pop();
