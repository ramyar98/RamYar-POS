import 'dart:io';

import 'package:flutter/foundation.dart';

/// True while the code is running inside a `flutter test` process.
///
/// Widget and unit tests drive real code, and some of that code opens real
/// sockets, reads real files and schedules real timers. The flutter_test binding
/// fails a test that ends with those still pending, so the affected startup
/// paths check this first and stay out of the way.
///
/// Lives in its own file so both the settings store and the sync layer can ask
/// the question without importing each other.
bool get isRunningUnderTest {
  if (kIsWeb) return false;
  try {
    return Platform.environment['FLUTTER_TEST'] == 'true';
  } catch (_) {
    return false;
  }
}
