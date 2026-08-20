// A HEADER COUNT IS A CLAIM ABOUT DATA THAT WAS READ.
//
// 🔴 THE DEFECT THIS GUARDS. SA-15 fixed the Operations Center's `trailing`
// badge, which printed a green "All clear" off `alerts.length` with no state
// test. Four sibling screens print the same kind of number the same way:
//
//     Audit log        '${ctrl.logs.length} total'
//     Communication    '${ctrl.announcements.length} total'
//     Platform Staff   '${ctrl.total} active'
//     Support          '${ctrl.openCount} open' / '${ctrl.reviewCount} reviews'
//
// Each of those controllers already carries an error flag, and each list is
// empty when its stream fails — so a denied read printed "0 total",
// "0 active", "0 open". The body of every one of those screens shows a proper
// error state at the same moment, so the header contradicted the page beneath
// it, and the header is what a founder reads at a glance.
//
// This is a source guard rather than four widget tests on purpose: the point is
// the CLASS. Every `trailing:` count in the console must consult its screen's
// failure state before printing a number.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens whose `trailing` is not a count, with the reason.
const _notACount = <String, String>{
  'settlement_screen.dart': 'a Refresh IconButton, not a number',
  'operations_screen.dart': 'guarded by anyLoading — SA-15',
};

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

void main() {
  test('the stripper works — otherwise every assertion below is vacuous', () {
    expect(codeOnly('// trailing: Obx(\nvar a = 1;').contains('trailing: Obx('),
        isFalse);
  });

  test('every reactive header badge consults its failure state', () {
    final offenders = <String>[];

    for (final f in Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final name = f.path.split('/').last;
      if (_notACount.containsKey(name)) continue;
      final lines = codeOnly(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('trailing: Obx(')) continue;
        final window =
            lines.sublist(i, (i + 18).clamp(0, lines.length)).join('\n');
        final guarded = window.contains('Error') ||
            window.contains('Loading') ||
            window.contains('Loaded') ||
            window.contains('Ready') ||
            window.contains('anyLoading');
        if (!guarded) offenders.add('${f.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'these header badges print a number without checking whether '
            'the read succeeded, so a failed load reads as a real zero:\n'
            '${offenders.join('\n')}');
  });
}
