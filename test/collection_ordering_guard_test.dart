// A CONSOLE LIST MUST NOT DROP THE DOCUMENTS ITS OWN DASHBOARD COUNTS.
//
// 🔴 THE DEFECT THIS GUARDS. Four screens streamed a whole collection with
// `.orderBy('createdAt', descending: true)`. Firestore excludes every document
// where the ordered field is ABSENT — so any organization, trainer, member or
// payment written without `createdAt` was invisible to that screen while the
// Dashboard, which reads the same collections unordered (and by `count()`
// aggregate for headcounts), still counted it.
//
// Proven in the Firestore emulator against the shipped queries:
//   • admins  — Dashboard 2, Organizations screen 1
//   • admin_payments_history — Dashboard ₹14,998, Payments screen ₹4,999
//
// The console already knew this: `platform_staff_controller` refuses `orderBy`
// in a comment for exactly this reason. The fix applies that same house rule to
// the other four, sorting in Dart instead.
//
// ⚠️ WHY THE COMMENTS ARE STRIPPED FIRST. Each fixed controller now DOCUMENTS
// the `orderBy` it deliberately does not perform. A naive substring search
// would fail on the very comment that prevents the relapse — which is how a
// guard gets deleted for crying wolf. Only CODE is inspected.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Removes `//` line comments and `/* */` block comments, leaving code.
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

/// A `.orderBy(` call naming [field], ignoring whitespace and quote style.
final _orderByCreatedAt = RegExp(r'''\.orderBy\(\s*['"]createdAt['"]''');

void main() {
  String code(String path) => codeOnly(File(path).readAsStringSync());

  test('the comment stripper works — otherwise every assertion is vacuous', () {
    expect(codeOnly('// x\nkeep;').trim(), 'keep;');
    expect(codeOnly('/* x */keep;'), 'keep;');
    expect(
      codeOnly("// .orderBy('createdAt')\nvar a = 1;"),
      isNot(matches(_orderByCreatedAt)),
    );
  });

  /// The four collections whose documents predate a consistent `createdAt`.
  /// Each is written by more than one producer across three apps and a
  /// backend, so absence is a real state, not a hypothetical.
  const unorderedStreams = {
    'lib/controllers/admin_controller.dart': 'admins (Organizations)',
    'lib/controllers/trainer_controller.dart': 'trainers',
    'lib/controllers/client_controller.dart': 'clients (Members)',
    'lib/controllers/payments_controller.dart': 'admin_payments_history',
  };

  for (final entry in unorderedStreams.entries) {
    test('${entry.value}: the stream does not orderBy createdAt', () {
      expect(
        code(entry.key),
        isNot(contains(RegExp(_orderByCreatedAt.pattern))),
        reason:
            'ordering ${entry.value} server-side silently drops every document '
            'without createdAt — the Dashboard counts them, this screen would '
            'not list them. Sort in Dart instead.',
      );
    });
  }

  test('the guard is not a blanket ban — audit_logs still orders server-side',
      () {
    // `audit_logs` is written ONLY by the backend's writeAudit, which always
    // stamps createdAt, and its window is a `limit()` that REQUIRES a server
    // order. Pinning it here proves this guard is about absent fields, not
    // about orderBy, so nobody "fixes" the audit log by removing its order.
    expect(
      code('lib/controllers/audit_controller.dart'),
      contains(RegExp(_orderByCreatedAt.pattern)),
    );
  });
}
