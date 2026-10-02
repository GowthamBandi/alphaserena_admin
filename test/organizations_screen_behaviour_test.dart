// ORGANIZATIONS LIST + ACTIONS — driven through the real screen with offline
// controllers. Pins: states (loading / empty / filtered-empty / error), the
// queue tiles, search, plan filter, sort, paging, the Dashboard drill-down
// contract, opening a row, every confirmation dialog's contract (what / who /
// consequences / reason / typed name / cancel), the re-entry guard, the stale
// guard, honest failure wording, and phone-width layout.

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/organization_detail_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/core/services/saas_onboarding_service.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

final now = DateTime(2026, 9, 6, 12);

class OfflineDetail extends OrganizationDetailController {
  OfflineDetail(super.orgId);
  @override
  // ignore: must_call_super
  void onInit() {}
}

class FakeAdmins extends AdminController {
  int moderationCalls = 0;
  int grantCalls = 0;
  double? lastExpectedListPrice;
  int? lastGrantMonths;
  double? lastGrantAmount;
  String? lastGrantPlanId;
  final List<String> statuses = [];
  final List<String?> reasons = [];
  Completer<void>? hold;
  Object? failWith;

  /// What the server says the status is right now. Null = document gone.
  String? Function(String uid)? serverStatus;

  FakeAdmins() {
    clock = () => now;
    currentUid = () => 'me';
    detailFactory = (id) {
      final d = OfflineDetail(id);
      d.admin.value = byId(id);
      d.adminLoading.value = false;
      d.notFound.value = byId(id) == null;
      return d;
    };
    freshStatusRead = (uid) async =>
        serverStatus != null ? serverStatus!(uid) : byId(uid)?.status;
    moderationCall = (uid, status, {reason, expectedStatus}) async {
      moderationCalls++;
      statuses.add(status);
      reasons.add(reason);
      if (hold != null) await hold!.future;
      if (failWith != null) throw failWith!;
    };
    grantCall =
        ({
          required adminUid,
          required planId,
          required months,
          required reference,
          required amount,
          expectedListPrice,
        }) async {
          grantCalls++;
          lastExpectedListPrice = expectedListPrice;
          lastGrantMonths = months;
          lastGrantAmount = amount;
          lastGrantPlanId = planId;
          if (failWith != null) throw failWith!;
          return GrantResult(
            expiry: now.add(const Duration(days: 30)).toIso8601String(),
            planName: 'Growth',
            pricingBasis: 'plan_term',
            listPrice: 4999,
            listTermMonths: months,
            collected: amount,
            discount: 4999 - amount < 0 ? 0 : 4999 - amount,
            overpayment: amount - 4999 < 0 ? 0 : amount - 4999,
          );
        };
  }

  @override
  // ignore: must_call_super
  void onInit() {
    // The filter workers are what make cross-screen navigation land on the
    // list; keep them, drop the Firestore stream.
    wireFilters();
  }
}

class OfflineSubs extends SubscriptionController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

late FakeAdmins ctrl;

