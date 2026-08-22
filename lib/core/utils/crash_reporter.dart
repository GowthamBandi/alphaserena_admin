// lib/core/utils/crash_reporter.dart
//
// PRODUCTION CRASH CAPTURE FOR A FLUTTER *WEB* CONSOLE.
//
// Firebase Crashlytics does not exist on Flutter web (firebase_crashlytics
// 5.x supports Android / iOS / macOS only), and this console's ONLY registered
// Firebase app is the web app — the android/ios folders are unregistered
// `com.example` scaffolding. Installing the Crashlytics plugin here would
// instrument builds nobody runs and capture zero production crashes.
//
// This module is therefore the web-native equivalent, attached behind the
// SAME seam every error already flows through (`reportFatal` in
// fatal_reporter.dart): reports are persisted to the founder-only Firestore
// collection `console_crash_reports` (rules: super-admin create/read only,
// update/delete denied for everyone), carrying the build identity, a
// fatal/non-fatal classification, a breadcrumb trail, and a sanitized error +
// stack. The founder reads them in the Firebase console.
//
// HARD RULES THIS FILE ENFORCES, IN CODE, NOT IN COMMENTS:
//  • Reporting can NEVER take the app down — every path is try/caught and
//    fire-and-forget. The reporter must not await anything on a crash path.
//  • Nothing sensitive leaves the app: error text and breadcrumbs pass
//    through `redact()` (passwords, bearer tokens, JWTs, API keys, emails),
//    and breadcrumb NAMES are the only breadcrumb payload that exists —
//    the API refuses arbitrary prose, so a form value cannot sneak in.
//  • A crash loop cannot flood the backend: per-signature and per-session
//    caps drop repeats client-side (update rules are closed, so repeat
//    counting is a client concern by design).
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'fatal_reporter.dart';

/// How a report is classified in `console_crash_reports.kind`.
///
/// `fatal`    — reached the global handlers (FlutterError.onError or the
///              guarded zone): nothing downstream handled it.
/// `nonfatal` — explicitly recorded by code that caught the error and kept
///              the console alive, but judged the failure worth a report.
enum CrashKind { fatal, nonfatal }

/// A report about to be persisted. Exposed so tests can assert on the exact
/// document that would be written.
typedef CrashDocWriter = Future<void> Function(Map<String, dynamic> doc);

