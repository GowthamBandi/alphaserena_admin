// GRANT-3 / GRANT-6 / ORG-3 / ORG-7 / ORG-12 / ORG-13 / ORG-14 / ORG-16 —
// RECORDING A PAYMENT, SAID AND PRICED LIKE THE SERVER DOES IT.
//
// • A dual-priced plan sells TWO terms; 'Plan term' offers both, each with
//   the list price the server measures that term against (C4), and the
//   dialog sends that list price back as `expectedListPrice`.
// • Amounts are rupees with at most two decimals — NaN / Infinity / 1e9 /
//   negatives / sub-paise amounts are refused before anything is sent — and
//   the prefill is never rounded (a ₹1,499.50 plan prefilled "1500").
// • Plans are identified by `subscription.planId`, the name only as a
//   fallback: a renamed plan is still "the same plan".
// • A lost response, a reused reference, a re-priced plan and an idempotent
//   replay each get their own honest words.
// • A receipt's coverage is `coverageStart → expiry` when stamped; a legacy
//   receipt never claims a span it cannot prove.

import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/core/services/action_outcomes.dart';
import 'package:alphaserena_admin_portel/core/services/org_moderation_service.dart';
import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/core/services/saas_onboarding_service.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organizations_screen_behaviour_test.dart' as list;

FirebaseFunctionsException ffe(String code, {Object? details, String? msg}) =>
    FirebaseFunctionsException(
      code: code,
      message: msg ?? code,
      details: details,
    );

/// A monthly-live plan that ALSO sells a year: ₹999 / month, ₹9,999 / year.
SubscriptionPlanModel dualPlan({String id = 'plan-pro', String name = 'Pro'}) =>
    SubscriptionPlanModel.fromMap({
      'title': name,
      'price': 999,
      'months': 1,
      'billingPeriod': 'monthly',
      'monthlyPrice': 999,
      'yearlyPrice': 9999,
      'isActive': true,
      'limits': {'trainers': 5, 'clients': 200},
    }, id);

SubscriptionPlanModel paisePlan() => SubscriptionPlanModel.fromMap({
  'title': 'Half',
  'price': 1499.5,
  'months': 1,
  'monthlyPrice': 1499.5,
  'yearlyPrice': 0,
  'isActive': true,
}, 'plan-half');

Future<void> openGrant(
  WidgetTester tester, {
  required List<SubscriptionPlanModel> plans,
  AdminModel? org,
}) async {
  list.mount(
    rows: [
      org ??
          list.org(
            id: 'nosub',
            orgName: 'Flex Arena',
            subActive: false,
            expiry: list.now.subtract(const Duration(days: 10)),
          ),
    ],
  );
  Get.find<SubscriptionController>().plans.assignAll(plans);
  await list.pump(tester);
  final id = (org?.docId ?? 'nosub');
  list.ctrl.openOrganization(id);
  await list.settle(tester);
  await tester.tap(
    find
        .text(
          (org?.isSubscriptionActive ?? false)
              ? 'Record renewal / change plan'
              : 'Record payment',
        )
        .first,
  );
  await list.settle(tester);
}

Finder field(String label) =>
    list.inDialog(find.widgetWithText(TextField, label));

