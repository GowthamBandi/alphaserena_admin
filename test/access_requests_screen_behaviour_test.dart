// ACCESS REQUESTS, AS A NON-TECHNICAL OPERATOR MEETS IT.
//
// Real screen + real controllers with `onInit` suppressed; the Cloud Function
// calls are intercepted at the controller's service seam by subclassing.
//
//   loading → skeleton, no count claimed
//   empty   → "No access requests yet"; filtered-empty explains itself
//   queue   → oldest open first, who/what/why/age/stage/action on every row
//   detail  → who, why, what creation allows, history with actors, technical
//   reject  → requires a reason, names the gym, says nothing else changes
//   payment → inline validation; failure message says nothing was changed
//   create  → two steps, review names owner/gym/plan/term/email; already-
//             created is reported honestly; one-time password shown once
//   lock    → a second action is refused while one is in flight
//   a11y    → rows and buttons carry labels naming the gym; phone width ok

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/access_request_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/core/services/access_request_language.dart';
import 'package:alphaserena_admin_portel/core/services/saas_onboarding_service.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/access_request_model.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/screens/access_requests_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Records every mutation instead of calling Cloud Functions.
class FakeRequests extends AccessRequestController {
  final calls = <String>[];
  Object? failWith;
  Completer<void>? gate;
  ProvisionResult? provisionResult;

  @override
  // ignore: must_call_super
  void onInit() {}

