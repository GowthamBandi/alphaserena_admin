// MEMBER WORKSPACE — one member, rendered from an offline detail controller
// whose feeds are filled by hand. Pins: header identity, health verdict (clean
// / issues / unread caveat), each tab's content, the per-section error +
// retry, not-found, and the cross-links' semantics.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/client_controller.dart';
import 'package:alphaserena_admin_portel/controllers/member_detail_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/services/member_language.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/models/member_payment_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/member/member_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'members_screen_behaviour_test.dart' show OfflineMembers, OfflineDetail;

final now = DateTime(2026, 9, 24, 12);

class SeededDetail extends OfflineDetail {
  SeededDetail(super.memberId);
  int paymentLoads = 0;
  @override
  Future<void> loadPayments() async {
    paymentLoads++;
    payments.succeed(const []);
  }
}

late OfflineMembers ctrl;
late SeededDetail detail;

class _Orgs extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Trainers extends TrainerController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

ClientModel member({Map<String, dynamic> doc = const {}}) =>
    ClientModel.fromMap({
      'adminId': 'org1',
      'authUid': 'u-1',
      'name': 'Sai Kumar',
      'email': 'sai@m.in',
      'phone': '+919800011111',
      'createdAt': now.subtract(const Duration(days: 40)),
      'membershipActive': true,
      'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      'membership': {
        'planName': 'Gold',
        'amount': 2999,
        'razorpayPaymentId': 'pay_1',
        'termStartAt': now.subtract(const Duration(days: 40)).toIso8601String(),
      },
      'activationStage': 'ready',
      'adherence': {
        'score': 72,
        'workoutPct': 80,
        'dietPct': 60,
        'windowDays': 14,
      },
      'lastActivityAt': now.subtract(const Duration(days: 1)),
      ...doc,
    }, 'm1');

void seedAll(SeededDetail d) {
  d.payments.succeed(const []);
  d.settlements.succeed(const []);
  d.assignments.succeed(const []);
  d.workoutSessions.succeed(const []);
  d.nutritionDays.succeed(const []);
  d.lifestyleDays.succeed(const []);
  d.checkIns.succeed(const []);
  d.coachNotes.succeed(const []);
  d.progress.succeed(const []);
  d.weeklyReports.succeed(const []);
  d.onboarding.succeed(null);
  d.chat.succeed(null);
  d.orgReviews.succeed(const []);
  d.coachReviews.succeed(const []);
  d.feedback.succeed(const []);
  d.audit.succeed(const []);
  d.siblings.succeed(const []);
}

