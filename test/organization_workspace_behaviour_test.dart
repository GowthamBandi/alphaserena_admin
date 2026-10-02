// ORGANIZATION WORKSPACE — one organization, rendered from an offline detail
// controller whose eight feeds are filled by hand. Pins: header identity,
// health verdict (clean / issues / unread caveat), every tab's content, the
// people rows (stale access, removed trainers, foreign coach, member total vs
// rows), subscription + receipts (states, refund only where possible, the
// refund dialog contract), history (actors, origin, technical details), the
// per-section error + retry, not-found, semantics and keyboard reach.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/organization_detail_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/access_request_model.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organizations_screen_behaviour_test.dart' as list;

final now = list.now;

class SeededDetail extends OrganizationDetailController {
  SeededDetail(super.orgId);
  int trainerLoads = 0;
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> loadTrainers() async {
    trainerLoads++;
    trainers.succeed(const []);
  }
}

late SeededDetail detail;
late list.FakeAdmins ctrl;

TrainerModel trainer(
  String id, {
  bool? orgActive = true,
  String status = 'active',
  bool deleted = false,
  int members = 0,
}) => TrainerModel(
  docId: id,
  uid: id,
  name: 'Coach $id',
  email: '$id@iron.in',
  phone: '',
  status: status,
  isDeleted: deleted,
  assignedBy: 'ok',
  orgActive: orgActive,
  clientIds: [for (var i = 0; i < members; i++) 'm$i'],
  createdAt: now.subtract(const Duration(days: 30)),
  updatedAt: now,
  lastLogin: now.subtract(const Duration(days: 1)),
);

ClientModel member(String id, {String? trainerId, bool active = true}) =>
    ClientModel(
      docId: id,
      uid: id,
      name: 'Member $id',
      email: '$id@m.in',
      phone: '',
      adminId: 'ok',
      trainerId: trainerId,
      membershipActive: active,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now,
    );

SubscriptionModel receipt({
  String id = 'r1',
  String pay = '',
  int amount = 4999,
  bool verified = true,
  double refund = 0,
}) => SubscriptionModel(
  id: id,
  adminUid: 'ok',
  adminDocId: 'ok',
  planName: 'Growth',
  durationMonths: 1,
  amountPaid: amount,
  originalAmount: amount,
  couponApplied: false,
  discountAmount: 0,
  paymentId: pay.isEmpty ? 'UTR-1' : pay,
  razorpayPaymentId: pay,
  startAt: now.subtract(const Duration(days: 20)),
  expiryAt: now.add(const Duration(days: 10)),
  createdAt: now.subtract(const Duration(days: 20)),
  captureVerified: verified,
  refundAmount: refund,
  maxAdmins: 1,
  maxTrainers: 5,
  maxClients: 100,
  maxWorkoutPlans: 5,
  maxWorkouts: 5,
  maxDietPlans: 5,
);

AuditLogModel audit(
  String action, {
  String actor = 'me',
  Map<String, dynamic> d = const {},
  int daysAgo = 1,
}) => AuditLogModel(
  id: '$action-$daysAgo',
  actorUid: actor,
  action: action,
  targetId: 'ok',
  targetType: 'admin',
  details: d,
  createdAt: now.subtract(Duration(days: daysAgo)),
);

AccessRequestModel request() => AccessRequestModel(
  id: 'ar-1',
  organizationName: 'Iron Temple',
  ownerName: 'Arjun Rao',
  email: 'arjun@iron.in',
  phone: '+919800011111',
  status: 'organization_created',
  city: 'Vizag',
  teamSize: 4,
  message: 'Two branches, want online payments.',
  provisionedOrgUid: 'ok',
  createdAt: now.subtract(const Duration(days: 12)),
  provisionedAt: now.subtract(const Duration(days: 9)),
  paymentEvidence: AccessRequestPayment(
    reference: 'UTR-1',
    amount: 4999,
    confirmedBy: 'me',
    confirmedAt: now.subtract(const Duration(days: 10)),
  ),
  statusHistory: [
    AccessRequestEvent(
      status: 'requested',
      at: now.subtract(const Duration(days: 12)),
      by: 'prospect',
    ),
    AccessRequestEvent(
      status: 'payment_confirmed',
      at: now.subtract(const Duration(days: 10)),
      by: 'me',
    ),
    AccessRequestEvent(
      status: 'organization_created',
      at: now.subtract(const Duration(days: 9)),
      by: 'me',
    ),
  ],
);