  Future<void> _go(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<bool> setStatus(
    String requestId,
    String status, {
    String? note,
    String? paymentReference,
    double? paymentAmount,
  }) async {
    if (isProcessing.value) return false;
    isProcessing.value = true;
    busyRequestId.value = requestId;
    actionError.value = null;
    try {
      await _go(
        'status:$requestId:$status:${note ?? ''}:${paymentReference ?? ''}:${paymentAmount ?? ''}',
      );
      return true;
    } catch (e) {
      actionError.value = AccessRequestController.friendlyError(e);
      return false;
    } finally {
      isProcessing.value = false;
      busyRequestId.value = null;
    }
  }

  @override
  Future<bool> addNote(String requestId, String text) async {
    if (text.trim().isEmpty) return false;
    await _go('note:$requestId:$text');
    return true;
  }

  @override
  Future<ProvisionResult?> provision({
    required String requestId,
    required String planId,
    required int months,
    String? email,
    String? ownerName,
    String? organizationName,
    String? phone,
  }) async {
    if (isProcessing.value) return null;
    isProcessing.value = true;
    try {
      await _go('provision:$requestId:$planId:$months:$email');
      return provisionResult;
    } catch (e) {
      actionError.value = AccessRequestController.friendlyError(
        e,
        creating: true,
      );
      return null;
    } finally {
      isProcessing.value = false;
    }
  }
}

class OfflineSubs extends SubscriptionController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class RecordingRoot extends AdminRootController {
  final opened = <int>[];
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void changePage(int index) => opened.add(index);
}

late FakeRequests ctrl;
late OfflineSubs subs;
late OfflineAdmins admins;
late RecordingRoot root;
final now = DateTime.now();

void mount() {
  ctrl =
      Get.put<AccessRequestController>(FakeRequests(), permanent: true)
          as FakeRequests;
  subs =
      Get.put<SubscriptionController>(OfflineSubs(), permanent: true)
          as OfflineSubs;
  admins =
      Get.put<AdminController>(OfflineAdmins(), permanent: true)
          as OfflineAdmins;
  root =
      Get.put<AdminRootController>(RecordingRoot(), permanent: true)
          as RecordingRoot;
  ctrl.isLoading.value = false;
}

AccessRequestModel req(
  String id, {
  String status = 'requested',
  String org = 'Iron Temple Gym',
  String owner = 'Arjun Rao',
  String message = 'Two branches, want online payments.',
  DateTime? created,
  String? provisionedOrgUid,
  List<AccessRequestEvent> history = const [],
  AccessRequestPayment? evidence,
}) => AccessRequestModel(
  id: id,
  organizationName: org,
  ownerName: owner,
  email: '$id@example.com',
  phone: '+91980000$id',
  message: message,
  status: status,
  provisionedOrgUid: provisionedOrgUid,
  createdAt: created ?? now.subtract(const Duration(hours: 4)),
  statusHistory: history,
  paymentEvidence: evidence,
);

SubscriptionPlanModel plan() => SubscriptionPlanModel.fromMap({
  'title': 'Growth',
  'price': 4999,
  'months': 1,
  'isActive': true,
  'limits': {
    'trainers': 5,
    'clients': 200,
    'workoutPlans': 50,
    'dietPlans': 50,
    'workouts': 500,
  },
}, 'plan-growth');

Future<void> pump(
  WidgetTester tester, {
  Size size = const Size(1500, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: AccessRequestsScreen())),
  );
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> drainSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 2));
}

Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  tearDown(Get.reset);
  openOrganizationById();

  group('loading / empty / error', () {
    testWidgets('loading claims no count; empty says all caught up', (
      tester,
    ) async {
      mount();
      ctrl.isLoading.value = true;
      await pump(tester);
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.textContaining('need'), findsNothing);

      ctrl.isLoading.value = false;
      await settle(tester);
      expect(find.text('No access requests yet'), findsOneWidget);
      expect(find.text('Nothing waiting'), findsOneWidget);
    });

    testWidgets('a failed stream is an error with Retry, never "no requests"', (
      tester,
    ) async {
      mount();
      ctrl.loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.permission,
        message: 'Firestore refused this read.',
      );
      await pump(tester);
      expect(find.text("We couldn't load access requests"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No access requests yet'), findsNothing);
      expect(
        find.text('Could not load'),
        findsOneWidget,
        reason: 'header badge',
      );
    });

    testWidgets('filtered-empty explains and offers Clear filters', (
      tester,
    ) async {
      mount();
      ctrl.requests.add(req('a'));
      ctrl.search.value = 'zebra';
      await pump(tester);
      expect(find.text('No requests match these filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters').last);
      await settle(tester);
      expect(ctrl.hasActiveFilters, isFalse);
      expect(find.text('Iron Temple Gym'), findsOneWidget);
    });
  });

  group('the queue', () {
    testWidgets(
      'rows show who, what, why, age, stage and the next action; oldest first',
      (tester) async {
        mount();
        ctrl.requests.assignAll(
          AccessRequestLanguage.sorted([
            req('new', created: now.subtract(const Duration(hours: 2))),
            req(
              'old',
              org: 'Powerhouse Gym',
              owner: 'Suresh N',
              message: '',
              created: now.subtract(const Duration(days: 12)),
            ),
            req(
              'paid',
              org: 'Pulse Fitness',
              status: 'payment_confirmed',
              created: now.subtract(const Duration(days: 6)),
            ),
          ]),
        );
        await pump(tester);

        // Summary tiles.
        expect(
          find.text('2 need attention'),
          findsNothing,
          reason: 'three open',
        );
        expect(find.text('3 need attention'), findsOneWidget);
        // Oldest first: Powerhouse before Iron Temple.
        final titles = tester.widgetList<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == 'Powerhouse Gym' ||
                    w.data == 'Iron Temple Gym' ||
                    w.data == 'Pulse Fitness'),
          ),
        );
        expect(titles.first.data, 'Powerhouse Gym');
        // Age + overdue, in words.
        expect(find.text('Waiting 12 days'), findsOneWidget);
        expect(find.text('Overdue'), findsWidgets);
        expect(find.text('Received today'), findsOneWidget);
        // Reason, including the missing one.
        expect(find.text('“Reason not provided”'), findsOneWidget);
        // Stage words, never ids.
        expect(find.text('Payment received'), findsOneWidget);
        expect(find.text('payment_confirmed'), findsNothing);
        // Next actions.
        expect(find.text('Mark as contacted'), findsNWidgets(2));
        expect(find.text('Create organization'), findsOneWidget);
      },
    );

    testWidgets(
      'tiles filter; chips filter; unknown stage is flagged, not hidden',
      (tester) async {
        mount();
        ctrl.requests.assignAll([
          req('a'),
          req('b', status: 'payment_pending', org: 'Muscle Factory'),
          req('w', status: 'on_hold', org: 'Odd State Gym'),
        ]);
        await pump(tester);
        expect(
          find.textContaining('a stage this console does not recognise'),
          findsOneWidget,
        );
        expect(find.text('Odd State Gym'), findsOneWidget);

        await tester.tap(
          find.bySemanticsLabel(RegExp(r'^In conversation: 1\.')),
        );
        await settle(tester);
        expect(ctrl.statusFilter.value, 'conversation');
        expect(find.text('Muscle Factory'), findsOneWidget);
        expect(find.text('Iron Temple Gym'), findsNothing);
      },
    );
  });

  group('detail', () {
    testWidgets(
      'names people in history, shows why, what creation allows, technical on demand',
      (tester) async {
        mount();
        ctrl.requests.add(
          req(
            'c',
            status: 'contacted',
            history: [
              AccessRequestEvent(
                status: 'requested',
                at: now.subtract(const Duration(days: 2)),
                by: 'prospect',
              ),
              AccessRequestEvent(
                status: 'contacted',
                at: now.subtract(const Duration(days: 1)),
                by: 'u-someone',
                note: 'Spoke on WhatsApp',
              ),
            ],
          ),
        );
        await pump(tester);
        await tester.tap(find.text('Details'));
        await settle(tester);

        expect(find.text('Who is asking'), findsOneWidget);
        expect(find.text('Why they asked'), findsOneWidget);
        expect(find.text('Two branches, want online payments.'), findsWidgets);
        expect(
          find.text('What creating the organization allows'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Request received · by the requester'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Marked as contacted · by a super-admin — “Spoke on WhatsApp”',
          ),
          findsOneWidget,
        );
        expect(find.text('Stored stage'), findsNothing);
        await tester.ensureVisible(find.text('Technical details'));
        await tester.tap(find.text('Technical details'));
        await settle(tester);
        await tester.ensureVisible(find.text('Stored stage'));
        expect(find.text('Stored stage'), findsOneWidget);
        expect(
          find.text('contacted'),
          findsOneWidget,
          reason: 'raw value only under details',
        );
        // The primary action explains itself.
        expect(
          find.textContaining(
            'Payment link sent — Records that a payment link was sent',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a request that disappears while open says so and offers no action',
      (tester) async {
        mount();
        ctrl.requests.add(req('gone'));
        await pump(tester);
        await tester.tap(find.text('Details'));
        await settle(tester);
        ctrl.requests.clear();
        await settle(tester);
        expect(
          find.text('This request is no longer in the list'),
          findsOneWidget,
        );
        expect(find.text('Mark as contacted'), findsNothing);
      },
    );
  });

  group('reject', () {
    testWidgets('requires a reason, names the gym, records the note', (
      tester,
    ) async {
      mount();
      ctrl.requests.add(
        req('r', org: 'Quick Cash Fitness', owner: 'Unknown Caller'),
      );
      await pump(tester);
      await tester.tap(find.text('Details'));
      await settle(tester);
      await tester.tap(find.text('Reject'));
      await settle(tester);
      expect(find.text('Reject this request?'), findsOneWidget);
      expect(
        find.textContaining(
          'Unknown Caller of Quick Cash Fitness will not get',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('You can reopen it later'), findsOneWidget);

      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Reject request')),
      );
      await settle(tester);
      expect(find.textContaining('Write one line'), findsOneWidget);
      expect(ctrl.calls, isEmpty);

      await tester.enterText(
        inDialog(find.byType(TextField)),
        'Not a real gym',
      );
      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Reject request')),
      );
      await settle(tester);
      expect(ctrl.calls, ['status:r:rejected:Not a real gym::']);
      expect(find.textContaining('now under "Rejected"'), findsOneWidget);
      await drainSnackbar(tester);
    });
  });

  group('record payment', () {
    testWidgets(
      'validates inline; a backend refusal says nothing was changed',
      (tester) async {
        mount();
        ctrl.requests.add(req('p', status: 'payment_pending'));
        await pump(tester);
        await tester.tap(find.text('Record payment'));
        await settle(tester);
        expect(find.text('Record payment'), findsWidgets);
        await tester.tap(
          inDialog(find.widgetWithText(FilledButton, 'Record payment')),
        );
        await settle(tester);
        expect(find.text('Enter the payment reference.'), findsOneWidget);
        expect(
          find.textContaining('Enter the amount as a number'),
          findsOneWidget,
        );
        expect(ctrl.calls, isEmpty);

        ctrl.failWith = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'This payment reference was already used for another grant.',
        );
        await tester.enterText(inDialog(find.byType(TextField)).at(0), 'pay_X');
        await tester.enterText(inDialog(find.byType(TextField)).at(1), '4999');
        await tester.tap(
          inDialog(find.widgetWithText(FilledButton, 'Record payment')),
        );
        await settle(tester);
        expect(ctrl.calls, ['status:p:payment_confirmed::pay_X:4999.0']);
        expect(
          find.textContaining(
            'already used for another grant. Nothing was changed.',
          ),
          findsOneWidget,
        );
        await drainSnackbar(tester);
      },
    );
  });

  group('create organization', () {
    testWidgets(
      'two steps: form → review naming owner, gym, plan, term, email → one-time password',
      (tester) async {
        mount();
        subs.plans.add(plan());
        ctrl.requests.add(
          req(
            'ok',
            status: 'payment_confirmed',
            org: 'Pulse Fitness',
            owner: 'Meera Shah',
          ),
        );
        ctrl.provisionResult = const ProvisionResult(
          uid: 'new-uid',
          email: 'ok@example.com',
          tempPassword: 'Secret1234567890abcd',
          expiry: '2026-10-06T00:00:00.000Z',
        );
        await pump(tester);
        await tester.tap(find.text('Create organization'));
        await settle(tester);
        expect(find.text('Create organization'), findsWidgets);
        expect(find.textContaining('Growth — ₹4999 / 1 month'), findsOneWidget);
        await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Review')));
        await settle(tester);
        expect(find.text('Review before creating'), findsOneWidget);
        expect(
          find.textContaining(
            'create a Trainersarena organization for Meera Shah (Pulse Fitness)',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('This cannot be undone from here'),
          findsOneWidget,
        );
        expect(find.text('ok@example.com'), findsWidgets);
        expect(
          ctrl.calls,
          isEmpty,
          reason: 'nothing happens before the final confirmation',
        );

        await tester.tap(
          inDialog(find.widgetWithText(FilledButton, 'Create organization')),
        );
        await settle(tester);
        expect(ctrl.calls, ['provision:ok:plan-growth:1:ok@example.com']);
        expect(find.text('Organization created'), findsOneWidget);
        expect(
          find.textContaining('Temporary password: Secret1234567890abcd'),
          findsOneWidget,
        );
        expect(find.textContaining('Meera Shah can sign in'), findsOneWidget);
        expect(find.textContaining('Plan ends: 6 Oct 2026'), findsOneWidget);
      },
    );

    testWidgets('already created is reported honestly — no second password', (
      tester,
    ) async {
      mount();
      subs.plans.add(plan());
      ctrl.requests.add(req('dup', status: 'approved'));
      ctrl.provisionResult = const ProvisionResult(
        uid: 'existing',
        alreadyProvisioned: true,
      );
      await pump(tester);
      await tester.tap(find.text('Create organization'));
      await settle(tester);
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Review')));
      await settle(tester);
      await tester.tap(
        inDialog(find.widgetWithText(FilledButton, 'Create organization')),
      );
      await settle(tester);
      expect(find.text('Already created'), findsOneWidget);
      expect(find.textContaining('no new password was issued'), findsOneWidget);
      expect(find.textContaining('Temporary password'), findsNothing);
    });

    testWidgets(
      'with no published plan nothing is attempted and the reason is stated',
      (tester) async {
        mount();
        ctrl.requests.add(req('np', status: 'payment_confirmed'));
        await pump(tester);
        await tester.tap(find.text('Create organization'));
        await settle(tester);
        expect(ctrl.calls, isEmpty);
        expect(
          find.textContaining('Publish a plan under Plans first'),
          findsOneWidget,
        );
        await drainSnackbar(tester);
      },
    );

    testWidgets(
      'a network failure during creation does NOT claim nothing changed',
      (tester) async {
        mount();
        subs.plans.add(plan());
        ctrl.requests.add(req('net', status: 'payment_confirmed'));
        ctrl.failWith = FirebaseFunctionsException(
          code: 'unavailable',
          message: 'x',
        );
        await pump(tester);
        await tester.tap(find.text('Create organization'));
        await settle(tester);
        await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Review')));
        await settle(tester);
        await tester.tap(
          inDialog(find.widgetWithText(FilledButton, 'Create organization')),
        );
        await settle(tester);
        expect(
          find.textContaining('unclear whether the organization was created'),
          findsOneWidget,
        );
        expect(find.textContaining('Nothing was changed'), findsNothing);
        await drainSnackbar(tester);
      },
    );
  });

  group('one action at a time', () {
    testWidgets(
      'while a call is in flight the row shows progress and a second call is refused',
      (tester) async {
        mount();
        ctrl.requests.addAll([req('a'), req('b', org: 'Second Gym')]);
        ctrl.gate = Completer<void>();
        await pump(tester);

        final first = ctrl.setStatus('a', 'contacted');
        await tester.pump();
        expect(ctrl.busyRequestId.value, 'a');
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final buttons = tester.widgetList<FilledButton>(
          find.byType(FilledButton),
        );
        expect(buttons.every((b) => b.onPressed == null), isTrue);

        final second = await ctrl.setStatus('b', 'contacted');
        expect(second, isFalse);
        ctrl.gate!.complete();
        expect(await first, isTrue);
        expect(ctrl.calls, ['status:a:contacted:::']);
      },
    );
  });

  group('reopen and open organization', () {
    testWidgets(
      'reopen confirms; a created request opens Organizations with the gym searched',
      (tester) async {
        mount();
        ctrl.requests.addAll([
          req(
            'rej',
            status: 'rejected',
            org: 'Rejected Gym',
            history: [
              AccessRequestEvent(
                status: 'rejected',
                at: now,
                by: 'u-x',
                note: 'spam',
              ),
            ],
          ),
          req(
            'done',
            status: 'organization_created',
            provisionedOrgUid: 'org-1',
            org: 'Done Gym',
          ),
        ]);
        ctrl.statusFilter.value = 'all';
        await pump(tester);

        await tester.tap(find.text('Reopen'));
        await settle(tester);
        expect(find.text('Reopen this request?'), findsOneWidget);
        await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Reopen')));
        await settle(tester);
        expect(ctrl.calls, ['status:rej:requested:::']);
        await drainSnackbar(tester);

        await tester.tap(find.text('Open organization'));
        expect(root.opened, [1]);
        expect(
          admins.search.value,
          'Done Gym',
          reason:
              'no created record in the list yet → the gym name, not the requester email',
        );
      },
    );
  });

  group('accessibility and phone width', () {
    testWidgets(
      'rows and buttons announce the gym; renders at 390px without overflow',
      (tester) async {
        mount();
        ctrl.requests.add(
          req('a', org: 'A Very Long Organization Name For A Narrow Screen'),
        );
        await pump(tester, size: const Size(390, 2400));
        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(RegExp(r'^Mark as contacted: A Very Long')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'^A Very Long Organization Name.*requested by Arjun Rao'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

// Appended after the emulator run: "Open organization" searched by the
// request's email and found nothing, because the created organization's record
// is keyed by the provisioned id and its details may have been edited at
// creation. The drill-down must find the record by id.
void openOrganizationById() {
  testWidgets('Open organization finds the created record by its id', (
    tester,
  ) async {
    mount();
    admins.admins.add(
      AdminModelFixture.byId('org-1', 'Renamed At Creation', 'owner@new.in'),
    );
    ctrl.requests.add(
      req(
        'done',
        status: 'organization_created',
        provisionedOrgUid: 'org-1',
        org: 'Done Gym',
      ),
    );
    ctrl.statusFilter.value = 'created';
    await pump(tester);
    await tester.tap(find.text('Open organization'));
    expect(root.opened, [1]);
    expect(admins.search.value, 'owner@new.in');
    expect(admins.statusFilter.value, 'all');
  });
}

class AdminModelFixture {
  static AdminModel byId(String id, String org, String email) =>
      AdminModel.fromMap({
        'organizationName': org,
        'name': 'owner',
        'email': email,
        'status': 'active',
        'createdAt': DateTime(2026, 8, 1).toIso8601String(),
      }, id);
}
