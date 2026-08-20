// REDECLARING A SCHEDULE MUST RETIRE THE INSTANT DERIVED FROM THE OLD ONE.
//
// 🔴 THE DEFECT THIS GUARDS. `campaignScheduler` acts on `scheduledAtMs`, an
// absolute instant resolved from the campaign's `schedule` rule. The console's
// save is the one write that can change that rule — and it left the old
// instant in place.
//
// This only became reachable when scheduled campaigns started firing at all
// (P1-A). Before that nothing ever acted on the stamp, so a stale one was
// harmless. Two failures it produces:
//
//   • Edit a scheduled campaign from 09:00 to 18:00 → it broadcasts at 09:00.
//   • Cancel a scheduled campaign, then re-schedule it → the stale PAST
//     instant makes it due immediately, or past the lateness window, where the
//     scheduler completes it without ever sending.
//
// The console may write this field: `scheduledAtMs` is deliberately absent
// from `workerOwned()` in firestore.rules, whose comment explains why
// `claimedAtMs` and `runDueAtMs` ARE worker-only.
//
// A source guard because the payload is built inline inside a Firestore write.
// It asserts the one thing that matters — that the save retires the stamp —
// and comments are stripped so the prose above cannot satisfy it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  final code =
      codeOnly(File('lib/controllers/communication_controller.dart').readAsStringSync());

  test('the stripper works — otherwise the assertion below is vacuous', () {
    expect(codeOnly("// 'scheduledAtMs': null,\nvar a = 1;"),
        isNot(contains('scheduledAtMs')));
  });

  test('saving an announcement retires the previously resolved instant', () {
    expect(code, contains(RegExp(r"'scheduledAtMs'\s*:\s*null")),
        reason: 'the save redeclares `schedule`, so an instant derived from '
            'the old rule must not survive it — the scheduler re-resolves');
  });

  test('the save still writes the schedule rule itself', () {
    // Control: the fix must retire the derived instant, not the rule.
    expect(code, contains(RegExp(r"'schedule'\s*:\s*schedule\.toMap\(\)")));
  });
}
