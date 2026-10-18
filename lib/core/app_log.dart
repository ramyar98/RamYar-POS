import 'package:flutter/foundation.dart';

/// The one gate every log line in the app goes through.
///
/// In debug builds these lines trace the sync, discovery and socket layers
/// while developing. In release builds - on the iPad, the phone and the
/// laptop - nothing reaches the console at all: no log spam, no churn, and
/// nothing for a customer to see. Errors that matter reach the user through
/// the UI instead of the console.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message, wrapWidth: 2048);
  }
}