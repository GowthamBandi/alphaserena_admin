import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Release identity attached to every fatal report.
///
/// Pin it exactly at build time:
///   flutter build web \
///     --dart-define=APP_VERSION=1.0.0+1 \
///     --dart-define=GIT_COMMIT=$(git rev-parse --short HEAD)
///
/// The default is pinned to pubspec.yaml by
/// `test/build_info_matches_pubspec_test.dart` — a stale default would
/// misattribute every crash to the wrong release.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0+1',
);

/// Short git SHA when supplied via --dart-define. Defaults to `unknown` rather
/// than a hardcoded SHA: a wrong commit sends a reader to the wrong diff.
const String kGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'unknown',
);

String get buildMode => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

String get buildIdentity => '$kAppVersion ($kGitCommit) $buildMode';

/// The sink fatal reports are written to. Swappable so a test can observe a
/// report without reading the platform console — and so a real crash-reporting
/// backend can be attached at one seam rather than at every call site.
typedef FatalSink =
    void Function(String label, Object error, StackTrace? stack);

void _defaultSink(String label, Object error, StackTrace? stack) {
  // `dart:developer`, NOT `debugPrint`. A crash report is not diagnostic
  // chatter: it is the one message that must survive log hygiene. It carries
  // the exception and its stack and nothing the app chose to log.
  developer.log(
    '[$buildIdentity] $label: $error',
    name: 'alphaserena.admin.fatal',
    error: error,
    stackTrace: stack,
    level: 1000, // SEVERE
  );
}

FatalSink _sink = _defaultSink;

/// Reports an unrecoverable error through a channel release builds keep.
void reportFatal(String label, Object error, [StackTrace? stack]) {
  try {
    _sink(label, error, stack);
  } catch (_) {
    // The reporter must never be the thing that takes the app down.
  }
}

/// Test seam. Returns the previous sink so a test can restore it.
@visibleForTesting
FatalSink setFatalSinkForTest(FatalSink sink) {
  final previous = _sink;
  _sink = sink;
  return previous;
}
