// ORG-2 / REF-13 / C1 / ORG-6 / ORG-15 / REF-12 — REFUNDS, SAID HONESTLY.
//
// 🔴 The Revenue door titled EVERY callable error "Refund failed" and kept
// the dialog open over a maximum captured at open time. After a lost
// response (the gateway HAD refunded) a press more than two minutes later
// passed the server's time-based lock and a second partial left: ₹1,000
// refunded for one ₹500 decision. The workspace door titled the same unknown
// outcome "Refund not issued".
//
// Now: both doors send a client refund INTENT (once per dialog opening,
// reused on retry), share ONE verdict (ActionOutcomes), never title an
// unknown outcome "failed" / "not issued", close the dialog on it, and the
// next opening recomputes the maximum from the live receipt. Receipts carry
// a per-refund ledger shown with amount / status / source / date, refunds
// are History events at their own time, and every amount is paise-exact.

import 'dart:io';

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/payments_controller.dart';
import 'package:alphaserena_admin_portel/core/services/action_outcomes.dart';
import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/core/services/refund_service.dart';
import 'package:alphaserena_admin_portel/core/services/revenue_engine.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:alphaserena_admin_portel/screens/payments_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organization_workspace_behaviour_test.dart' as w;
import 'organizations_screen_behaviour_test.dart' as list;

FirebaseFunctionsException ffe(String code, {Object? details, String? msg}) =>
    FirebaseFunctionsException(
      code: code,
      message: msg ?? code,
      details: details,
    );

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

class OfflinePayments extends PaymentsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

SubscriptionModel onlineReceipt({
  String id = 'h1',
  num amount = 2000,
  Map<String, dynamic>? refund,
  Map<String, dynamic>? refunds,
}) => SubscriptionModel.fromMap(id, {
  'adminUid': 'ok',
  'planName': 'Growth',
  'amount': amount,
  'razorpayPaymentId': 'pay_1',
  'createdAt': list.now.subtract(const Duration(days: 30)).toIso8601String(),
  if (refund != null) 'refund': refund,
  if (refunds != null) 'refunds': refunds,
});