/// Compiled once; applied to error text, stack text and (defensively) crumbs.
///
/// Order matters, and the first test run proved it: SPECIFIC token shapes
/// must run before the broad keyword rule. `Authorization: Bearer <token>`
/// under keyword-first redacted the word "Bearer" and LEFT THE TOKEN — the
/// keyword rule's `\S+` consumes exactly one word.
final List<(RegExp, String)> _redactions = [
  // Bearer <anything> — before the keyword rule, see above.
  (RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer [redacted]'),
  // JWTs (three base64url segments)
  (
    RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
    '[jwt-redacted]',
  ),
  // Google API keys
  (RegExp(r'AIza[0-9A-Za-z_-]{35}'), '[apikey-redacted]'),
  // password=..., pwd: ..., secret=..., token: ..., authorization=...
  (
    RegExp(
      r'''(password|passwd|pwd|secret|token|authorization|api[_-]?key)(["']?\s*[:=]\s*)(\S+)''',
      caseSensitive: false,
    ),
    r'$1$2[redacted]',
  ),
  // Email addresses — FirebaseAuthException messages embed the typed email.
  (RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '[email-redacted]'),
];

/// Strips credential- and identity-shaped substrings from text that is about
/// to leave the app. Public so the privacy regression test exercises the real
/// function, not a copy.
String redact(String text) {
  var out = text;
  for (final (re, replacement) in _redactions) {
    out = out.replaceAllMapped(re, (m) {
      if (replacement.contains(r'$1')) {
        return replacement
            .replaceAll(r'$1', m.group(1) ?? '')
            .replaceAll(r'$2', m.group(2) ?? '');
      }
      return replacement;
    });
  }
  return out;
}

/// Breadcrumb names must be STABLE EVENT NAMES, not prose. This is the whole
/// privacy story for breadcrumbs: a name that cannot hold spaces or
/// lowercase free text cannot hold a password either.
final RegExp _crumbName = RegExp(r'^[A-Z][A-Z0-9_]{2,47}$');

class CrashReporter {
  CrashReporter._();

  static const int maxBreadcrumbs = 40;
  static const int maxReportsPerSession = 25;
  static const int maxPerSignature = 3;
  static const int _maxPending = 5;

  static CrashDocWriter? _writer;
  static bool _emulator = false;
  static String? _uid;
  static String _section = 'boot';

  static final List<String> _crumbs = <String>[];
  static final Map<String, int> _seen = <String, int>{};
  static final List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  static int _sent = 0;
  static final String _sessionId =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      math.Random().nextInt(1 << 20).toRadixString(36);

  /// Attaches the persistence writer (production: a Firestore `add` on
  /// `console_crash_reports`). Also flushes anything reported before the
  /// writer existed — a crash during Firebase init is buffered and lands on
  /// the retry that succeeds.
  static void install(CrashDocWriter writer, {required bool emulatorMode}) {
    _writer = writer;
    _emulator = emulatorMode;
    final queued = List<Map<String, dynamic>>.of(_pending);
    _pending.clear();
    for (final doc in queued) {
      _dispatch(doc);
    }
  }

  /// The founder's uid — a stable internal identifier. NEVER the email.
  static void setUser(String? uid) => _uid = uid;

  /// The console section in view; nav indices are meaningless in a report.
  static void setSection(String name) => _section = name;

  /// Records a stable, named event. Rejects anything that is not a
  /// SCREAMING_SNAKE name — in debug builds loudly, in release by dropping it.
  static void breadcrumb(String name) {
    assert(
      _crumbName.hasMatch(name),
      'Breadcrumb "$name" is not a stable SCREAMING_SNAKE event name',
    );
    if (!_crumbName.hasMatch(name)) return;
    final ts = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    _crumbs.add('$ts $name');
    if (_crumbs.length > maxBreadcrumbs) _crumbs.removeAt(0);
  }

  /// Non-fatal: code caught the error, the console survived, and the failure
  /// is important enough to be visible in production.
  static void reportNonFatal(String label, Object error, [StackTrace? stack]) {
    _report(CrashKind.nonfatal, label, error, stack);
  }

  /// The [FatalSink] wired behind `reportFatal` — the two global handlers
  /// (FlutterError.onError, the guarded zone) both end here.
  static void handleFatal(String label, Object error, StackTrace? stack) {
    _report(CrashKind.fatal, label, error, stack);
  }

  static void _report(
    CrashKind kind,
    String label,
    Object error,
    StackTrace? stack,
  ) {
    try {
      final errorText = redact(_clip(error.toString(), 4000));
      final stackText = stack == null ? null : redact(_clip('$stack', 30000));

      // Crash-loop protection. The signature is the label plus the error's
      // TYPE and first stack frame — message text is excluded so a loop that
      // embeds a changing value (a timestamp, an id) still deduplicates.
      final firstFrame = stackText?.split('\n').firstOrNull ?? '';
      final signature = '$kind|$label|${error.runtimeType}|$firstFrame';
      final n = (_seen[signature] ?? 0) + 1;
      _seen[signature] = n;
      if (n > maxPerSignature) return;
      if (_sent >= maxReportsPerSession) return;

      final doc = <String, dynamic>{
        'kind': kind.name,
        'label': _clip(label, 120),
        'error': errorText,
        if (stackText != null) 'stack': stackText,
        'breadcrumbs': List<String>.of(_crumbs),
        'build': kAppVersion,
        'commit': kGitCommit,
        'mode': buildMode,
        'env': _emulator ? 'emulator' : 'production',
        if (_uid != null) 'uid': _uid,
        'section': _section,
        'sessionId': _sessionId,
        'occurrence': n,
      };
      _dispatch(doc);
    } catch (_) {
      // The reporter must never be the thing that takes the app down.
    }
  }

  static void _dispatch(Map<String, dynamic> doc) {
    final writer = _writer;
    if (writer == null) {
      if (_pending.length < _maxPending) _pending.add(doc);
      return;
    }
    _sent++;
    // Fire-and-forget: a crash path must never await the network, and an
    // offline write queues inside the Firestore SDK without blocking.
    // A failed write falls back to the developer log so the report is never
    // silently lost — it is just not remote.
    writer(doc).catchError((Object e) {
      developer.log(
        'crash report write failed: $e',
        name: 'alphaserena.admin.fatal',
        level: 900,
      );
    });
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…[clipped]';

  /// Test seams — state is static because the app has exactly one reporter.
  @visibleForTesting
  static void resetForTest() {
    _writer = null;
    _emulator = false;
    _uid = null;
    _section = 'boot';
    _crumbs.clear();
    _seen.clear();
    _pending.clear();
    _sent = 0;
  }

  @visibleForTesting
  static List<String> get debugBreadcrumbs => List.unmodifiable(_crumbs);
}
