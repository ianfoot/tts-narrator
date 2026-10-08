import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';

/// Ends the app process. `required` is non-cancelable, matching what Quit
/// means.
void quitApp() {
  unawaited(ServicesBinding.instance.exitApplication(AppExitType.required));
}