void main() {
  tearDown(Get.reset);

  group('ONE refund verdict (C2) — unknown is never "failed"', () {
    test(
      'definite refusals: not refunded, dialog stays open, no money moved',
      () {
        for (final code in [
          'failed-precondition',
          'invalid-argument',
          'not-found',
          'permission-denied',
          'unauthenticated',
          'resource-exhausted',
        ]) {
          final o = ActionOutcomes.refundFailed(
            ffe(code, details: {'outcome': 'not_refunded'}),
          );
          expect(o.verdict, RefundVerdict.notRefunded, reason: code);
          expect(o.closesDialog, isFalse, reason: code);
          expect(o.changed, isFalse, reason: code);
          expect(o.message, contains('No money moved'), reason: code);
        }
      },
    );

    test('already-exists is IN FLIGHT: not a failure, dialog closes', () {
      final o = ActionOutcomes.refundFailed(
        ffe('already-exists', details: {'outcome': 'in_flight'}),
      );
      expect(o.verdict, RefundVerdict.inFlight);
      expect(o.title.toLowerCase(), isNot(contains('fail')));
      expect(o.title, 'A refund is already in progress');
      expect(o.closesDialog, isTrue);
      expect(o.changed, isNull);
    });

    test('unavailable + not_attempted: nothing moved, retry allowed', () {
      final o = ActionOutcomes.refundFailed(
        ffe('unavailable', details: {'outcome': 'not_attempted'}),
      );
      expect(o.verdict, RefundVerdict.notAttempted);
      expect(o.closesDialog, isFalse);
      expect(o.message, contains('No money moved'));
    });

    test('unavailable(unknown) / internal / deadline / network → OUTCOME '
        'UNKNOWN, never "failed" or "not issued", and the dialog closes', () {
      final cases = <Object>[
        ffe('unavailable', details: {'outcome': 'unknown'}),
        ffe('unavailable'),
        ffe('internal', msg: 'Refund failed at the gateway.'),
        ffe('deadline-exceeded'),
        ffe('unknown'),
        Exception('socket closed'),
      ];
      for (final e in cases) {
        final o = ActionOutcomes.refundFailed(e);
        expect(o.verdict, RefundVerdict.unknown, reason: '$e');
        expect(o.title, 'Refund outcome unknown', reason: '$e');
        expect(o.title.toLowerCase(), isNot(contains('fail')));
        expect(o.title.toLowerCase(), isNot(contains('not issued')));
        expect(o.message, contains('Do NOT refund again'), reason: '$e');
        expect(o.closesDialog, isTrue, reason: '$e');
        expect(o.changed, isNull, reason: '$e');
      }
      expect(
        ActionOutcomes.refundFailed(
          ffe('unavailable', details: {'outcome': 'unknown'}),
        ).message,
        contains('Operations Center'),
      );
    });

    test('success words come from the server; warnings are translated', () {
      final ok = ActionOutcomes.refundSucceeded(
        const RefundResult(
          refundId: 'rfnd_1',
          amount: 1178.82,
          amountMinor: 117882,
          status: 'processed',
          revoked: true,
          warnings: ['history_stamp_failed', 'revoke_failed', 'brand_new'],
        ),
      );
      expect(ok.verdict, RefundVerdict.refunded);
      expect(ok.message, contains('₹1,178.82'));
      expect(ok.message, contains('NOT updated yet'));
      expect(ok.message, isNot(contains('The receipt was updated')));
      expect(ok.message, contains('still has access'));
      expect(ok.message, contains('does not recognise'));
      expect(
        ok.message.contains('revoke_failed'),
        isFalse,
        reason: 'a known code is never printed raw',
      );
      final clean = ActionOutcomes.refundSucceeded(
        const RefundResult(refundId: 'r', amount: 500, status: 'created'),
      );
      expect(clean.message, contains('The receipt was updated'));
      expect(clean.message, contains('gateway accepted it'));
      final replay = ActionOutcomes.refundSucceeded(
        const RefundResult(
          refundId: 'r',
          amount: 500,
          status: 'processed',
          replayed: true,
        ),
      );
      expect(replay.title, 'Refund already issued');
      expect(replay.message, contains('Nothing new was sent'));
    });

    test('RefundResult reads amountMinor / replayed; intent ids are valid', () {
      final r = RefundResult.fromMap({
        'refundId': 'rfnd_9',
        'amount': 500.5,
        'amountMinor': 50050,
        'status': 'processed',
        'replayed': true,
        'warnings': ['a'],
      });
      expect(r.amountMinor, 50050);
      expect(r.replayed, isTrue);
      final a = ActionOutcomes.newRefundIntentId();
      final b = ActionOutcomes.newRefundIntentId();
      expect(ActionOutcomes.isValidIntentId(a), isTrue);
      expect(a, isNot(b));
    });
  });

  group('the Revenue door (PaymentsController)', () {
    test(
      'a lost response is UNKNOWN, carries the intent, raises no snackbar',
      () async {
        final c = OfflinePayments();
        String? sentIntent;
        c.refundCall =
            ({
              required paymentId,
              required historyDocId,
              amount,
              reason,
              revokeAccess = false,
              intentId,
            }) async {
              sentIntent = intentId;
              throw ffe('deadline-exceeded');
            };
        final o = await c.refundPayment(
          onlineReceipt(),
          amount: 500,
          reason: 'dup',
          intentId: 'rf_test_intent_1',
        );
        expect(sentIntent, 'rf_test_intent_1');
        expect(o.verdict, RefundVerdict.unknown);
        expect(o.closesDialog, isTrue);
        expect(c.isRefunding.value, isFalse);
      },
    );

    test('source guard: the controller raises no snackbar of its own', () {
      final src = _strip(
        File('lib/controllers/payments_controller.dart').readAsStringSync(),
      );
      expect(src.contains('Get.snackbar('), isFalse);
      expect(src.contains('"Refund failed"'), isFalse);
      expect(src.contains('ActionOutcomes.refundFailed(e)'), isTrue);
    });

    test('Payments search finds a manual receipt by its reference (ORG-3)', () {
      final c = OfflinePayments();
      c.subscriptions.assignAll([
        SubscriptionModel.fromMap('m1', {
          'adminUid': 'ok',
          'amount': 999,
          'method': 'manual',
          'reference': 'UTR-77',
        }),
        onlineReceipt(),
      ]);
      c.searchQuery.value = 'utr-77';
      expect(c.filteredList.map((s) => s.id), ['m1']);
    });
  });

  group('the Revenue refund dialog (REF-13 + intent)', () {
    Future<(OfflinePayments, List<String?>)> openDialog(
      WidgetTester tester,
      SubscriptionModel receipt, {
      required List<Object> answers,
    }) async {
      final c =
          Get.put<PaymentsController>(OfflinePayments(), permanent: true)
              as OfflinePayments;
      c.subscriptions.assignAll([receipt]);
      final intents = <String?>[];
      var i = 0;
      c.refundCall =
          ({
            required paymentId,
            required historyDocId,
            amount,
            reason,
            revokeAccess = false,
            intentId,
          }) async {
            intents.add(intentId);
            final a = answers[i++];
            if (a is RefundResult) return a;
            throw a;
          };
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      Get.dialog(
        PaymentsRefundDialog(
          ctrl: c,
          receiptId: receipt.id,
          initial: receipt,
          orgLabel: 'Iron Temple',
        ),
        barrierDismissible: false,
      );
      await tester.pumpAndSettle();
      return (c, intents);
    }

    testWidgets(
      'a definite refusal keeps the dialog open; the retry REUSES the intent',
      (tester) async {
        final (_, intents) = await openDialog(
          tester,
          onlineReceipt(),
          answers: [
            ffe('failed-precondition', msg: 'Only ₹1,500 is refundable.'),
            const RefundResult(
              refundId: 'r',
              amount: 2000,
              status: 'processed',
            ),
          ],
        );
        await tester.enterText(find.byType(TextField).last, 'duplicate');
        await tester.pump();
        await tester.tap(find.text('Refund'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentsRefundDialog), findsOneWidget);
        expect(
          find.textContaining('Only ₹1,500 is refundable'),
          findsOneWidget,
        );
        await tester.tap(find.text('Refund'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentsRefundDialog), findsNothing);
        expect(intents.length, 2);
        expect(intents[0], isNotNull);
        expect(intents[0], intents[1], reason: 'same dialog → same intent');
        expect(find.text('Refund issued'), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'an UNKNOWN outcome CLOSES the dialog and is never titled failed',
      (tester) async {
        await openDialog(tester, onlineReceipt(), answers: [ffe('internal')]);
        await tester.enterText(find.byType(TextField).last, 'duplicate');
        await tester.pump();
        await tester.tap(find.text('Refund'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentsRefundDialog), findsNothing);
        expect(find.text('Refund outcome unknown'), findsOneWidget);
        expect(find.textContaining('Refund failed'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'the maximum comes from the LIVE receipt at open, paise-exact; a new '
      'opening is a new intent',
      (tester) async {
        final stale = onlineReceipt(amount: 1178.82);
        final live = onlineReceipt(
          amount: 1178.82,
          refund: {'amountMinor': 50000, 'amount': 500},
        );
        final (c, intents) = await openDialog(
          tester,
          stale,
          answers: [ffe('failed-precondition'), ffe('failed-precondition')],
        );
        // The first opening saw the stale copy (the list held it).
        expect(find.textContaining('₹1,178.82'), findsWidgets);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        c.subscriptions.assignAll([live]);
        Get.dialog(
          PaymentsRefundDialog(
            ctrl: c,
            receiptId: live.id,
            initial: stale, // the row may still hold the stale copy
            orgLabel: 'Iron Temple',
          ),
          barrierDismissible: false,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Full refund · ₹678.82'), findsOneWidget);
        await tester.tap(find.text('Partial'));
        await tester.pump();
        expect(find.textContaining('whole ₹, 1–678'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '679');
        await tester.enterText(find.byType(TextField).last, 'r');
        await tester.pump();
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull,
          reason: 'above the live remainder',
        );
        await tester.enterText(find.byType(TextField).first, '678');
        await tester.pump();
        await tester.tap(find.text('Refund'));
        await tester.pumpAndSettle();
        expect(intents.length, 1);
        expect(intents.single, isNotNull);
      },
    );

    testWidgets(
      'REF-13: closing with a focused field disposes nothing still in use',
      (tester) async {
        await openDialog(tester, onlineReceipt(), answers: const []);
        await tester.tap(find.text('Partial'));
        await tester.pump();
        await tester.showKeyboard(find.byType(TextField).first);
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.tap(find.text('Cancel'));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(PaymentsRefundDialog), findsNothing);
      },
    );

    test('source guard: no dialog disposes its controllers in a .then', () {
      final src = _strip(
        File('lib/screens/payments_screen.dart').readAsStringSync(),
      );
      expect(src.contains('.then((_)'), isFalse);
      expect(
        src.contains('class PaymentsRefundDialog extends StatefulWidget'),
        isTrue,
      );
      expect(src.contains('ActionOutcomes.newRefundIntentId()'), isTrue);
    });
  });

  group('the workspace door (AdminController.refund)', () {
    testWidgets(
      'sends the dialog intent; an unknown outcome is "outcome unknown", '
      'never "Refund not issued"',
      (tester) async {
        final a = AdminModel(
          docId: 'ok',
          uid: 'ok',
          name: 'Arjun',
          email: 'a@b.in',
          phone: '',
          organizationName: 'Iron Temple',
          role: 'admin',
          status: 'active',
          isSubscriptionActive: true,
          planExpiry: w.now.add(const Duration(days: 40)),
          subscription: const {'razorpayPaymentId': 'pay_1'},
          subscriptionLimits: AdminSubscriptionLimits.empty(),
          createdAt: w.now,
          updatedAt: w.now,
        );
        await w.open(
          tester,
          org: a,
          seed: (d) {
            w.seedHealthy(d, a);
            d.receipts.succeed([w.receipt(id: 'online', pay: 'pay_1')]);
          },
        );
        String? intent;
        int? sentAmount = -1;
        w.ctrl.refundCall =
            ({
              required paymentId,
              required historyDocId,
              amount,
              reason,
              revokeAccess = false,
              intentId,
            }) async {
              intent = intentId;
              sentAmount = amount;
              throw ffe('unavailable', details: {'outcome': 'unknown'});
            };
        await w.tab(tester, 'Subscription');
        await tester.tap(find.text('Refund…'));
        await list.settle(tester);
        await tester.enterText(w.inDialog(find.byType(TextField)).last, 'dup');
        await list.settle(tester);
        await tester.tap(w.inDialog(find.text('Refund')));
        await list.settle(tester);
        expect(intent, isNotNull);
        expect(ActionOutcomes.isValidIntentId(intent!), isTrue);
        expect(sentAmount, isNull, reason: 'a full refund sends no amount');
        expect(find.text('Refund outcome unknown'), findsOneWidget);
        expect(find.text('Refund not issued'), findsNothing);
        expect(find.textContaining('not known'), findsOneWidget);
      },
    );

    test('the stale comment claiming no compare-and-set is gone', () {
      final src = File(
        'lib/controllers/admin_controller.dart',
      ).readAsStringSync();
      expect(src.contains('has no compare-and-set'), isFalse);
      expect(src.contains('The gateway did not accept the refund'), isFalse);
    });
  });

  group('the receipt refund ledger (C1) and paise-exact money', () {
    test('ledger entries: amount, status, source, date; aggregate is the '
        "server's amountMinor", () {
      final r = onlineReceipt(
        amount: 4999,
        refund: {'amountMinor': 70000, 'amount': 700, 'count': 2},
        refunds: {
          'rfnd_b': {
            'amountMinor': 20000,
            'status': 'created',
            'counted': true,
            'source': 'gateway',
            'createdAt': DateTime(2026, 9, 20).toIso8601String(),
          },
          'rfnd_a': {
            'amountMinor': 50000,
            'status': 'processed',
            'counted': true,
            'source': 'console',
            'requestedBy': 'me',
            'intentId': 'rf_x_y',
            'createdAt': DateTime(2026, 9, 10).toIso8601String(),
          },
          'rfnd_c': {
            'amountMinor': 10000,
            'status': 'failed',
            'counted': false,
            'source': 'console',
            'createdAt': DateTime(2026, 9, 12).toIso8601String(),
            'failedAt': DateTime(2026, 9, 13).toIso8601String(),
          },
        },
      );
      expect(r.refundMinor, 70000);
      expect(r.netAmount, 4299);
      expect(r.refunds.map((x) => x.id), ['rfnd_a', 'rfnd_c', 'rfnd_b']);
      expect(
        OrganizationLanguage.refundLine(r.refunds[0]),
        '₹500 · processed · issued from this console · 10 Sep 2026',
      );
      expect(
        OrganizationLanguage.refundLine(r.refunds[2]),
        '₹200 · pending at the gateway · made in the Razorpay dashboard · 20 Sep 2026',
      );
      expect(
        OrganizationLanguage.refundLine(r.refunds[1]),
        contains('failed — no money left, not counted'),
      );
      expect(r.refunds[1].counted, isFalse);
    });

    test('a legacy receipt (no ledger) gets ONE synthesised entry from the '
        'rupee total', () {
      final r = onlineReceipt(
        amount: 2000,
        refund: {
          'id': 'rfnd_old',
          'amount': 500.5,
          'count': 2,
          'status': 'processed',
          'refundedBy': 'me',
          'refundedAt': DateTime(2026, 8, 1).toIso8601String(),
        },
      );
      expect(r.refundMinor, 50050);
      expect(r.refunds.single.legacy, isTrue);
      expect(r.refunds.single.id, 'rfnd_old');
      expect(r.refunds.single.amountMinor, 50050);
      expect(
        OrganizationLanguage.refundLine(r.refunds.single),
        contains('a total of 2 refunds'),
      );
    });

    test('amounts are paise-exact: strings, GST-inclusive totals, refunds', () {
      final s = SubscriptionModel.fromMap('x', {'amount': '999.50'});
      expect(s.amountMinor, 99950);
      expect(OrganizationLanguage.rupees(s.amountPaid), '₹999.50');
      final gst = onlineReceipt(amount: 1178.82, refund: {'amount': 1178});
      expect(gst.netMinor, 82);
      expect(gst.isFullyRefunded, isFalse);
      expect(OrganizationLanguage.maxPartialRefundRupees(gst), 0);
      expect(OrganizationLanguage.canRefund(gst), isTrue);
      expect(OrganizationLanguage.rupees(gst.netAmount), '₹0.82');
      expect(OrganizationLanguage.rupees(125000.5), '₹1,25,000.50');
      expect(OrganizationLanguage.rupees(double.nan), '₹—');
    });

    test('revenue sums in paise — no float drift', () {
      final ps = [
        for (var i = 0; i < 3; i++)
          SubscriptionModel.fromMap('p$i', {
            'adminUid': 'a',
            'amount': 0.1,
            'createdAt': w.now.toIso8601String(),
          }),
      ];
      final r = RevenueEngine.compute(ps, now: w.now);
      expect(r.totalRevenue, 0.3);
      expect(r.revenueByAdmin['a'], 0.3);
    });
  });

  group('refunds are History events at their own time (ORG-6)', () {
    String actor(String uid) => OrganizationLanguage.actor(
      uid,
      currentUid: 'me',
      staffName: (_) => null,
    );

    test('ledger refunds become dated events; matching audit "recorded" rows '
        'are not shown twice; the request row stays', () {
      final receipt = onlineReceipt(
        amount: 4999,
        refund: {'amountMinor': 50000},
        refunds: {
          'rfnd_a': {
            'amountMinor': 50000,
            'status': 'processed',
            'source': 'console',
            'requestedBy': 'me',
            'createdAt': DateTime(2026, 9, 10).toIso8601String(),
          },
        },
      );
      final audit = [
        AuditLogModel(
          id: 'req',
          actorUid: 'me',
          action: 'refund_payment',
          targetId: 'ok',
          details: {
            'paymentId': 'pay_1',
            'amount': 500,
            'requestedAmountRupees': 500,
            'reason': 'duplicate',
          },
          createdAt: DateTime(2026, 9, 10),
        ),
        AuditLogModel(
          id: 'rec',
          actorUid: 'me',
          action: 'refund_recorded',
          targetId: 'ok',
          details: {'refundId': 'rfnd_a', 'amountMinor': 50000},
          createdAt: DateTime(2026, 9, 10),
        ),
        AuditLogModel(
          id: 'fail',
          actorUid: 'razorpay_webhook',
          action: 'subscription_refund_failed',
          targetId: 'ok',
          details: {'refundId': 'rfnd_other', 'amountMinor': 1000},
          createdAt: DateTime(2026, 9, 11),
        ),
      ];
      final events = OrganizationLanguage.historyEvents(
        audit: audit,
        requests: const [],
        receipts: [receipt],
        actorOf: actor,
      );
      final titles = events.map((e) => e.title).toList();
      expect(titles, contains('Refund requested from the console'));
      expect(titles, contains('Refund · ₹500'));
      expect(titles, isNot(contains('Refund recorded')));
      expect(titles, contains('A refund failed at the gateway'));
      final refundEvent = events.firstWhere((e) => e.title == 'Refund · ₹500');
      expect(refundEvent.at, DateTime(2026, 9, 10));
      expect(refundEvent.actor, 'you');
      expect(
        events
            .firstWhere((e) => e.title == 'Refund requested from the console')
            .detail,
        contains('₹500'),
      );
      expect(
        events
            .firstWhere((e) => e.title == 'A refund failed at the gateway')
            .actor,
        'the Razorpay webhook',
      );
    });

    test('refund audit amounts: amountMinor, amount, legacy requested', () {
      expect(
        OrganizationLanguage.refundAuditAmount({'amountMinor': 117882}),
        '₹1,178.82',
      );
      expect(OrganizationLanguage.refundAuditAmount({'amount': 500}), '₹500');
      expect(
        OrganizationLanguage.refundAuditAmount({'amount': null, 'full': true}),
        'full refund',
      );
      expect(
        OrganizationLanguage.refundAuditAmount({'requestedAmountRupees': 0}),
        'full refund',
      );
      expect(
        OrganizationLanguage.refundAuditAmount({'requestedAmountRupees': 250}),
        '₹250',
      );
    });

    test('a refund made in the Razorpay dashboard is named as such', () {
      final r = onlineReceipt(
        refunds: {
          'rfnd_g': {
            'amountMinor': 100000,
            'status': 'processed',
            'source': 'gateway',
            'createdAt': DateTime(2026, 9, 1).toIso8601String(),
          },
        },
      );
      final e = OrganizationLanguage.refundEvents(r, actorOf: (u) => u).single;
      expect(e.title, 'Refund made in the Razorpay dashboard · ₹1,000');
      expect(e.actor, 'the Razorpay dashboard');
    });

    testWidgets('the workspace receipt row lists its refunds', (tester) async {
      await w.open(
        tester,
        seed: (d) {
          w.seedHealthy(d, w.a_);
          d.receipts.succeed([
            onlineReceipt(
              amount: 4999,
              refund: {'amountMinor': 50000},
              refunds: {
                'rfnd_a': {
                  'amountMinor': 50000,
                  'status': 'processed',
                  'source': 'console',
                  'createdAt': DateTime(2026, 9, 1).toIso8601String(),
                },
              },
            ),
          ]);
        },
      );
      await w.tab(tester, 'Subscription');
      expect(
        find.textContaining(
          'Refund: ₹500 · processed · issued from this console',
        ),
        findsOneWidget,
      );
    });
  });
}
