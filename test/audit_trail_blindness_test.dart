// AN UNREAD AUDIT RECORD IS NOT AN EMPTY ONE.
//
// 🔴 The original defect: the organization detail swallowed a failed
// `audit_logs` read into an empty list and rendered "No recorded platform
// actions for this organization yet." — a statement about the compliance
// record made on the strength of a read that did not happen. A denied rule,
// a missing index and a genuinely unmoderated organization were the same
// sentence, on the one surface whose whole purpose is "who did this, when".
//
// The workspace now keeps every related feed in its own unread / read /
// failed state (OrganizationDetailController.Section). This test pins the
// History tab's two sentences to the two states they belong to.

import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organization_workspace_behaviour_test.dart' as w;

void main() {
  tearDown(Get.reset);

  testWidgets('a failed audit read is not "no recorded platform actions"', (
    tester,
  ) async {
    await w.open(
      tester,
      seed: (d) {
        w.seedHealthy(d, w.a_);
        d.audit.fail(
          const ConsoleError(
            kind: ConsoleErrorKind.permission,
            message: 'Rules denied the read.',
          ),
        );
      },
    );
    await w.tab(tester, 'History');
    expect(
      find.textContaining('No recorded platform actions'),
      findsNothing,
      reason:
          'the audit read FAILED — that sentence asserts the record is '
          'empty, which the console did not observe',
    );
    expect(
      find.textContaining('could not be loaded'),
      findsOneWidget,
      reason:
          'the operator must be able to tell an unread record from an '
          'empty one',
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('CONTROL — a record that WAS read and is empty still says so', (
    tester,
  ) async {
    await w.open(
      tester,
      seed: (d) {
        w.seedHealthy(d, w.a_);
        d.audit.succeed(const []);
        d.requests.succeed(const []);
        // Receipts are timeline events too; an EMPTY timeline needs none.
        d.receipts.succeed(const []);
      },
    );
    await w.tab(tester, 'History');
    expect(find.textContaining('No recorded platform actions'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
