// A DIAGNOSTIC THAT PRINTS ITS OWN SOURCE CODE IS NOT A DIAGNOSTIC.
//
// 🔴 THE DEFECT THIS GUARDS. The error-state work (SA-06) added a `debugPrint`
// beside every classified stream failure so the raw error survives for whoever
// has to diagnose it — the classified message is for the founder, the log line
// is for us. Five of them were written inside a single-quoted Dart string as
//
//     debugPrint('clients stream error: \$e');
//
// `\$` escapes the interpolation, so every one of those lines printed the
// literal text `$e` and the actual exception was discarded. The screens said
// "not authorized" or "missing index" correctly and the console log — the only
// place the underlying `FirebaseException` code and message existed — said
// nothing at all.
//
// The remaining 38 `debugPrint` calls in the console interpolate correctly, so
// this was a slip in one batch of edits, not a house style.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no debugPrint escapes its own interpolation', () {
    final offenders = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('debugPrint')) continue;
        // A backslash before `$` inside a debugPrint argument can only ever be
        // an escape — there is no reason to log a literal dollar sign here.
        if (RegExp(r'\\\$').hasMatch(line)) {
          offenders.add('${f.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these log lines print the literal text instead of the error:\n'
            '${offenders.join('\n')}');
  });

  test('the detector works — otherwise this suite is vacuous', () {
    expect(RegExp(r'\\\$').hasMatch(r"debugPrint('x: \$e');"), isTrue);
    expect(RegExp(r'\\\$').hasMatch(r"debugPrint('x: $e');"), isFalse);
  });

  // ── WIDENED 2026-09-09 (Superadmin ↔ Trainersarena E2E run) ───────────────
  //
  // The original guard only watched `debugPrint`. During this run a NEW chart
  // label was written as '\\${m.count}' and shipped to the browser rendering the
  // literal text, on a founder-facing screen — the same escape, one layer up,
  // where the audience is the operator instead of the log.
  //
  // `\\${` is never intentional: a literal dollar is written `\\$` and a literal
  // brace needs no escape. Anything matching it is an interpolation that will
  // print its own source.
  test('no string escapes an interpolated EXPRESSION anywhere in lib/', () {
    final offenders = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        // Comments explain the trap; they must not trip it.
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (RegExp(r'\\\$\{').hasMatch(line)) {
          offenders.add('${f.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these strings render their own source instead of the value:\n'
            '${offenders.join('\n')}');
  });
}
