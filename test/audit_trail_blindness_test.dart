// A COMPLIANCE RECORD MAY BE EMPTY. IT MAY NOT PRETEND TO BE.
//
// 🔴 THE DEFECT THIS GUARDS. The organization detail dialog shows that org's
// platform audit trail — the answer to "who moderated this gym, when, and
// why". `_loadOrgAudit` reads `audit_logs` and ends with
//
//     } catch (_) {
//       // e.g. rule/index not yet deployed — never crash the dialog.
//       return const <AuditLogModel>[];
//     }
//
// and the builder renders `logs.isEmpty` as
//
//     "No recorded platform actions for this organization yet."
//
// Not crashing the dialog is right. Answering the compliance question with a
// sentence the console cannot support is not. A denied read, a missing index
// and an organization that has genuinely never been moderated all produced the
// same reassuring line — on the one surface whose entire purpose is being the
// record. A founder reviewing why an org was blocked is told nobody ever
// touched it.
//
// This is the SA-06 / SA-11 class, on the audit trail, and it survived that
// pass because the failure is swallowed inside a `catch` rather than reaching
// a stream's `onError`.
//
// THE TEST DRIVES THE REAL FAILURE. There is no Firebase app in a widget test,
// so `FirebaseFirestore.instance` inside `_loadOrgAudit` throws for real and
// the catch fires — exactly the production path this guards.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

AdminModel _org({String uid = 'org-1'}) => AdminModel.fromMap({
      'uid': uid,
      'organizationName': 'Iron Works Gym',
      'name': 'Owner',
      'email': 'owner@ironworks.test',
      'status': 'blocked',
      'statusReason': 'Repeated payment disputes',
    }, uid);

Future<void> _openDetail(WidgetTester tester, {String uid = 'org-1'}) async {
  tester.view.physicalSize = const Size(1600, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final c = Get.put<AdminController>(_OfflineAdmins(), permanent: true);
  c.isLoading.value = false;
  c.admins.assignAll([_org(uid: uid)]);

  await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: AdminsScreen())));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Iron Works Gym').first);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('a failed audit read is not "no recorded platform actions"',
      (tester) async {
    await _openDetail(tester);

    expect(find.textContaining('No recorded platform actions'), findsNothing,
        reason: 'the audit read FAILED — that sentence asserts the record is '
            'empty, which the console did not observe');
    expect(find.textContaining('could not be loaded'), findsOneWidget,
        reason: 'the operator must be able to tell an unread record from an '
            'empty one');
  });

  testWidgets(
      'CONTROL — a record that WAS read and is empty still says so',
      (tester) async {
    // `_loadOrgAudit('')` returns early with no error, which is the
    // successful-and-empty path. Without this control a fix that always
    // reported failure would pass the test above and the dialog would never
    // again be able to say an organization has a clean record.
    await _openDetail(tester, uid: '');

    expect(find.textContaining('No recorded platform actions'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
