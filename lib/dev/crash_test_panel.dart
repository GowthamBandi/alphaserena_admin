// lib/dev/crash_test_panel.dart
//
// CONTROLLED CRASH TRIGGERS — INTERNAL BUILDS ONLY.
//
// The observability pipeline cannot be certified without forcing a real
// fatal, a real uncaught-async error and a real non-fatal through the actual
// handlers of the actual build. But a reachable "crash the console" control
// in a production build is a defect. The gate is therefore a COMPILE-TIME
// dart-define:
//
//   flutter run/build web --dart-define=CRASH_TEST=true
//
// A normal production build never passes the define, so `kCrashTestEnabled`
// is `const false` and this panel — triggers included — is tree-shaken out of
// the artifact entirely. That is stronger than kDebugMode alone: it also lets
// an INTERNAL RELEASE build (define passed explicitly) exercise the pipeline
// in true release mode, which kDebugMode-gating would make impossible.
// `test/crash_pipeline_contract_test.dart` pins the default to false.
import 'package:flutter/material.dart';

import '../core/utils/crash_reporter.dart';

/// Compile-time gate. False unless the build was made with
/// `--dart-define=CRASH_TEST=true`.
const bool kCrashTestEnabled = bool.fromEnvironment('CRASH_TEST');

/// Floating diagnostics panel offering the three controlled failures the
/// certification requires. Renders nothing when the gate is off.
class CrashTestPanel extends StatelessWidget {
  const CrashTestPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kCrashTestEnabled) return const SizedBox.shrink();
    return Positioned(
      right: 12,
      bottom: 12,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          // A Positioned pinned only right+bottom gives its child UNBOUNDED
          // width, and `CrossAxisAlignment.stretch` under unbounded width is
          // "BoxConstraints forces an infinite width" — found live on the
          // E2E run. The panel therefore fixes its own width.
          child: SizedBox(
            width: 180,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'CRASH TEST (internal build)',
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
              const SizedBox(height: 6),
              _btn('Fatal (sync)', () {
                CrashReporter.breadcrumb('CRASH_TEST_FATAL_SYNC');
                throw StateError('CONTROLLED TEST: synchronous fatal');
              }),
              _btn('Fatal (async)', () {
                CrashReporter.breadcrumb('CRASH_TEST_FATAL_ASYNC');
                // Deliberately un-awaited and un-caught: this must reach the
                // guarded zone's onError, not any local handler.
                Future<void>.delayed(
                  const Duration(milliseconds: 50),
                  () => throw StateError('CONTROLLED TEST: uncaught async'),
                );
              }),
              _btn('Non-fatal', () {
                CrashReporter.breadcrumb('CRASH_TEST_NONFATAL');
                try {
                  throw const FormatException(
                    'CONTROLLED TEST: handled failure',
                  );
                } catch (e, s) {
                  CrashReporter.reportNonFatal('crash-test non-fatal', e, s);
                }
              }),
            ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _btn(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    ),
  );
}
