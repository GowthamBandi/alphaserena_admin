// ORGANIZATIONS — COMMERCIAL INTEGRITY.
//
// The founder console records what was COLLECTED; the server owns the
// price, the discount, the expiry and the limits. These tests pin the
// client half of that contract: the receipt model states only what the
// record carries, the grant preview mirrors the server's evidence rule for
// display, the moderation call carries the founder's expectation, and the
// dialog cannot slip a differing amount or a negotiated term past the founder
// without an explicit acknowledgement. Source guards at the end make the
// invariants fail loudly if reintroduced.

import 'dart:io';

import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/core/services/saas_onboarding_service.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 25, 12);

SubscriptionModel receipt(Map<String, dynamic> m) =>
    SubscriptionModel.fromMap('r1', {'adminUid': 'ok', ...m});

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

void main() {
  group('receipt model states only what the record carries', () {
    test(
      'a legacy receipt with no dates or term does not invent a 30-day term',
      () {
        final r = receipt({'amount': 4999, 'planName': 'Growth'});
        expect(r.startKnown, isFalse);
        expect(r.expiryKnown, isFalse);
        expect(r.termKnown, isFalse);
        expect(
          OrganizationLanguage.receiptCoverageLine(r),
          'Term dates not recorded',
        );
        expect(
          OrganizationLanguage.fromReceipt(r).detail,
          contains('term not recorded'),
        );
        expect(
          OrganizationLanguage.fromReceipt(r).technical['expiryAt'],
          'not recorded',
        );
      },
    );

    test('a LEGACY receipt with dates says when it was paid and until when — '
        'never a "Covers" span it cannot prove (ORG-7)', () {
      final r = receipt({
        'amount': 4999,
        'months': 12,
        'startedAt': '2026-09-01T00:00:00.000Z',
        'expiry': '2027-09-01T00:00:00.000Z',
      });
      expect(r.termKnown, isTrue);
      expect(r.hasCoverageEvidence, isFalse);
      final line = OrganizationLanguage.receiptCoverageLine(r);
      expect(line, startsWith('Paid 1 Sep 2026 · runs until 1 Sep 2027'));
      expect(line, contains('coverage start not recorded'));
      expect(line, isNot(contains('Covers')));
    });

    test('pricing evidence is read from the server stamp, never inferred', () {
      final plain = receipt({'amount': 9999});
      expect(plain.hasPricingEvidence, isFalse);
      expect(OrganizationLanguage.receiptPricingLine(plain), '');
      final stamped = receipt({
        'amount': 9999,
        'pricing': {
          'basis': 'plan_term',
          'listPrice': 11999,
          'listTermMonths': 12,
          'discount': 2000,
          'overpayment': 0,
        },
      });
      expect(stamped.listPrice, 11999);
      expect(stamped.pricingDiscount, 2000);
      expect(
        OrganizationLanguage.receiptPricingLine(stamped),
        'list ₹11,999 · discount ₹2,000',
      );
      final over = receipt({
        'amount': 12500,
        'pricing': {
          'basis': 'plan_term',
          'listPrice': 11999,
          'listTermMonths': 12,
          'discount': 0,
          'overpayment': 501,
        },
      });
      expect(
        OrganizationLanguage.receiptPricingLine(over),
        'list ₹11,999 · ₹501 above list',
      );
      final neg = receipt({
        'amount': 7000,
        'pricing': {
          'basis': 'negotiated_term',
          'listPrice': 11999,
          'listTermMonths': 12,
        },
      });
      expect(
        OrganizationLanguage.receiptPricingLine(neg),
        contains('negotiated term'),
      );
      expect(
        OrganizationLanguage.receiptPricingLine(neg),
        contains('no discount computed'),
      );
      final unpriced = receipt({
        'amount': 100,
        'pricing': {'basis': 'unpriced'},
      });
      expect(
        OrganizationLanguage.receiptPricingLine(unpriced),
        contains('no list price'),
      );
    });

    test('an online receipt with a coupon names it', () {
      final r = receipt({
        'amount': 3999,
        'razorpayPaymentId': 'pay_1',
        'pricing': {
          'basis': 'plan_term',
          'listPrice': 4999,
          'listTermMonths': 1,
          'discount': 1000,
          'overpayment': 0,
          'coupon': 'LAUNCH20',
        },
      });
      expect(
        OrganizationLanguage.receiptPricingLine(r),
        'list ₹4,999 · discount ₹1,000 (coupon LAUNCH20)',
      );
    });
  });

  group('grant preview mirrors the server evidence rule (display only)', () {
    test('plan term: discount / overpayment / at list', () {
      final d = OrganizationLanguage.grantPreview(
        listPrice: 11999,
        listTermMonths: 12,
        months: 12,
        amount: 9999,
      );
      expect(d.basis, 'plan_term');
      expect(d.discount, 2000);
      expect(d.differsFromList, isTrue);
      final o = OrganizationLanguage.grantPreview(
        listPrice: 11999,
        listTermMonths: 12,
        months: 12,
        amount: 12500,
      );
      expect(o.overpayment, 501);
      final e = OrganizationLanguage.grantPreview(
        listPrice: 11999,
        listTermMonths: 12,
        months: 12,
        amount: 11999,
      );
      expect(e.differsFromList, isFalse);
      final c = OrganizationLanguage.grantPreview(
        listPrice: 11999,
        listTermMonths: 12,
        months: 12,
        amount: 0,
      );
      expect(c.isComped, isTrue);
    });

    test(
      'negotiated term computes no discount; unpriced plan claims nothing',
      () {
        final n = OrganizationLanguage.grantPreview(
          listPrice: 11999,
          listTermMonths: 12,
          months: 7,
          amount: 7000,
        );
        expect(n.basis, 'negotiated_term');
        expect(n.discount, isNull);
        final u = OrganizationLanguage.grantPreview(
          listPrice: null,
          listTermMonths: null,
          months: 12,
          amount: 500,
        );
        expect(u.basis, 'unpriced');
      },
    );

    test(
      'the grant base is max(now, planExpiry) — the flag does not change it',
      () {
        final future = now.add(const Duration(days: 20));
        final live = AdminModel.fromMap({
          'isSubscriptionActive': true,
          'planExpiry': future.toIso8601String(),
        }, 'a');
        final flagOff = AdminModel.fromMap({
          'isSubscriptionActive': false,
          'planExpiry': future.toIso8601String(),
        }, 'b');
        final lapsed = AdminModel.fromMap({
          'isSubscriptionActive': true,
          'planExpiry': now.subtract(const Duration(days: 2)).toIso8601String(),
        }, 'c');
        expect(OrganizationLanguage.grantBase(live, now: now), future);
        expect(OrganizationLanguage.grantBase(flagOff, now: now), future);
        expect(OrganizationLanguage.grantBase(lapsed, now: now), now);
      },
    );

    test('month arithmetic clamps the day like the backend', () {
      final jan31 = DateTime.utc(2026, 1, 31, 9);
      expect(
        OrganizationLanguage.addMonthsClamped(jan31, 1),
        DateTime.utc(2026, 2, 28, 9),
      );
      expect(
        OrganizationLanguage.addMonthsClamped(jan31, 12),
        DateTime.utc(2027, 1, 31, 9),
      );
    });
  });

  group('the outcome sentence repeats the SERVER figures', () {
    test('discount, overpayment, list, negotiated, unpriced', () {
      expect(
        OrganizationLanguage.pricingSentence(
          const GrantResult(
            pricingBasis: 'plan_term',
            listPrice: 11999,
            collected: 9999,
            discount: 2000,
            overpayment: 0,
          ),
        ),
        'Recorded ₹9,999 against a list price of ₹11,999 — a discount of ₹2,000 is on the receipt.',
      );
      expect(
        OrganizationLanguage.pricingSentence(
          const GrantResult(
            pricingBasis: 'plan_term',
            listPrice: 11999,
            collected: 12500,
            discount: 0,
            overpayment: 501,
          ),
        ),
        contains('₹501 above the list price'),
      );
      expect(
        OrganizationLanguage.pricingSentence(
          const GrantResult(
            pricingBasis: 'plan_term',
            listPrice: 11999,
            collected: 11999,
            discount: 0,
            overpayment: 0,
          ),
        ),
        'Recorded ₹11,999, the list price.',
      );
      expect(
        OrganizationLanguage.pricingSentence(
          const GrantResult(
            pricingBasis: 'negotiated_term',
            listPrice: 11999,
            listTermMonths: 12,
            collected: 7000,
          ),
        ),
        contains('negotiated term'),
      );
      expect(OrganizationLanguage.pricingSentence(const GrantResult()), '');
    });

    test('GrantResult parses the callable response shape', () {
      final r = GrantResult.fromMap({
        'expiry': '2027-09-25T00:00:00.000Z',
        'planName': 'Pro Annual',
        'pricing': {
          'basis': 'plan_term',
          'listPrice': 11999,
          'listTermMonths': 12,
          'collected': 9999,
          'discount': 2000,
          'overpayment': 0,
        },
      });
      expect(r.planName, 'Pro Annual');
      expect(r.discount, 2000);
      expect(r.listTermMonths, 12);
    });
  });

  group('source guards', () {
    final service = _strip(
      File('lib/core/services/saas_onboarding_service.dart').readAsStringSync(),
    );
    final moderation = _strip(
      File('lib/core/services/org_moderation_service.dart').readAsStringSync(),
    );
    final controller = _strip(
      File('lib/controllers/admin_controller.dart').readAsStringSync(),
    );
    final dashboard = _strip(
      File('lib/controllers/dashboard_controller.dart').readAsStringSync(),
    );
    final dialogs = _strip(
      File(
        'lib/screens/organization/organization_action_dialogs.dart',
      ).readAsStringSync(),
    );
    final workspace = _strip(
      File(
        'lib/screens/organization/organization_workspace.dart',
      ).readAsStringSync(),
    );

    test(
      'the grant payload carries no price, discount, expiry or limits — only what was collected',
      () {
        final call = service.substring(
          service.indexOf("httpsCallable('grantSubscription')"),
          service.indexOf('GrantResult.fromMap'),
        );
        for (final forbidden in [
          "'expiry'",
          "'planExpiry'",
          "'limits'",
          "'discount'",
          "'listPrice'",
          "'price'",
          "'features'",
        ]) {
          expect(
            call.contains(forbidden),
            isFalse,
            reason: 'grant payload must not send $forbidden',
          );
        }
        expect(call.contains("'amount': amount"), isTrue);
        expect(call.contains("'months': months"), isTrue);
      },
    );

    test('every moderation call states the founder\'s expectation', () {
      expect(
        moderation.contains("'expectedStatus': expectedStatus.trim()"),
        isTrue,
      );
      expect(
        controller.contains('expectedStatus: expectedStatus,'),
        isTrue,
        reason: 'Organizations must send its expectation',
      );
      expect(
        dashboard.contains('expectedStatus: OrgModerationService.pending'),
        isTrue,
        reason: 'the Dashboard approve/reject path must send its expectation',
      );
    });

    test(
      'the outcome banner reports the server pricing, not the dialog preview',
      () {
        expect(
          controller.contains('OrganizationLanguage.pricingSentence(r)'),
          isTrue,
        );
        expect(controller.contains('r.expiry'), isTrue);
      },
    );

    test(
      'the dialog requires an acknowledgement before recording a differing amount or term',
      () {
        expect(
          dialogs.contains('_needsAcknowledgement && !_acknowledgeDifference'),
          isTrue,
        );
        expect(dialogs.contains("basis == 'negotiated_term'"), isTrue);
      },
    );

    test(
      'receipts are on the history timeline and never printed with invented dates',
      () {
        final language = _strip(
          File(
            'lib/core/services/organization_language.dart',
          ).readAsStringSync(),
        );
        expect(
          workspace.contains('OrganizationLanguage.historyEvents('),
          isTrue,
        );
        final history = language.substring(
          language.indexOf('static List<OrgEvent> historyEvents('),
        );
        expect(history.contains('fromReceipt(r)'), isTrue);
        expect(history.contains('refundEvents(r'), isTrue);
        expect(workspace.contains('receiptCoverageLine(r)'), isTrue);
        expect(
          workspace.contains(
            "'Covers \${OrganizationLanguage.exact(r.startAt)}",
          ),
          isFalse,
        );
      },
    );

    test('the refund dialog never offers more than the net remaining', () {
      // Whole rupees for a PARTIAL (the callable's unit), from the paise-exact
      // remainder; a full refund sends no amount and returns the exact rest.
      expect(
        dialogs.contains(
          'int get _max => OrganizationLanguage.maxPartialRefundRupees(widget.receipt);',
        ),
        isTrue,
      );
      expect(dialogs.contains('a >= 1 && a <= _max'), isTrue);
    });
  });
}