/// A consistent, healthy organization with every feed read.
void seedHealthy(SeededDetail d, AdminModel a) {
  d.admin.value = a;
  d.adminLoading.value = false;
  d.lastReceived.value = now;
  d.trainers.succeed([trainer('t1', members: 2), trainer('t2')]);
  d.members.succeed([
    member('m1', trainerId: 't1'),
    member('m2', trainerId: 't1', active: false),
    member('m3'),
  ]);
  d.memberTotal.value = 3;
  d.receipts.succeed([receipt()]);
  d.audit.succeed([
    audit('provision_organization', daysAgo: 9, d: {'requestId': 'ar-1'}),
    audit('set_admin_status', daysAgo: 9, d: {'status': 'active'}),
    audit(
      'grant_subscription',
      daysAgo: 2,
      d: {'months': 1, 'amount': 4999, 'reference': 'UTR-1'},
    ),
    audit('privileged_read:getX', daysAgo: 1),
  ]);
  d.requests.succeed([request()]);
  d.storefront.succeed({
    'published': true,
    'handle': 'irontemple',
    'orgActive': true,
  });
  d.quota.succeed(null);
  d.incidents.succeed(const []);
}

Future<void> open(
  WidgetTester tester, {
  AdminModel? org,
  void Function(SeededDetail d)? seed,
  Size? size,
}) async {
  final a =
      org ??
      AdminModel(
        docId: 'ok',
        uid: 'ok',
        name: 'Arjun Rao',
        email: 'arjun@iron.in',
        phone: '+91 9800011111',
        organizationName: 'Iron Temple',
        role: 'admin',
        status: 'active',
        isSubscriptionActive: true,
        planName: 'Growth',
        planExpiry: now.add(const Duration(days: 90)),
        subscriptionLimits: const AdminSubscriptionLimits(
          maxAdmins: 1,
          maxTrainers: 5,
          maxClients: 100,
          maxWorkoutPlans: 5,
          maxDietPlans: 5,
        ),
        createdAt: now.subtract(const Duration(days: 100)),
        updatedAt: now,
        trainerIds: const ['t1', 't2'],
      );
  a_ = a;
  ctrl =
      Get.put<AdminController>(list.FakeAdmins(), permanent: true)
          as list.FakeAdmins;
  ctrl.isLoading.value = false;
  ctrl.admins.assignAll([a]);
  ctrl.detailFactory = (id) {
    detail = SeededDetail(id);
    (seed ?? ((d) => seedHealthy(d, a)))(detail);
    return detail;
  };
  await list.pump(tester, size: size ?? const Size(1500, 3000));
  ctrl.openOrganization('ok');
  await list.settle(tester);
}

