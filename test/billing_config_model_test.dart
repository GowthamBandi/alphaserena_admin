// ADD TAX — the console half of the platform tax contract.
//
// 🔴 WHY THIS SUITE EXISTS. The "Billing & taxes" editor at the top of the
// Subscription Plans screen wrote `platform_billing/config` directly from the
// client. That collection is declared in no ruleset and the rules file has no
// wildcard fallback, so every read and write was default-denied: the dialog
// could not load and could not save. The error handler guessed at the cause and
// blamed a missing deployment, which sent the investigation at a Cloud Function
// that was never involved.
//
// Underneath that sat the defect that would have survived a rules fix: the
// billing engine prices from `platform_config/commerce`, and its
// `normalizeTaxRules` has no concept of `enabled`. So the master switch and the
// per-rule kill switches were about to become decorative.
//
// These tests pin the CLIENT side of the repair — the document the editor
// reads, the payload it sends, and the arithmetic it previews. The server side
// is pinned by `functions/test/commerce_config.test.mjs`, and the numbers below
// are deliberately the same ones, so a change to either half that breaks
// agreement fails here.
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena_admin_portel/models/billing_config_model.dart';

Map<String, dynamic> tax({
  String name = 'GST',
  String label = '',
  num percent = 18,
  bool inclusive = false,
  bool enabled = true,
}) => {
  'name': name,
  'label': label,
  'percent': percent,
  'inclusive': inclusive,
  'enabled': enabled,
};