Future<void> pump(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: ClientsScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Get.reset();
    final orgs = Get.put<AdminController>(_Orgs(), permanent: true);
    orgs.admins.value = [
      AdminModel.fromMap({
        'organizationName': 'Iron Temple',
        'name': 'Arjun',
        'email': 'arjun@iron.in',
        'status': 'active',
        'isSubscriptionActive': true,
      }, 'org1'),
    ];
    orgs.lastReceived.value = now;
    final trainers = Get.put<TrainerController>(_Trainers(), permanent: true);
    trainers.trainers.value = [
      TrainerModel.fromMap({
        'name': 'Priya',
        'status': 'active',
        'assignedBy': 'org1',
      }, 't1'),
    ];
    trainers.lastReceived.value = now;
    ctrl = OfflineMembers();
    Get.put<ClientController>(ctrl, permanent: true);
    ctrl.lastReceived.value = now;
    ctrl.detailFactory = (id) {
      detail = SeededDetail(id);
      detail.member.value = ctrl.byId(id);
      detail.loading.value = false;
      detail.notFound.value = ctrl.byId(id) == null;
      detail.lastReceived.value = now;
      return detail;
    };
  });
  tearDown(Get.reset);

  Future<void> open(WidgetTester tester, ClientModel m) async {
    ctrl.clients.value = [m];
    await pump(tester);
    final btn = find.bySemanticsLabel(
      'Open member: ${MemberLanguage.displayName(m)}',
    );
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.byType(MemberWorkspace), findsOneWidget);
  }

  testWidgets('header: identity, membership, org, coach, links', (
    tester,
  ) async {
    await open(tester, member(doc: {'trainerId': 't1'}));
    seedAll(detail);
    await tester.pumpAndSettle();

    expect(find.text('Sai Kumar'), findsWidgets);
    expect(find.text('Gold · ends in 20 days'), findsWidgets);
    expect(find.text('Iron Temple'), findsWidgets);
    expect(find.text('Coach Priya'), findsWidgets);
    expect(
      find.bySemanticsLabel('Open organization: Iron Temple'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Open trainer: Coach Priya'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open settlements for this member'),
      findsOneWidget,
    );
    expect(find.text('Everything looks good'), findsOneWidget);
    expect(find.textContaining('Score 72'), findsWidgets);
  });

  testWidgets('health lists issues from the record AND the payment feed', (
    tester,
  ) async {
    await open(
      tester,
      member(
        doc: {
          'membershipExpiry': now
              .subtract(const Duration(days: 5))
              .toIso8601String(),
        },
      ),
    );
    seedAll(detail);
    detail.payments.succeed([
      MemberPaymentModel.fromMap({
        'amount': 2999,
        'razorpayPaymentId': 'pay_1',
        'captureVerified': false,
        'createdAt': now,
      }, 'r1'),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text('Still marked active although the term ended'),
      findsWidgets,
    );
    expect(
      find.textContaining('activated without gateway confirmation'),
      findsOneWidget,
    );
    expect(find.text('Everything looks good'), findsNothing);
  });

  testWidgets('an unread feed is disclosed, not treated as fine', (
    tester,
  ) async {
    await open(tester, member());
    seedAll(detail);
    detail.payments.fail(
      const ConsoleError(kind: ConsoleErrorKind.permission, message: 'denied'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not checked: payments'), findsOneWidget);

    await tester.tap(find.text('Membership & payments'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This section could not be loaded'),
      findsOneWidget,
    );
    final before = detail.paymentLoads;
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(detail.paymentLoads, before + 1);
  });

  testWidgets('membership tab: term, receipts, settlements', (tester) async {
    await open(tester, member());
    seedAll(detail);
    detail.payments.succeed([
      MemberPaymentModel.fromMap({
        'amount': 2999,
        'planName': 'Gold',
        'razorpayPaymentId': 'pay_1',
        'captureVerified': true,
        'settlementStatus': 'pending',
        'createdAt': now,
      }, 'r1'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membership & payments'));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT TERM'), findsOneWidget);
    expect(find.text('Paid online via Razorpay'), findsWidgets);
    expect(find.text('pay_1'), findsWidgets);
    expect(find.textContaining('1 receipt'), findsOneWidget);
    expect(find.text('settlement pending'), findsOneWidget);
    expect(find.textContaining('No settlement exists'), findsOneWidget);
  });

  testWidgets('activity tab renders assignments and empty feeds honestly', (
    tester,
  ) async {
    await open(tester, member());
    seedAll(detail);
    detail.assignments.succeed([
      DatedDoc('a1', now.subtract(const Duration(days: 3)), {
        'planType': 'workout',
        'planName': 'Push Pull Legs',
        'status': 'active',
        'assignedByName': 'Priya',
      }),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coaching & activity'));
    await tester.pumpAndSettle();
    expect(find.text('Push Pull Legs (workout)'), findsOneWidget);
    expect(
      find.text('No workout sessions logged from the member app.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Only entries the member marked as shared'),
      findsOneWidget,
    );
    expect(find.text('Set up — has a plan'), findsWidgets);
  });

  testWidgets('feedback & history: a timeline from audit + receipts + record', (
    tester,
  ) async {
    await open(tester, member());
    seedAll(detail);
    detail.audit.succeed([
      AuditLogModel(
        id: 'l1',
        action: 'set_client_coach',
        actorUid: 'org1',
        targetId: 'm1',
        details: const {'to': 't1'},
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    ]);
    detail.payments.succeed([
      MemberPaymentModel.fromMap({
        'amount': 2999,
        'planName': 'Gold',
        'razorpayPaymentId': 'pay_1',
        'createdAt': now.subtract(const Duration(days: 40)),
      }, 'r1'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feedback & history'));
    await tester.pumpAndSettle();
    expect(find.text('Coach assigned to Priya'), findsOneWidget);
    expect(find.textContaining('by the organization owner ·'), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Member record created'), findsOneWidget);
    expect(
      find.text('The member has not rated the organization.'),
      findsOneWidget,
    );
  });

  testWidgets('profile tab: per-field identity, siblings, technical dump', (
    tester,
  ) async {
    await open(
      tester,
      member(
        doc: {
          'sharedProfile': {
            'identity': {
              'displayName': 'Sai K.',
              'gender': 'Male',
              'dob': '1995-01-10',
            },
            'bodyMetrics': {'heightCm': 178, 'weightKg': 82.5},
            'location': {'city': 'Vizag', 'country': 'India'},
          },
        },
      ),
    );
    seedAll(detail);
    detail.siblings.succeed([
      ClientModel.fromMap({
        'adminId': 'org1',
        'authUid': 'u-1',
        'name': 'Sai Kumar',
        'createdAt': now,
      }, 'm2'),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Also a member of 1 other organization'),
      findsOneWidget,
    );
    await tester.tap(find.text('Profile & technical'));
    await tester.pumpAndSettle();
    expect(find.text('178 cm'), findsOneWidget);
    expect(find.text('82.5 kg'), findsOneWidget);
    expect(find.text('Vizag, India'), findsOneWidget);
    expect(find.textContaining('31 (born'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Open membership in Iron Temple')),
      findsOneWidget,
    );
    expect(find.text('m1'), findsWidgets); // record id, selectable
  });

  testWidgets('not found is certain, distinct from an error', (tester) async {
    ctrl.clients.value = [member()];
    await pump(tester);
    ctrl.openMember('ghost');
    await tester.pumpAndSettle();
    expect(find.text('Member not found'), findsOneWidget);
    await tester.tap(find.text('Back to all members'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberWorkspace), findsNothing);
  });

  testWidgets('phone width renders without overflow', (tester) async {
    ctrl.clients.value = [
      member(doc: {'trainerId': 't1'}),
    ];
    await pump(tester, width: 390);
    final open = find.bySemanticsLabel('Open member: Sai Kumar');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    seedAll(detail);
    await tester.pumpAndSettle();
    for (final tab in ['Membership', 'Activity', 'Feedback', 'Profile']) {
      // The tab chips render before the content, so `.first` is the chip even
      // when a stat below shares the word.
      await tester.ensureVisible(find.text(tab).first);
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