late AdminModel a_;

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.textContaining(label).first);
  await list.settle(tester);
}

Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  tearDown(Get.reset);

  group('header and health', () {
    testWidgets(
      'identity, standing, operating line, plan, owner, created and actions',
      (tester) async {
        await open(tester);
        expect(find.text('Iron Temple'), findsWidgets);
        expect(find.text('Approved'), findsWidgets);
        expect(
          find.text('Operating — can create trainers, members and plans'),
          findsWidgets,
        );
        expect(find.textContaining('Growth · Active · ends'), findsOneWidget);
        expect(
          find.textContaining('Owner Arjun Rao · arjun@iron.in'),
          findsOneWidget,
        );
        expect(find.textContaining('Created '), findsWidgets);
        expect(
          find.widgetWithText(OutlinedButton, 'Record renewal / change plan'),
          findsWidgets,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Issue warning'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Block'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Everything looks good'), findsOneWidget);
        expect(find.textContaining('Live · record updated'), findsOneWidget);
      },
    );

    testWidgets(
      'at a glance shows seats against limits and the payment count',
      (tester) async {
        await open(tester);
        expect(find.text('2 of 5 '), findsOneWidget);
        expect(find.text('3 of 100 '), findsOneWidget);
        expect(find.text('1'), findsWidgets);
        // ORG-9: the origin is PROVEN by the server-only access request that
        // points at this organization — not by the owner-editable
        // metadata.createdFrom, which this fixture lacks anyway.
        expect(
          find.textContaining('Created by the team from an access request'),
          findsOneWidget,
        );
        expect(
          find.textContaining('How it entered the system was not recorded'),
          findsNothing,
        );
        expect(
          find.textContaining('Published · @irontemple · listed as operating'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'issues from the record AND the feeds, worst first, with what/why/what-to-do',
      (tester) async {
        await open(
          tester,
          org: list.org(
            id: 'ok',
            orgName: 'Iron Temple',
            expiry: now.add(const Duration(days: 2)),
          ),
          seed: (d) {
            seedHealthy(d, a_);
            d.trainers.succeed([trainer('t1', orgActive: false)]);
            d.quota.succeed({
              'status': 'open',
              'violations': [
                {'resource': 'clients', 'used': 120, 'limit': 100},
              ],
            });
            d.incidents.succeed([
              {'id': 'i1', 'type': 'org_cascade_failed', 'status': 'open'},
            ]);
          },
        );
        expect(find.text('Everything looks good'), findsNothing);
        expect(find.textContaining('Urgent · '), findsWidgets);
        final incident = tester.getTopLeft(
          find.textContaining('backend operation on this organization failed'),
        );
        final expiring = tester.getTopLeft(
          find.text('Subscription ends in 2 days'),
        );
        expect(
          incident.dy,
          lessThan(expiring.dy),
          reason: 'critical before attention',
        );
        expect(
          find.textContaining('1 trainer has the wrong access state'),
          findsOneWidget,
        );
        expect(find.text('Using more than the plan allows'), findsOneWidget);
        expect(find.textContaining('Why it matters:'), findsWidgets);
        expect(find.textContaining('What you can do:'), findsWidgets);
        expect(
          find.textContaining('Trainer seat list does not match'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an unread feed is named next to the verdict, never treated as clean',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.trainers.fail(
              const ConsoleError(
                kind: ConsoleErrorKind.permission,
                message: 'denied',
              ),
            );
          },
        );
        expect(
          find.textContaining('Not checked: trainers could not be loaded'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a blocked organization: standing, reason on file, only Reactivate',
      (tester) async {
        final a = AdminModel(
          docId: 'ok',
          uid: 'ok',
          name: 'Arjun Rao',
          email: 'arjun@iron.in',
          phone: '',
          organizationName: 'Iron Temple',
          role: 'admin',
          status: 'blocked',
          statusReason: 'repeated chargebacks',
          statusUpdatedBy: 'me',
          statusUpdatedAt: now.subtract(const Duration(days: 1)),
          isSubscriptionActive: false,
          subscriptionLimits: AdminSubscriptionLimits.empty(),
          createdAt: now.subtract(const Duration(days: 50)),
          updatedAt: now,
        );
        await open(
          tester,
          org: a,
          seed: (d) {
            seedHealthy(d, a);
            d.storefront.succeed({'published': true, 'orgActive': false});
            d.trainers.succeed([trainer('t1', orgActive: false)]);
            d.members.succeed(const []);
            d.memberTotal.value = 0;
          },
        );
        expect(find.text('Blocked'), findsWidgets);
        expect(find.text('Cannot operate — blocked'), findsWidgets);
        expect(find.widgetWithText(OutlinedButton, 'Reactivate'), findsWidgets);
        expect(find.widgetWithText(OutlinedButton, 'Block'), findsNothing);
        expect(
          find.textContaining('Reason on file: repeated chargebacks'),
          findsOneWidget,
        );
        expect(find.textContaining('by you'), findsWidgets);
      },
    );

    testWidgets('not found is certain and offers the way back', (tester) async {
      await open(
        tester,
        seed: (d) {
          d.adminLoading.value = false;
          d.notFound.value = true;
        },
      );
      expect(find.text('Organization not found'), findsOneWidget);
      await tester.tap(find.text('Back to all organizations'));
      await list.settle(tester);
      expect(ctrl.selectedOrgId.value, '');
    });

    testWidgets(
      'a record stream failure is an error with retry, not a blank page',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            d.adminLoading.value = false;
            d.adminError.value = const ConsoleError(
              kind: ConsoleErrorKind.offline,
              message: 'offline',
            );
          },
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Organization not found'), findsNothing);
      },
    );
  });

  group('people', () {
    testWidgets(
      'trainers with access state, out-of-step flag, removed collapsed; members with total',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.trainers.succeed([
              trainer('t1', members: 2),
              trainer('t2', orgActive: false),
              trainer('t3', deleted: true, status: 'removed'),
            ]);
            d.members.succeed([
              member('m1', trainerId: 't1'),
              member('m2', trainerId: 'stranger'),
            ]);
            d.memberTotal.value = 250;
          },
        );
        await tab(tester, 'People');
        expect(find.text('Coach t1'), findsOneWidget);
        expect(find.text('app access on'), findsOneWidget);
        expect(find.text('app access paused · OUT OF STEP'), findsOneWidget);
        expect(find.text('2 of 5 trainers'), findsOneWidget);
        expect(find.textContaining('1 removed trainer'), findsOneWidget);
        expect(
          find.text('Coach t3'),
          findsNothing,
          reason: 'collapsed until expanded',
        );
        await tester.tap(find.textContaining('1 removed trainer'));
        await list.settle(tester);
        expect(find.text('Coach t3'), findsOneWidget);
        // ORG-10: the active count is of the rows READ, never of the total.
        expect(
          find.textContaining(
            '250 members · showing the first 2 read · 2 of those with an '
            'active membership',
          ),
          findsOneWidget,
        );
        expect(find.text('coach Coach t1'), findsOneWidget);
        expect(find.text('coach not in this organization'), findsOneWidget);
        expect(
          find.textContaining('managed by the organization in the'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a failed member feed offers its own Retry while trainers stand',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.members.fail(
              const ConsoleError(
                kind: ConsoleErrorKind.offline,
                message: 'offline',
              ),
            );
          },
        );
        await tab(tester, 'People');
        expect(find.text('Coach t1'), findsOneWidget);
        expect(
          find.textContaining('This section could not be loaded'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets('a section Retry re-runs that loader only', (tester) async {
      await open(
        tester,
        seed: (d) {
          seedHealthy(d, a_);
          d.trainers.fail(
            const ConsoleError(
              kind: ConsoleErrorKind.offline,
              message: 'offline',
            ),
          );
        },
      );
      await tab(tester, 'People');
      await tester.tap(find.text('Retry'));
      await list.settle(tester);
      expect(detail.trainerLoads, 1);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('subscription and payments', () {
    testWidgets('the plan card states state, end, source, reference, limits', (
      tester,
    ) async {
      final a = AdminModel(
        docId: 'ok',
        uid: 'ok',
        name: 'Arjun Rao',
        email: 'arjun@iron.in',
        phone: '',
        organizationName: 'Iron Temple',
        role: 'admin',
        status: 'active',
        isSubscriptionActive: true,
        planName: 'Growth',
        planExpiry: now.add(const Duration(days: 40)),
        subscription: {
          'method': 'manual',
          'reference': 'UTR-1',
          'amount': 4999,
          'months': 1,
          'grantedBy': 'me',
          'startedAt': now.subtract(const Duration(days: 20)).toIso8601String(),
        },
        subscriptionLimits: const AdminSubscriptionLimits(
          maxAdmins: 1,
          maxTrainers: 5,
          maxClients: 100,
          maxWorkoutPlans: 0,
          maxDietPlans: 1000000000,
        ),
        createdAt: now.subtract(const Duration(days: 50)),
        updatedAt: now,
      );
      await open(tester, org: a);
      await tab(tester, 'Subscription');
      expect(find.text('Recorded by the team'), findsWidgets);
      expect(find.textContaining('· in 1 month'), findsOneWidget);
      expect(find.text('UTR-1'), findsWidgets);
      expect(find.text('you'), findsWidgets);
      expect(find.text('trainers: up to 5'), findsOneWidget);
      expect(find.text('workout plans: not set'), findsOneWidget);
      expect(find.text('diet plans: unlimited'), findsOneWidget);
      expect(
        find.textContaining('On — the rules let the organization write'),
        findsOneWidget,
      );
    });

    testWidgets(
      'receipts are classified; Refund only on an online receipt with money left',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.receipts.succeed([
              receipt(id: 'manual'),
              receipt(id: 'online', pay: 'pay_1'),
              receipt(id: 'unv', pay: 'pay_2', verified: false),
              receipt(id: 'ref', pay: 'pay_3', refund: 4999),
              receipt(id: 'part', pay: 'pay_4', refund: 1000),
            ]);
          },
        );
        await tab(tester, 'Subscription');
        expect(find.text('Recorded by the team'), findsWidgets);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.text('Not confirmed by the gateway'), findsOneWidget);
        expect(find.text('Refunded'), findsOneWidget);
        expect(find.text('Partly refunded'), findsOneWidget);
        expect(
          find.text('Refund…'),
          findsNWidgets(3),
          reason: 'online, unverified, partial',
        );
        expect(find.textContaining('₹1,000 refunded'), findsOneWidget);
      },
    );

    testWidgets(
      'the refund dialog: what/who/consequences, whole rupees, reason required, revoke only for current',
      (tester) async {
        final a = AdminModel(
          docId: 'ok',
          uid: 'ok',
          name: 'Arjun Rao',
          email: 'arjun@iron.in',
          phone: '',
          organizationName: 'Iron Temple',
          role: 'admin',
          status: 'active',
          isSubscriptionActive: true,
          planName: 'Growth',
          planExpiry: now.add(const Duration(days: 40)),
          subscription: {'razorpayPaymentId': 'pay_1'},
          subscriptionLimits: AdminSubscriptionLimits.empty(),
          createdAt: now,
          updatedAt: now,
        );
        await open(
          tester,
          org: a,
          seed: (d) {
            seedHealthy(d, a);
            d.receipts.succeed([
              receipt(id: 'online', pay: 'pay_1'),
              receipt(id: 'old', pay: 'pay_0'),
            ]);
          },
        );
        await tab(tester, 'Subscription');
        await tester.tap(find.text('Refund…').first);
        await list.settle(tester);
        expect(inDialog(find.text('WHAT WILL HAPPEN')), findsOneWidget);
        expect(
          inDialog(find.textContaining('Full refund · ₹4,999')),
          findsOneWidget,
        );
        expect(
          inDialog(find.text('Also end the subscription now')),
          findsOneWidget,
        );
        FilledButton confirm() =>
            tester.widget<FilledButton>(inDialog(find.byType(FilledButton)));
        expect(confirm().onPressed, isNull, reason: 'reason required');
        await tester.enterText(
          inDialog(find.byType(TextField)).last,
          'duplicate charge',
        );
        await list.settle(tester);
        expect(confirm().onPressed, isNotNull);
        await tester.tap(inDialog(find.text('Part of it')));
        await list.settle(tester);
        expect(
          confirm().onPressed,
          isNull,
          reason: 'an amount is now required',
        );
        await tester.enterText(inDialog(find.byType(TextField)).first, '6000');
        await list.settle(tester);
        expect(
          confirm().onPressed,
          isNull,
          reason: 'above the refundable amount',
        );
        await tester.enterText(inDialog(find.byType(TextField)).first, '500');
        await list.settle(tester);
        expect(confirm().onPressed, isNotNull);
        expect(inDialog(find.textContaining('₹500 leaves')), findsOneWidget);
        await tester.tap(inDialog(find.text('Cancel')));
        await list.settle(tester);
        // The OLD receipt is not the current payment: no revoke option.
        await tester.tap(find.text('Refund…').last);
        await list.settle(tester);
        expect(
          inDialog(find.text('Also end the subscription now')),
          findsNothing,
        );
        expect(
          inDialog(find.textContaining('not the current subscription payment')),
          findsOneWidget,
        );
      },
    );
  });

  group('history', () {
    testWidgets(
      'origin card, moderation trail and a timeline with actors; privileged reads dropped',
      (tester) async {
        await open(tester);
        await tab(tester, 'History');
        expect(find.text('Created from access request'), findsOneWidget);
        expect(find.textContaining('Arjun Rao · arjun@iron.in'), findsWidgets);
        expect(find.textContaining('team of 4'), findsOneWidget);
        expect(
          find.text('"Two branches, want online payments."'),
          findsOneWidget,
        );
        expect(
          find.textContaining('₹4,999 · ref UTR-1 · by you'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Organization created by you'),
          findsOneWidget,
        );
        expect(find.text('Open the access request'), findsOneWidget);
        expect(find.text('Payment recorded by the team'), findsOneWidget);
        expect(find.text('Status changed to Approved'), findsOneWidget);
        expect(
          find.text('Organization created from an access request'),
          findsOneWidget,
        );
        expect(find.text('Access request received'), findsOneWidget);
        expect(find.textContaining('Get x'), findsNothing);
        expect(find.text('1 month · ₹4,999 · ref UTR-1'), findsOneWidget);
        // newest first
        expect(
          tester.getTopLeft(find.text('Payment recorded by the team')).dy,
          lessThan(tester.getTopLeft(find.text('Access request received')).dy),
        );
        expect(find.text('Technical details'), findsWidgets);
        expect(
          find.textContaining(
            'The current state of the organization is never turned into history',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a receipt is an event on the timeline, with its pricing evidence',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.audit.succeed(const []);
            d.requests.succeed(const []);
            d.receipts.succeed([
              SubscriptionModel(
                id: 'r-ev',
                adminUid: 'ok',
                adminDocId: 'ok',
                planName: 'Growth',
                durationMonths: 12,
                amountPaid: 9999,
                originalAmount: 9999,
                couponApplied: false,
                discountAmount: 0,
                paymentId: 'UTR-9',
                startAt: now.subtract(const Duration(days: 3)),
                expiryAt: now.add(const Duration(days: 362)),
                createdAt: now.subtract(const Duration(days: 3)),
                maxAdmins: 1,
                maxTrainers: 5,
                maxClients: 100,
                maxWorkoutPlans: 5,
                maxWorkouts: 5,
                maxDietPlans: 5,
                pricingBasis: 'plan_term',
                listPrice: 11999,
                listTermMonths: 12,
                pricingDiscount: 2000,
                overpayment: 0,
              ),
            ]);
          },
        );
        await tab(tester, 'History');
        expect(
          find.textContaining('Receipt · ₹9,999 · Growth'),
          findsOneWidget,
        );
        expect(
          find.textContaining('list ₹11,999 · discount ₹2,000'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No recorded platform actions'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'no audit rows and no receipts: an honest empty line, not a blank',
      (tester) async {
        await open(
          tester,
          seed: (d) {
            seedHealthy(d, a_);
            d.audit.succeed(const []);
            d.requests.succeed(const []);
            d.receipts.succeed(const []);
          },
        );
        await tab(tester, 'History');
        expect(
          find.textContaining('No recorded platform actions'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No access request points to this organization'),
          findsOneWidget,
        );
      },
    );
  });

  group('profile and technical', () {
    testWidgets(
      'business identity, owner, storefront and ids with "Not recorded" for blanks',
      (tester) async {
        await open(tester);
        await tab(tester, 'Profile');
        expect(find.text('Not recorded'), findsWidgets);
        expect(
          find.text('ok'),
          findsWidgets,
          reason: 'the id is shown, selectable',
        );
        expect(find.text('Raw status'), findsOneWidget);
        expect(find.text('@irontemple'), findsNothing);
        expect(find.text('irontemple'), findsOneWidget);
        expect(
          find.textContaining('the console cannot read Firebase Auth directly'),
          findsOneWidget,
        );
      },
    );
  });

  group('accessibility', () {
    testWidgets(
      'rows and actions carry meaningful labels; tabs are reachable by keyboard',
      (tester) async {
        await open(tester);
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp(r'^Block: Iron Temple')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Issue warning: Iron Temple')),
          findsOneWidget,
        );
        await tab(tester, 'People');
        expect(
          find.bySemanticsLabel(RegExp(r'Coach t1, Active, app access on')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Member m1, membership active, coach Coach t1'),
          ),
          findsOneWidget,
        );
        handle.dispose();

        // Keyboard: Tab from the back button reaches the tab chips.
        await tester.tap(find.text('All organizations'));
        await list.settle(tester);
        ctrl.openOrganization('ok');
        await list.settle(tester);
        var reached = false;
        for (var i = 0; i < 14 && !reached; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final f = FocusManager.instance.primaryFocus;
          final w = f?.context?.widget;
          if (w is InkWell || w is Focus) {
            final ctx = f!.context!;
            reached =
                find
                    .descendant(
                      of: find.byWidget(ctx.widget),
                      matching: find.text('History'),
                    )
                    .evaluate()
                    .isNotEmpty ||
                find
                    .ancestor(
                      of: find.text('History'),
                      matching: find.byWidget(ctx.widget),
                    )
                    .evaluate()
                    .isNotEmpty;
          }
        }
        expect(
          reached,
          isTrue,
          reason: 'the History tab chip must be focusable within 14 Tabs',
        );
      },
    );
  });

  group('responsive', () {
    testWidgets('every tab renders at phone width without overflow', (
      tester,
    ) async {
      await open(tester, size: const Size(390, 3600));
      for (final t in ['People', 'Subscription', 'History', 'Profile']) {
        await tab(tester, t);
        expect(tester.takeException(), isNull, reason: t);
      }
    });
  });
}
