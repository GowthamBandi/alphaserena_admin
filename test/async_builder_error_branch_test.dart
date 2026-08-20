// AN ASYNC BUILDER WITH NO ERROR BRANCH RENDERS THE FAILURE AS SOMETHING ELSE.
//
// 🔴 THE DEFECT THIS GUARDS. `automation_screen.dart` consumes two streams from
// the same service. The RULES stream branches on `snap.hasError`; the RUNS
// stream does not — it tests `if (!snap.hasData)` and shows a spinner. On a
// stream error `hasError` is true and `hasData` stays false forever, so the
// automation activity panel span an INFINITE spinner rather than reporting
// that it could not read `automation_runs`.
//
// The organization detail dialog's audit `FutureBuilder` had the same shape in
// the other direction: no error branch, `snap.data ?? []`, and the failure
// rendered as "No recorded platform actions for this organization yet."
//
// Both are the same rule: LOADING, FAILED and EMPTY are three different
// answers, and an async builder that only knows two of them will report one of
// the others in place of the failure. This guard pins the rule for every
// StreamBuilder and FutureBuilder in the console so the next one added cannot
// quietly re-open it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `//` and `/* */` stripper — a builder mentioned in prose must not
/// satisfy or trip this guard.
String codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final rest = source.substring(i);
    if (rest.startsWith('//')) {
      final nl = source.indexOf('\n', i);
      i = nl == -1 ? source.length : nl;
      continue;
    }
    if (rest.startsWith('/*')) {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
      continue;
    }
    i++;
    out.write(source[i - 1]);
  }
  return out.toString();
}

final _builder = RegExp(r'(Stream|Future)Builder<');

void main() {
  test('the stripper works — otherwise every assertion below is vacuous', () {
    expect(codeOnly('// StreamBuilder<X>\nvar a = 1;'),
        isNot(matches(_builder)));
    expect(codeOnly('StreamBuilder<X>('), matches(_builder));
  });

  test('every StreamBuilder / FutureBuilder branches on failure', () {
    final offenders = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = codeOnly(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!_builder.hasMatch(lines[i])) continue;
        // The builder body follows the declaration. 40 lines is generous for
        // the state triage, which is always written first.
        final window = lines
            .sublist(i, (i + 40).clamp(0, lines.length))
            .join('\n');
        final handles = window.contains('hasError') ||
            // A record/result type that carries its own classified error is
            // the other accepted shape (see `_loadOrgAudit`).
            window.contains('.error');
        if (!handles) {
          offenders.add('${f.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these async builders cannot tell FAILED from LOADING or '
            'EMPTY, so a failure renders as a spinner or as an empty state:\n'
            '${offenders.join('\n')}');
  });
}