void main() {
  group('the editor reads the AUTHORED table, never the levied one', () {
    test('authoredTaxes wins when both arrays are present', () {
      // The stored doc holds both: `taxes` is pre-filtered for the engine and
      // `authoredTaxes` is what the founder typed. Reading the wrong one
      // silently deletes every retired rule on the next save.
      final cfg = BillingConfigModel.fromMap({
        'enabled': true,
        'currency': 'INR',
        'taxes': [tax()],
        'authoredTaxes': [tax(), tax(name: 'VAT', percent: 5, enabled: false)],
      });

      expect(cfg.taxes.map((t) => t.name), ['GST', 'VAT']);
      expect(
        cfg.taxes[1].enabled,
        isFalse,
        reason: 'the retired rule must survive a load/save round trip',
      );
    });

    test('a pre-split document still loads from taxes', () {
      // Back-compat: without this fallback the first load after the change
      // shows an empty editor, and the first save wipes the live table.
      final cfg = BillingConfigModel.fromMap({
        'enabled': true,
        'currency': 'INR',
        'taxes': [tax()],
      });
      expect(cfg.taxes.single.name, 'GST');
    });

    test('a document with neither array loads as untaxed, not as an error', () {
      final cfg = BillingConfigModel.fromMap(const {});
      expect(cfg.enabled, isFalse);
      expect(cfg.taxes, isEmpty);
      expect(cfg.currency, 'INR');
      expect(cfg.liveTaxes, isEmpty);
    });
  });

  group('the callable payload', () {
    test('carries the authored rules including the retired ones', () {
      final cfg = BillingConfigModel(
        enabled: true,
        taxes: const [
          TaxRule(name: 'GST', percent: 18),
          TaxRule(name: 'VAT', percent: 5, enabled: false),
        ],
      );
      final payload = cfg.toPayload();

      expect(payload['enabled'], isTrue);
      expect(payload['currency'], 'INR');
      expect((payload['taxes'] as List).length, 2);
      expect((payload['taxes'] as List)[1]['enabled'], isFalse);
    });

    test('is plain JSON — a FieldValue would fail the callable encoder', () {
      final payload = BillingConfigModel(
        enabled: true,
        taxes: const [TaxRule(name: 'GST', percent: 18)],
      ).toPayload();

      expect(
        payload.containsKey('updatedAt'),
        isFalse,
        reason:
            'the server stamps this; a FieldValue cannot cross a '
            'callable boundary',
      );
      for (final v in payload.values) {
        expect(v, anyOf(isA<bool>(), isA<String>(), isA<num>(), isA<List>()));
      }
    });

    test('uppercases and trims the currency before it leaves the client', () {
      final payload = const BillingConfigModel(currency: ' inr ').toPayload();
      expect(payload['currency'], 'INR');
    });
  });

  group('liveTaxes agrees with the server effectiveTaxes filter', () {
    test('master switch OFF makes every rule inert', () {
      const cfg = BillingConfigModel(
        enabled: false,
        taxes: [TaxRule(name: 'GST', percent: 18)],
      );
      expect(cfg.liveTaxes, isEmpty);
      expect(cfg.exclusivePercent, 0);
    });

    test('a retired, unnamed or zero-rate rule is not live', () {
      const cfg = BillingConfigModel(
        enabled: true,
        taxes: [
          TaxRule(name: 'GST', percent: 18),
          TaxRule(name: 'VAT', percent: 5, enabled: false),
          TaxRule(name: '  ', percent: 9),
          TaxRule(name: 'ZERO', percent: 0),
        ],
      );
      expect(cfg.liveTaxes.map((t) => t.name), ['GST']);
      expect(cfg.exclusivePercent, 18);
    });

    test('inclusive and exclusive rates are kept apart', () {
      const cfg = BillingConfigModel(
        enabled: true,
        taxes: [
          TaxRule(name: 'GST', percent: 18),
          TaxRule(name: 'SERVICE', percent: 5, inclusive: true),
        ],
      );
      expect(cfg.exclusivePercent, 18);
      expect(cfg.inclusivePercent, 5);
    });
  });

  group('validation mirrors the server gate', () {
    BillingConfigModel cfg(
      List<TaxRule> taxes, {
      bool enabled = true,
      String currency = 'INR',
    }) =>
        BillingConfigModel(enabled: enabled, currency: currency, taxes: taxes);

    test('a well-formed config passes', () {
      expect(
        cfg(const [TaxRule(name: 'GST', percent: 18)]).validate(),
        isEmpty,
      );
    });

    test('a blank name is reported', () {
      expect(
        cfg(const [TaxRule(name: ' ', percent: 18)]).validate(),
        contains('Every tax needs a name.'),
      );
    });

    test('duplicate names are caught case-insensitively', () {
      final errors = cfg(const [
        TaxRule(name: 'GST', percent: 18),
        TaxRule(name: 'gst', percent: 9),
      ]).validate();
      expect(errors.any((e) => e.contains('both named')), isTrue);
    });

    test('a zero or above-100 rate is refused', () {
      expect(
        cfg(const [
          TaxRule(name: 'GST', percent: 0),
        ]).validate().any((e) => e.contains('greater than 0')),
        isTrue,
      );
      expect(
        cfg(const [
          TaxRule(name: 'GST', percent: 101),
        ]).validate().any((e) => e.contains('above 100%')),
        isTrue,
      );
    });

    test('tax ON with nothing live is refused rather than stored inert', () {
      expect(
        cfg(const [
          TaxRule(name: 'GST', percent: 18, enabled: false),
        ]).validate().any((e) => e.contains('no rule is live')),
        isTrue,
      );
    });

    test('a non-3-letter currency is refused', () {
      expect(
        cfg(const [
          TaxRule(name: 'GST', percent: 18),
        ], currency: 'IN').validate().any((e) => e.contains('3-letter')),
        isTrue,
      );
    });
  });

  group('the buyer-facing label is derived the same way as the server', () {
    test('a blank label falls back to "Name (X%)"', () {
      expect(const TaxRule(name: 'GST', percent: 18).displayLabel, 'GST (18%)');
    });

    test('a fractional rate keeps its decimal', () {
      expect(
        const TaxRule(name: 'CESS', percent: 2.5).displayLabel,
        'CESS (2.5%)',
      );
    });

    test('an explicit label is used verbatim', () {
      expect(
        const TaxRule(
          name: 'GST',
          label: 'Goods & Services Tax',
          percent: 18,
        ).displayLabel,
        'Goods & Services Tax',
      );
    });
  });
}