void main() {
  tearDown(Get.reset);

  group('the server term rule, mirrored (C4)', () {
    test('a dual plan sells both terms, each at its own list', () {
      final pl = dualPlan();
      expect(pl.dualPricesAuthored, isTrue);
      final terms = OrganizationLanguage.soldTerms(
        livePrice: pl.price,
        liveMonths: pl.durationMonths,
        authoredMonthly: pl.authoredMonthlyPrice,
        authoredYearly: pl.authoredYearlyPrice,
      );
      expect(terms.map((t) => '${t.key}:${t.months}:${t.listPrice}'), [
        'monthly:1:999.0',
        'yearly:12:9999.0',
      ]);
      GrantList l(int m) => OrganizationLanguage.listForGrant(
        livePrice: pl.price,
        liveMonths: pl.durationMonths,
        authoredMonthly: pl.authoredMonthlyPrice,
        authoredYearly: pl.authoredYearlyPrice,
        months: m,
      );
      expect(l(12).listPrice, 9999);
      expect(l(12).term, 'yearly');
      expect(l(1).listPrice, 999);
      expect(l(7).listPrice, 999, reason: 'negotiated → the live term');
      expect(l(7).listTermMonths, 1);
      // A year at list price is a PLAN TERM, not a "negotiated term".
      final pv = OrganizationLanguage.grantPreview(
        listPrice: l(12).listPrice,
        listTermMonths: l(12).listTermMonths,
        months: 12,
        amount: 8000,
        term: l(12).term,
      );
      expect(pv.basis, 'plan_term');
      expect(pv.discount, 1999);
      expect(pv.term, 'yearly');
    });

    test('a MIGRATED legacy price is not an authored second term', () {
      final legacyYear = SubscriptionPlanModel.fromMap({
        'title': 'Annual',
        'price': 9999,
        'months': 12,
      }, 'y');
      expect(legacyYear.dualPricesAuthored, isFalse);
      expect(legacyYear.yearlyPrice, 9999, reason: 'migrated for the editor');
      final l = OrganizationLanguage.listForGrant(
        livePrice: legacyYear.price,
        liveMonths: legacyYear.durationMonths,
        authoredMonthly: legacyYear.authoredMonthlyPrice,
        authoredYearly: legacyYear.authoredYearlyPrice,
        months: 1,
      );
      expect(l.listTermMonths, 12, reason: 'no monthly price is sold');
      final threeMonth = SubscriptionPlanModel.fromMap({
        'title': 'Quarter',
        'price': 2700,
        'months': 3,
      }, 'q');
      expect(threeMonth.monthlyPrice, 2700, reason: 'migrated, not sold');
      expect(
        OrganizationLanguage.soldTerms(
          livePrice: threeMonth.price,
          liveMonths: threeMonth.durationMonths,
          authoredMonthly: threeMonth.authoredMonthlyPrice,
          authoredYearly: threeMonth.authoredYearlyPrice,
        ).map((t) => t.months),
        [3],
      );
    });

    test('the preview is paise-exact and never throws on a bad amount', () {
      final pv = OrganizationLanguage.grantPreview(
        listPrice: 999,
        listTermMonths: 1,
        months: 1,
        amount: 999.4,
      );
      expect(pv.overpayment, 0.4);
      expect(OrganizationLanguage.rupees(pv.overpayment!), '₹0.40');
      for (final bad in [double.nan, double.infinity]) {
        expect(
          () => OrganizationLanguage.grantPreview(
            listPrice: 999,
            listTermMonths: 1,
            months: 1,
            amount: bad,
          ),
          returnsNormally,
        );
      }
    });

    test(
      'the outcome sentence names the sold term when the server stamps it',
      () {
        expect(
          OrganizationLanguage.pricingSentence(
            const GrantResult(
              pricingBasis: 'plan_term',
              listPrice: 9999,
              collected: 9999,
              discount: 0,
              overpayment: 0,
              pricingTerm: 'yearly',
            ),
          ),
          'Recorded ₹9,999, the list price (yearly term).',
        );
      },
    );

    test('GrantResult reads replayed and pricing.term', () {
      final r = GrantResult.fromMap({
        'ok': true,
        'replayed': true,
        'expiry': '2027-09-25T00:00:00.000Z',
        'pricing': {'basis': 'plan_term', 'term': 'yearly'},
      });
      expect(r.replayed, isTrue);
      expect(r.pricingTerm, 'yearly');
    });
  });

  group('the grant dialog', () {
    testWidgets(
      'a dual-priced plan offers BOTH sold terms; the yearly term at list '
      'needs no acknowledgement and sends months 12 + expectedListPrice',
      (tester) async {
        await openGrant(tester, plans: [dualPlan()]);
        expect(
          list.inDialog(find.text('Monthly · 1 month · ₹999')),
          findsOneWidget,
        );
        expect(
          list.inDialog(find.text('Yearly · 12 months · ₹9,999')),
          findsOneWidget,
        );
        await tester.tap(
          list.inDialog(find.text('Yearly · 12 months · ₹9,999')),
        );
        await list.settle(tester);
        expect(
          list.inDialog(find.textContaining('Exactly the list price')),
          findsOneWidget,
        );
        expect(
          list.inDialog(
            find.textContaining(
              'List price: ₹9,999 for 12 months (yearly term)',
            ),
          ),
          findsOneWidget,
        );
        await tester.enterText(
          field('Payment reference (Razorpay id / bank reference)'),
          'UTR-12',
        );
        await tester.tap(list.inDialog(find.text('Review')));
        await list.settle(tester);
        expect(
          list.inDialog(find.textContaining('Review before recording')),
          findsOneWidget,
        );
        expect(list.inDialog(find.byType(Checkbox)), findsNothing);
        await tester.tap(list.inDialog(find.text('Record payment')));
        await list.settle(tester);
        expect(list.ctrl.grantCalls, 1);
        expect(list.ctrl.lastGrantMonths, 12);
        expect(list.ctrl.lastGrantAmount, 9999);
        expect(list.ctrl.lastExpectedListPrice, 9999);
        expect(list.ctrl.lastGrantPlanId, 'plan-pro');
      },
    );

    testWidgets('NaN, Infinity, 1e9, negatives and sub-paise are refused '
        'before anything is sent — and nothing crashes', (tester) async {
      await openGrant(tester, plans: [dualPlan()]);
      await tester.enterText(
        field('Payment reference (Razorpay id / bank reference)'),
        'UTR-1',
      );
      for (final bad in ['NaN', 'Infinity', '1e9', '-5', '10.555', '1,000']) {
        await tester.enterText(field('Amount collected (₹)'), bad);
        await list.settle(tester);
        expect(tester.takeException(), isNull, reason: bad);
        await tester.tap(list.inDialog(find.text('Review')));
        await list.settle(tester);
        expect(
          list.inDialog(find.textContaining('at most two decimals')),
          findsWidgets,
          reason: bad,
        );
        expect(
          list.inDialog(find.textContaining('Review before recording')),
          findsNothing,
          reason: bad,
        );
      }
      expect(list.ctrl.grantCalls, 0);
    });

    testWidgets('a paise-priced plan prefills exactly — no spurious '
        '"above the list price"', (tester) async {
      await openGrant(tester, plans: [paisePlan()]);
      final amount = tester.widget<TextField>(field('Amount collected (₹)'));
      expect(amount.controller!.text, '1499.50');
      expect(
        list.inDialog(find.textContaining('Exactly the list price')),
        findsOneWidget,
      );
      expect(list.inDialog(find.textContaining('ABOVE')), findsNothing);
    });

    testWidgets('changing the negotiated months clears the acknowledgement', (
      tester,
    ) async {
      await openGrant(tester, plans: [dualPlan()]);
      await tester.tap(list.inDialog(find.text('Negotiated term')));
      await list.settle(tester);
      await tester.enterText(field('Term (months, 1–120)'), '7');
      await list.settle(tester);
      await tester.tap(list.inDialog(find.byType(Checkbox)));
      await list.settle(tester);
      expect(
        tester.widget<Checkbox>(list.inDialog(find.byType(Checkbox))).value,
        isTrue,
      );
      await tester.enterText(field('Term (months, 1–120)'), '8');
      await list.settle(tester);
      expect(
        tester.widget<Checkbox>(list.inDialog(find.byType(Checkbox))).value,
        isFalse,
      );
    });

    testWidgets(
      'the current plan is found by id: a renamed plan is still "the same '
      'plan", never a PLAN CHANGE',
      (tester) async {
        final renamed = dualPlan(id: 'plan-pro', name: 'Pro Plus');
        final other = dualPlan(id: 'plan-basic', name: 'Basic');
        final org = AdminModel(
          docId: 'ok',
          uid: 'ok',
          name: 'Arjun',
          email: 'a@b.in',
          phone: '',
          organizationName: 'Iron Temple',
          role: 'admin',
          status: 'active',
          isSubscriptionActive: true,
          planName: 'Pro',
          planExpiry: list.now.add(const Duration(days: 40)),
          subscription: const {'planId': 'plan-pro', 'months': 12},
          subscriptionLimits: AdminSubscriptionLimits.empty(),
          createdAt: list.now,
          updatedAt: list.now,
        );
        await openGrant(tester, plans: [other, renamed], org: org);
        expect(
          list.inDialog(find.textContaining('Pro Plus ·')),
          findsWidgets,
          reason: 'the renamed current plan is preselected',
        );
        await tester.enterText(
          field('Payment reference (Razorpay id / bank reference)'),
          'UTR-5',
        );
        await tester.tap(list.inDialog(find.text('Review')));
        await list.settle(tester);
        expect(list.inDialog(find.textContaining('PLAN CHANGE')), findsNothing);
        expect(
          list.inDialog(find.textContaining('Limits stay the Pro Plus limits')),
          findsOneWidget,
        );
        expect(
          list.inDialog(find.textContaining('for 12 months')),
          findsWidgets,
          reason: 'the org\'s current term (yearly) is preselected',
        );
      },
    );

    testWidgets('a catalog that failed to load says so — never "nothing is '
        'published"', (tester) async {
      await openGrant(tester, plans: const []);
      await tester.tap(list.inDialog(find.text('Close')));
      await list.settle(tester);
      Get.find<SubscriptionController>().loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.offline,
        message: 'Could not reach Firestore.',
      );
      await tester.tap(find.text('Record payment').first);
      await list.settle(tester);
      expect(
        list.inDialog(find.text('The plan catalog could not be loaded')),
        findsOneWidget,
      );
      expect(list.inDialog(find.text('No plan can be recorded')), findsNothing);
    });

    testWidgets('a switched-off-while-paid organization is warned that a '
        'payment ADDS a term', (tester) async {
      await openGrant(
        tester,
        plans: [dualPlan()],
        org: list.org(id: 'paid', orgName: 'Paid Gym', subActive: false),
      );
      expect(
        list.inDialog(
          find.textContaining('switched off although it is paid until'),
        ),
        findsOneWidget,
      );
    });
  });

  group('grant outcomes, in plain words', () {
    String friendly(Object e) => OrgModerationService.friendlyError(e);

    test('price_changed → nothing recorded, the new price named', () {
      final v = ActionOutcomes.grantFailed(
        ffe(
          'failed-precondition',
          details: {
            'reason': 'price_changed',
            'listPrice': 1499,
            'listTermMonths': 1,
          },
        ),
        reference: 'UTR-1',
        friendly: friendly,
      );
      expect(v.title, 'The plan price changed — nothing recorded');
      expect(v.message, contains('₹1,499 for 1 month'));
      expect(v.changed, isFalse);
    });

    test('reference_already_recorded on THIS org is "already recorded", not '
        '"Payment not recorded"', () {
      final same = ActionOutcomes.grantFailed(
        ffe(
          'failed-precondition',
          details: {
            'reason': 'reference_already_recorded',
            'sameOrganization': true,
            'recordedAt': '2026-09-20T10:00:00.000Z',
          },
        ),
        reference: 'UTR-1',
        friendly: friendly,
      );
      expect(same.title, 'Already recorded on this organization');
      expect(same.ok, isTrue);
      expect(same.message, contains('first attempt went through'));
      final other = ActionOutcomes.grantFailed(
        ffe(
          'failed-precondition',
          details: {
            'reason': 'reference_already_recorded',
            'sameOrganization': false,
          },
        ),
        reference: 'UTR-1',
        friendly: friendly,
      );
      expect(other.title, 'Reference already used on another organization');
      expect(other.ok, isFalse);
    });

    test('the DEPLOYED backend\'s bare message is not "Payment not recorded… '
        'Nothing was changed"', () {
      final v = ActionOutcomes.grantFailed(
        ffe(
          'failed-precondition',
          msg: 'This payment reference was already recorded.',
        ),
        reference: 'UTR-1',
        friendly: friendly,
      );
      expect(v.title, 'Reference already recorded');
      expect(v.title, isNot('Payment not recorded'));
      expect(v.message, contains('earlier attempt may be the one'));
    });

    test('activated_online, a deleted plan, and a definite refusal', () {
      expect(
        ActionOutcomes.grantFailed(
          ffe('failed-precondition', details: {'reason': 'activated_online'}),
          reference: 'pay_ABC123',
          friendly: friendly,
        ).title,
        'Already activated online',
      );
      final plan = ActionOutcomes.grantFailed(
        ffe('not-found', msg: 'Plan not found.'),
        reference: 'r',
        friendly: friendly,
      );
      expect(plan.message, contains('plan was deleted'));
      expect(plan.message, isNot(contains('organization no longer exists')));
      final blocked = ActionOutcomes.grantFailed(
        ffe('failed-precondition', msg: 'This organization is blocked.'),
        reference: 'r',
        friendly: friendly,
      );
      expect(blocked.title, 'Payment not recorded');
      expect(blocked.changed, isFalse);
    });

    test('a lost response is "outcome unknown" — never "not recorded"', () {
      for (final e in [
        ffe('unavailable'),
        ffe('internal'),
        ffe('deadline-exceeded'),
        ffe('unavailable', details: {'outcome': 'unknown'}),
        Exception('offline'),
      ]) {
        final v = ActionOutcomes.grantFailed(
          e,
          reference: 'r',
          friendly: friendly,
        );
        expect(v.title, 'Payment outcome unknown', reason: '$e');
        expect(v.changed, isNull);
        expect(v.message, contains(ActionOutcomes.cannotTell));
        expect(v.message, contains('SAME reference is safe'));
      }
    });

    testWidgets('a replayed grant reports "nothing new was charged or '
        'extended"', (tester) async {
      list.mount(rows: [list.org(id: 'ok')]);
      list.ctrl.grantCall =
          ({
            required adminUid,
            required planId,
            required months,
            required reference,
            required amount,
            expectedListPrice,
          }) async => const GrantResult(
            replayed: true,
            expiry: '2027-01-01T00:00:00.000Z',
          );
      await list.pump(tester);
      await list.ctrl.grantSubscription(
        org: list.ctrl.byId('ok')!,
        planId: 'p',
        planName: 'Growth',
        months: 1,
        reference: 'UTR-1',
        amount: 4999,
      );
      await list.settle(tester);
      expect(find.text('Already recorded'), findsOneWidget);
      expect(
        find.textContaining('nothing new was charged or extended'),
        findsOneWidget,
      );
      expect(find.text('Payment recorded'), findsNothing);
    });

    testWidgets(
      'the success banner claims a notification only as best effort',
      (tester) async {
        list.mount(rows: [list.org(id: 'ok')]);
        await list.pump(tester);
        await list.ctrl.grantSubscription(
          org: list.ctrl.byId('ok')!,
          planId: 'p',
          planName: 'Growth',
          months: 1,
          reference: 'UTR-1',
          amount: 4999,
        );
        await list.settle(tester);
        expect(find.textContaining('(best effort)'), findsOneWidget);
        expect(find.textContaining('the owner notified'), findsNothing);
      },
    );
  });

  group('receipt coverage honesty (ORG-7)', () {
    SubscriptionModel receipt(Map<String, dynamic> m) =>
        SubscriptionModel.fromMap('r', {'adminUid': 'ok', ...m});

    test('an early renewal covers coverageStart → expiry and says so', () {
      final r = receipt({
        'amount': 9999,
        'months': 12,
        'startedAt': '2026-09-25T00:00:00.000Z',
        'expiry': '2027-12-01T00:00:00.000Z',
        'coverageStart': '2026-12-01T00:00:00.000Z',
        'previousExpiry': '2026-12-01T00:00:00.000Z',
        'previousPlanName': 'Growth',
        'previousSubscriptionActive': true,
        'pricing': {
          'basis': 'plan_term',
          'listPrice': 9999,
          'listTermMonths': 12,
          'term': 'yearly',
          'discount': 0,
          'overpayment': 0,
        },
      });
      expect(r.hasCoverageEvidence, isTrue);
      expect(
        OrganizationLanguage.receiptCoverageLine(r),
        'Covers 1 Dec 2026 → 1 Dec 2027',
      );
      final detail = OrganizationLanguage.receiptCoverageDetail(r);
      expect(detail, startsWith('Early renewal'));
      expect(detail, contains('1 Dec 2026'));
      expect(detail, contains('previous plan Growth'));
      expect(r.pricingTerm, 'yearly');
      expect(
        OrganizationLanguage.receiptPricingLine(r),
        'at list price (yearly term)',
      );
    });

    test('a fresh start with no previous end date says so', () {
      final r = receipt({
        'startedAt': '2026-09-25T00:00:00.000Z',
        'expiry': '2026-10-25T00:00:00.000Z',
        'coverageStart': '2026-09-25T00:00:00.000Z',
        'previousExpiry': null,
      });
      expect(
        OrganizationLanguage.receiptCoverageDetail(r),
        startsWith('Started fresh: no previous end date'),
      );
    });

    test('a legacy receipt keeps the "not recorded" honesty', () {
      final r = receipt({'amount': 100});
      expect(
        OrganizationLanguage.receiptCoverageLine(r),
        'Term dates not recorded',
      );
      expect(OrganizationLanguage.receiptCoverageDetail(r), '');
    });

    test('a manual receipt prints its reference; a legacy checkout receipt is '
        'not "collected outside the platform" (ORG-20)', () {
      final manual = receipt({
        'amount': 999,
        'method': 'manual',
        'reference': 'UTR-9',
      });
      expect(manual.reference, 'UTR-9');
      expect(
        OrganizationLanguage.fromReceipt(manual).detail,
        contains('ref UTR-9'),
      );
      final legacy = receipt({'amount': 999, 'paymentId': 'pay_ABC'});
      expect(legacy.isLegacyGatewayReceipt, isTrue);
      expect(
        OrganizationLanguage.receiptState(legacy),
        ReceiptState.legacyGateway,
      );
      expect(
        OrganizationLanguage.receiptState(legacy).meaning,
        isNot(contains('outside the platform')),
      );
      expect(OrganizationLanguage.canRefund(legacy), isFalse);
      final manualPay = receipt({
        'amount': 999,
        'method': 'manual',
        'reference': 'pay_ABC',
        'paymentId': 'pay_ABC',
      });
      expect(manualPay.isLegacyGatewayReceipt, isFalse);
    });
  });
}