AdminModel org({
  String id = 'org-1',
  String orgName = 'Iron Temple',
  String owner = 'Arjun Rao',
  String email = 'arjun@iron.in',
  String status = 'active',
  bool subActive = true,
  DateTime? expiry,
  String? planName = 'Growth',
  DateTime? created,
}) => AdminModel(
  docId: id,
  uid: id,
  name: owner,
  email: email,
  phone: '+91 9800011111',
  organizationName: orgName,
  role: 'admin',
  status: status,
  isSubscriptionActive: subActive,
  planExpiry: expiry ?? now.add(const Duration(days: 90)),
  planName: planName,
  subscriptionLimits: const AdminSubscriptionLimits(
    maxAdmins: 1,
    maxTrainers: 5,
    maxClients: 100,
    maxWorkoutPlans: 5,
    maxDietPlans: 5,
  ),
  createdAt: created ?? now.subtract(const Duration(days: 100)),
  updatedAt: now,
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

void mount({List<AdminModel>? rows}) {
  ctrl = Get.put<AdminController>(FakeAdmins(), permanent: true) as FakeAdmins;
  final subs = Get.put<SubscriptionController>(OfflineSubs(), permanent: true);
  subs.plans.assignAll([plan()]);
  ctrl.isLoading.value = false;
  if (rows != null) ctrl.admins.assignAll(rows);
}

Future<void> pump(
  WidgetTester tester, {
  Size size = const Size(1500, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: const AdminsScreen())),
  );
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

List<AdminModel> sample() => [
  org(id: 'ok', orgName: 'Iron Temple'),
  org(
    id: 'pend',
    orgName: 'Pulse Fitness',
    status: 'pending',
    subActive: false,
    owner: 'Meera Shah',
    email: 'meera@pulse.in',
  ),
  org(id: 'nosub', orgName: 'Flex Arena', subActive: false),
  org(id: 'exp', orgName: 'Zen Yoga', expiry: now.add(const Duration(days: 3))),
  org(id: 'blk', orgName: 'Shady Gym', status: 'blocked', subActive: false),
  org(
    id: 'new',
    orgName: 'Fresh Fit',
    created: now.subtract(const Duration(days: 2)),
    planName: 'Starter',
  ),
];

void main() {
  tearDown(Get.reset);

  group('states', () {
    testWidgets('loading shows skeletons and claims no count', (tester) async {
      mount();
      ctrl.isLoading.value = true;
      await pump(tester);
      expect(find.text('No organizations yet'), findsNothing);
      expect(find.textContaining('organizations'), findsNothing);
    });

    testWidgets('no organizations at all explains where they come from', (
      tester,
    ) async {
      mount(rows: const []);
      await pump(tester);
      expect(find.text('No organizations yet'), findsOneWidget);
      expect(
        find.textContaining('created from Access Requests'),
        findsOneWidget,
      );
    });

    testWidgets('a failed stream is an error with Retry, never an empty list', (
      tester,
    ) async {
      mount(rows: const []);
      ctrl.loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.offline,
        message: 'Could not reach Firestore.',
      );
      await pump(tester);
      expect(find.text('No organizations yet'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text('—'),
        findsOneWidget,
        reason: 'the header must not claim a count',
      );
    });

    testWidgets('filtered-empty explains the filters and offers Clear', (
      tester,
    ) async {
      mount(rows: sample());
      ctrl.search.value = 'zebra';
      await pump(tester);
      expect(find.text('No organizations match'), findsOneWidget);
      await tester.tap(find.text('Clear filters').last);
      await settle(tester);
      expect(ctrl.search.value, '');
      expect(find.text('Iron Temple'), findsOneWidget);
    });
  });

  group('queue', () {
    testWidgets(
      'tiles carry the recomputed counts and the header says who needs attention',
      (tester) async {
        mount(rows: sample());
        await pump(tester);
        // all 6 · attention: pend, nosub, exp · pending 1 · noSub 1 · expiring 1 · blocked 1 · recent 1
        expect(find.text('6'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        for (final k in [
          'pending',
          'noSubscription',
          'expiring',
          'blocked',
          'recent',
        ]) {
          expect(ctrl.countFor(k), 1, reason: k);
        }
        expect(find.text('1'), findsAtLeastNWidgets(5));
        expect(
          find.textContaining('6 organizations · 3 need attention'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a tile filters; the active-filter strip says so; Clear restores',
      (tester) async {
        mount(rows: sample());
        await pump(tester);
        await tester.tap(find.text('Blocked').first);
        await settle(tester);
        expect(find.text('Shady Gym'), findsOneWidget);
        expect(find.text('Iron Temple'), findsNothing);
        expect(
          find.textContaining('Showing 1 organization: Blocked'),
          findsOneWidget,
        );
        await tester.tap(find.text('Clear filters'));
        await settle(tester);
        expect(find.text('Iron Temple'), findsOneWidget);
        expect(ctrl.statusFilter.value, 'all');
      },
    );

    testWidgets(
      'a Dashboard drill-down (statusFilter=pending) narrows the list',
      (tester) async {
        mount(rows: sample());
        ctrl.statusFilter.value = 'pending';
        await pump(tester);
        expect(find.text('Pulse Fitness'), findsOneWidget);
        expect(find.text('Iron Temple'), findsNothing);
      },
    );

    testWidgets(
      'search narrows across owner and email; the field mirrors an external search',
      (tester) async {
        mount(rows: sample());
        await pump(tester);
        await tester.enterText(find.byType(TextField).first, 'meera');
        await settle(tester);
        expect(find.text('Pulse Fitness'), findsOneWidget);
        expect(find.text('Iron Temple'), findsNothing);
        ctrl.search.value = 'zen';
        await settle(tester);
        expect(find.text('Zen Yoga'), findsOneWidget);
        expect(
          (tester.widget(find.byType(TextField).first) as TextField)
              .controller!
              .text,
          'zen',
        );
      },
    );

    testWidgets('plan filter shows only that plan', (tester) async {
      mount(rows: sample());
      await pump(tester);
      ctrl.planFilter.value = 'Starter';
      await settle(tester);
      expect(find.text('Fresh Fit'), findsOneWidget);
      expect(find.text('Iron Temple'), findsNothing);
      expect(find.textContaining('plan Starter'), findsOneWidget);
    });

    testWidgets(
      'default sort puts attention first; name sort is alphabetical',
      (tester) async {
        mount(rows: sample());
        await pump(tester);
        final first = tester.getTopLeft(find.text('Zen Yoga')).dy;
        final iron = tester.getTopLeft(find.text('Iron Temple')).dy;
        expect(
          first,
          lessThan(iron),
          reason: 'expiring row ranks above a clean one',
        );
        ctrl.sortKey.value = 'name';
        await settle(tester);
        expect(
          tester.getTopLeft(find.text('Flex Arena')).dy,
          lessThan(tester.getTopLeft(find.text('Fresh Fit')).dy),
        );
      },
    );

    testWidgets('rows are paged: 50 shown, "Show 50 more" reveals the rest', (
      tester,
    ) async {
      mount(
        rows: [for (var i = 0; i < 60; i++) org(id: 'o$i', orgName: 'Org $i')],
      );
      await pump(tester);
      expect(find.textContaining('Showing 50 of 60'), findsOneWidget);
      expect(
        find.textContaining('Org ').evaluate().length,
        lessThanOrEqualTo(50),
      );
      await tester.ensureVisible(find.text('Show 50 more'));
      await tester.tap(find.text('Show 50 more'));
      await settle(tester);
      expect(find.textContaining('Showing 50 of 60'), findsNothing);
    });

    testWidgets(
      'a row states standing, operating line, plan, owner and the first issue',
      (tester) async {
        mount(
          rows: [
            org(
              id: 'exp',
              orgName: 'Zen Yoga',
              expiry: now.add(const Duration(days: 3)),
            ),
          ],
        );
        await pump(tester);
        expect(find.text('Approved'), findsWidgets);
        expect(
          find.text('Operating — can create trainers, members and plans'),
          findsOneWidget,
        );
        expect(find.textContaining('Growth · Ends in 3 days'), findsOneWidget);
        expect(
          find.textContaining('Arjun Rao · arjun@iron.in'),
          findsOneWidget,
        );
        expect(find.text('Subscription ends in 3 days'), findsOneWidget);
        expect(
          find.text('Record renewal / change plan'),
          findsOneWidget,
          reason: 'the primary verb',
        );
      },
    );
  });

  group('opening', () {
    testWidgets(
      'tapping Open swaps in the workspace; back returns to the list',
      (tester) async {
        mount(rows: sample());
        await pump(tester);
        await tester.tap(find.text('Open').first);
        await settle(tester);
        expect(ctrl.selectedOrgId.value, isNotEmpty);
        expect(find.text('All organizations'), findsOneWidget);
        expect(find.text('Overview'), findsOneWidget);
        await tester.tap(find.text('All organizations'));
        await settle(tester);
        expect(ctrl.selectedOrgId.value, '');
        expect(find.text('Overview'), findsNothing);
      },
    );

    testWidgets('a filter set from another screen closes an open workspace', (
      tester,
    ) async {
      mount(rows: sample());
      await pump(tester);
      ctrl.openOrganization('ok');
      await settle(tester);
      expect(find.text('Overview'), findsOneWidget);
      ctrl.statusFilter.value = 'pending';
      await settle(tester);
      expect(find.text('Overview'), findsNothing);
      expect(find.text('Pulse Fitness'), findsOneWidget);
    });

    testWidgets(
      'openOrganizationFromElsewhere lands on the record with clean filters',
      (tester) async {
        mount(rows: sample());
        ctrl.search.value = 'stale';
        await pump(tester);
        ctrl.openOrganizationFromElsewhere('pend');
        await settle(tester);
        expect(ctrl.selectedOrgId.value, 'pend');
        expect(ctrl.search.value, '');
        expect(find.text('Pulse Fitness'), findsWidgets);
      },
    );

    testWidgets('an id that is not in the list opens an honest "not found"', (
      tester,
    ) async {
      mount(rows: sample());
      await pump(tester);
      ctrl.openOrganization('ghost');
      await settle(tester);
      expect(find.text('Organization not found'), findsOneWidget);
    });
  });

  group('confirmations', () {
    testWidgets(
      'Approve states what / who / changes / undo and cancels cleanly',
      (tester) async {
        mount(
          rows: [
            org(
              id: 'pend',
              orgName: 'Pulse Fitness',
              status: 'pending',
              subActive: false,
            ),
          ],
        );
        await pump(tester);
        await tester.tap(find.text('Approve').first);
        await settle(tester);
        expect(inDialog(find.text('WHAT WILL HAPPEN')), findsOneWidget);
        expect(inDialog(find.text('WHO IS AFFECTED')), findsOneWidget);
        expect(
          inDialog(find.textContaining('Pulse Fitness — owner Arjun Rao')),
          findsOneWidget,
        );
        expect(
          inDialog(find.textContaining('still cannot operate')),
          findsOneWidget,
        );
        expect(inDialog(find.text('CAN IT BE UNDONE?')), findsOneWidget);
        await tester.tap(inDialog(find.text('Cancel')));
        await settle(tester);
        expect(ctrl.moderationCalls, 0);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Block needs a reason AND the typed name; then calls once with the reason',
      (tester) async {
        mount(
          rows: [org(id: 'ok', orgName: 'Iron Temple')],
        );
        await pump(tester);
        ctrl.openOrganization('ok');
        await settle(tester);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Block'));
        await settle(tester);
        FilledButton confirm() =>
            tester.widget<FilledButton>(inDialog(find.byType(FilledButton)));
        expect(confirm().onPressed, isNull);
        await tester.enterText(
          inDialog(find.byType(TextField)).first,
          'repeated chargebacks',
        );
        await settle(tester);
        expect(
          confirm().onPressed,
          isNull,
          reason: 'reason alone is not enough',
        );
        await tester.enterText(
          inDialog(find.byType(TextField)).last,
          'Iron Temple',
        );
        await settle(tester);
        expect(confirm().onPressed, isNotNull);
        expect(
          inDialog(find.textContaining('Nothing is deleted')),
          findsOneWidget,
        );
        await tester.tap(inDialog(find.text('Block organization')));
        await settle(tester);
        expect(ctrl.moderationCalls, 1);
        expect(ctrl.statuses, ['blocked']);
        expect(ctrl.reasons, ['repeated chargebacks']);
        expect(find.text('Organization blocked'), findsOneWidget);
        expect(find.textContaining('Nothing was deleted'), findsOneWidget);
      },
    );

    testWidgets('a wrong typed name is refused with a message', (tester) async {
      mount(
        rows: [org(id: 'ok', orgName: 'Iron Temple')],
      );
      await pump(tester);
      ctrl.openOrganization('ok');
      await settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Block'));
      await settle(tester);
      await tester.enterText(inDialog(find.byType(TextField)).first, 'x');
      await tester.enterText(
        inDialog(find.byType(TextField)).last,
        'Iron Temple Gym',
      );
      await settle(tester);
      expect(inDialog(find.textContaining('Does not match')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(inDialog(find.byType(FilledButton)))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'Record payment: validation, then a review that names plan, term, amount and end date',
      (tester) async {
        mount(
          rows: [org(id: 'nosub', orgName: 'Flex Arena', subActive: false)],
        );
        await pump(tester);
        // Flag OFF with the plan end date 90 days ahead is "switched off
        // while paid-through" (ORPH-1): the list no longer PUSHES a payment
        // as the fix, but the action stays available in the workspace.
        expect(find.text('Record payment'), findsNothing);
        ctrl.openOrganization('nosub');
        await settle(tester);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Record payment'));
        await settle(tester);
        expect(
          inDialog(
            find.textContaining('switched off although it is paid until'),
          ),
          findsOneWidget,
        );
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        expect(
          inDialog(find.textContaining('reference is required')),
          findsOneWidget,
        );
        expect(ctrl.grantCalls, 0);
        await tester.enterText(
          inDialog(
            find.widgetWithText(
              TextField,
              'Payment reference (Razorpay id / bank reference)',
            ),
          ),
          'UTR-77',
        );
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        expect(
          inDialog(find.textContaining('Review before recording')),
          findsOneWidget,
        );
        expect(inDialog(find.textContaining('₹4,999')), findsWidgets);
        expect(inDialog(find.textContaining('UTR-77')), findsOneWidget);
        // The fixture's flag is OFF but its planExpiry lies 90 days ahead.
        // The backend extends from max(now, planExpiry) regardless of the
        // flag, so the preview must say so too: 5 Dec 2026 + 1 month.
        expect(
          inDialog(find.textContaining('added on top of the current end date')),
          findsOneWidget,
        );
        expect(
          inDialog(find.textContaining('until about 5 Jan 2027')),
          findsOneWidget,
        );
        expect(
          inDialog(find.textContaining('Cannot be undone')),
          findsOneWidget,
        );
        await tester.tap(inDialog(find.text('Record payment')));
        await settle(tester);
        expect(ctrl.grantCalls, 1);
        expect(find.text('Payment recorded'), findsOneWidget);
        expect(
          find.textContaining('Flex Arena is on Growth for 1 month'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Record payment: an amount below list needs an explicit acknowledgement and the review names the discount',
      (tester) async {
        mount(
          rows: [
            org(
              id: 'nosub',
              orgName: 'Flex Arena',
              subActive: false,
              expiry: now.subtract(const Duration(days: 10)),
            ),
          ],
        );
        await pump(tester);
        await tester.tap(find.text('Record payment').first);
        await settle(tester);
        // The pricing basis is shown, not typed.
        expect(
          inDialog(find.textContaining('List price: ₹4,999')),
          findsOneWidget,
        );
        expect(
          inDialog(find.textContaining('Exactly the list price')),
          findsOneWidget,
        );
        await tester.enterText(
          inDialog(find.widgetWithText(TextField, 'Amount collected (₹)')),
          '3999',
        );
        await settle(tester);
        expect(
          inDialog(find.textContaining('Discount of ₹1,000')),
          findsOneWidget,
        );
        await tester.enterText(
          inDialog(
            find.widgetWithText(
              TextField,
              'Payment reference (Razorpay id / bank reference)',
            ),
          ),
          'UTR-88',
        );
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        // Refused until the founder acknowledges the difference.
        expect(
          inDialog(find.textContaining('Tick the confirmation')),
          findsOneWidget,
        );
        expect(ctrl.grantCalls, 0);
        await tester.tap(inDialog(find.byType(Checkbox)));
        await settle(tester);
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        expect(
          inDialog(find.textContaining('list ₹4,999, discount ₹1,000')),
          findsOneWidget,
        );
        await tester.tap(inDialog(find.text('Record payment')));
        await settle(tester);
        expect(ctrl.grantCalls, 1);
        // The banner repeats the SERVER's evidence (the fake returns list 4999).
        expect(
          find.textContaining('a discount of ₹1,000 is on the receipt'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Record payment: a negotiated term is an explicit choice and is acknowledged',
      (tester) async {
        mount(
          rows: [
            org(
              id: 'nosub',
              orgName: 'Flex Arena',
              subActive: false,
              expiry: now.subtract(const Duration(days: 10)),
            ),
          ],
        );
        await pump(tester);
        await tester.tap(find.text('Record payment').first);
        await settle(tester);
        expect(
          inDialog(find.widgetWithText(TextField, 'Term (months, 1–120)')),
          findsNothing,
        );
        await tester.tap(inDialog(find.text('Negotiated term')));
        await settle(tester);
        await tester.enterText(
          inDialog(find.widgetWithText(TextField, 'Term (months, 1–120)')),
          '7',
        );
        await settle(tester);
        expect(
          inDialog(find.textContaining('no discount is computed')),
          findsOneWidget,
        );
        await tester.enterText(
          inDialog(
            find.widgetWithText(
              TextField,
              'Payment reference (Razorpay id / bank reference)',
            ),
          ),
          'UTR-89',
        );
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        expect(
          inDialog(find.textContaining('Tick the confirmation')),
          findsOneWidget,
        );
        await tester.tap(inDialog(find.byType(Checkbox)));
        await settle(tester);
        await tester.tap(inDialog(find.text('Review')));
        await settle(tester);
        expect(inDialog(find.textContaining('for 7 months')), findsWidgets);
        expect(
          inDialog(find.textContaining('negotiated term')),
          findsOneWidget,
        );
      },
    );

    testWidgets('no published plan → no grant, and it says so', (tester) async {
      mount(
        rows: [
          org(
            id: 'nosub',
            subActive: false,
            expiry: now.subtract(const Duration(days: 10)),
          ),
        ],
      );
      Get.find<SubscriptionController>().plans.clear();
      await pump(tester);
      await tester.tap(find.text('Record payment').first);
      await settle(tester);
      expect(inDialog(find.text('No plan can be recorded')), findsOneWidget);
      expect(inDialog(find.text('Review')), findsNothing);
    });
  });

  group('guards', () {
    testWidgets('every action button is disabled while a call is in flight', (
      tester,
    ) async {
      mount(
        rows: [org(id: 'ok', orgName: 'Iron Temple')],
      );
      ctrl.hold = Completer<void>();
      await pump(tester);
      ctrl.openOrganization('ok');
      await settle(tester);
      final f = ctrl.warn(ctrl.byId('ok')!, 'late');
      await settle(tester);
      expect(find.textContaining('Applying the change'), findsOneWidget);
      for (final b in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(b.onPressed, isNull);
      }
      expect(
        await ctrl.block(ctrl.byId('ok')!, 'x'),
        isFalse,
        reason: 're-entry refused',
      );
      ctrl.hold!.complete();
      await f;
      await settle(tester);
      expect(ctrl.moderationCalls, 1);
      expect(find.text('Warning recorded'), findsOneWidget);
    });

    testWidgets(
      'STALE: the record changed since the founder decided → nothing is sent',
      (tester) async {
        mount(
          rows: [
            org(
              id: 'pend',
              orgName: 'Pulse',
              status: 'pending',
              subActive: false,
            ),
          ],
        );
        ctrl.serverStatus = (_) =>
            'blocked'; // a colleague blocked it meanwhile
        await pump(tester);
        final ok = await ctrl.approve(ctrl.byId('pend')!);
        await settle(tester);
        expect(ok, isFalse);
        expect(ctrl.moderationCalls, 0);
        expect(
          find.text('This organization changed while you were deciding'),
          findsOneWidget,
        );
        expect(find.textContaining('now says "blocked"'), findsOneWidget);
        expect(find.text('Nothing was changed.'), findsOneWidget);
      },
    );

    testWidgets('DELETED meanwhile → nothing is sent, and it says so', (
      tester,
    ) async {
      mount(
        rows: [org(id: 'pend', status: 'pending', subActive: false)],
      );
      ctrl.serverStatus = (_) => null;
      await pump(tester);
      await ctrl.approve(ctrl.byId('pend')!);
      await settle(tester);
      expect(ctrl.moderationCalls, 0);
      expect(find.text('Organization no longer exists'), findsOneWidget);
    });

    testWidgets('ALREADY in the target state → no call, no duplicate audit row', (
      tester,
    ) async {
      mount(
        rows: [org(id: 'ok', status: 'warning')],
      );
      ctrl.serverStatus = (_) => 'active';
      await pump(tester);
      // Founder sees "warning" on a stale row, presses Clear warning; server already active.
      // That is a CHANGED record (warning → active), so it is refused as stale.
      await ctrl.reactivate(ctrl.byId('ok')!);
      await settle(tester);
      expect(ctrl.moderationCalls, 0);
      expect(
        find.text('This organization changed while you were deciding'),
        findsOneWidget,
      );
    });

    testWidgets('a backend refusal says the reason and "Nothing was changed"', (
      tester,
    ) async {
      mount(rows: [org(id: 'ok')]);
      ctrl.failWith = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'This organization is blocked.',
      );
      await pump(tester);
      await ctrl.grantSubscription(
        org: ctrl.byId('ok')!,
        planId: 'p',
        planName: 'Growth',
        months: 1,
        reference: 'r',
        amount: 1,
      );
      await settle(tester);
      expect(find.text('Payment not recorded'), findsOneWidget);
      expect(
        find.textContaining('This organization is blocked.'),
        findsOneWidget,
      );
      expect(find.text('Nothing was changed.'), findsOneWidget);
    });

    testWidgets(
      'a network drop is reported as UNKNOWN, not as failure-nothing-changed',
      (tester) async {
        mount(rows: [org(id: 'ok')]);
        ctrl.failWith = FirebaseFunctionsException(
          code: 'unavailable',
          message: 'x',
        );
        await pump(tester);
        await ctrl.warn(ctrl.byId('ok')!, 'late');
        await settle(tester);
        expect(
          find.textContaining('cannot tell whether the change was applied'),
          findsOneWidget,
        );
        expect(find.textContaining('not known'), findsOneWidget);
      },
    );

    testWidgets('raw callable names and paths never reach the founder', (
      tester,
    ) async {
      mount(rows: [org(id: 'ok')]);
      ctrl.failWith = FirebaseFunctionsException(
        code: 'internal',
        message: 'setAdminStatus at admins/ok',
      );
      await pump(tester);
      await ctrl.warn(ctrl.byId('ok')!, 'late');
      await settle(tester);
      expect(find.textContaining('setAdminStatus'), findsNothing);
      expect(find.textContaining('admins/ok'), findsNothing);
    });
  });

  group('responsive', () {
    testWidgets(
      'phone width renders without overflow, with tiles, search and rows',
      (tester) async {
        mount(rows: sample());
        await pump(tester, size: const Size(390, 3200));
        expect(tester.takeException(), isNull);
        expect(find.text('Iron Temple'), findsOneWidget);
        expect(find.text('Open'), findsWidgets);
      },
    );

    testWidgets('phone width workspace renders without overflow', (
      tester,
    ) async {
      mount(rows: sample());
      await pump(tester, size: const Size(390, 3200));
      ctrl.openOrganization('exp');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Zen Yoga'), findsWidgets);
    });
  });
}
