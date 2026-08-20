// THE FOUNDER'S PREVIEW MUST BE THE SERVER'S ARITHMETIC, NOT A REPHRASING.
//
// 🔴 THE DEFECT THIS GUARDS. `BillingConfigController`'s worked example claims,
// in its own comment, to "mirror functions/src/lib/pricing.ts exactly". For
// INCLUSIVE tax it did not.
//
//   server (pricing.ts, per rule, independently):
//       amountMinor = round(taxable - taxable / (1 + p/100))
//
//   console (before):
//       combined = Σ p_i
//       net      = round(sample * 100 / (100 + combined))
//       inclusive = sample - net
//
// Identical for ONE inclusive rule. Different for two — which is the ordinary
// Indian case, where GST is authored as CGST 9% + SGST 9% rather than as a
// single 18% line.
//
//   ₹1000, CGST 9% + SGST 9% inclusive
//     server:  round(100000 - 100000/1.09) x 2  = 8257 x 2 = 16514  (₹165.14)
//     console: 100000 - round(100000*100/118)   =            15254  (₹152.54)
//
// A ₹12.60 disagreement per ₹1000 between the number the founder approves and
// the tax line the buyer's receipt shows. It does not change what is CHARGED —
// inclusive tax is carved out, never added — but the console's entire stated
// design rule is "a founder must never have to imagine the outcome", and a
// preview that disagrees with the receipt is exactly that.
//
// The server is the authority; the preview mirrors it.

import 'package:alphaserena_admin_portel/controllers/billing_config_controller.dart';
import 'package:alphaserena_admin_portel/models/billing_config_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _OfflineBilling extends BillingConfigController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// `pricing.ts:priceQuote` — the deployed computation, transcribed.
int serverInclusiveMinor(int taxableMinor, List<TaxRule> taxes) {
  var total = 0;
  for (final t in taxes.where((t) => t.inclusive)) {
    final amount =
        (taxableMinor - taxableMinor / (1 + t.percent / 100)).round();
    if (amount <= 0) continue;
    total += amount;
  }
  return total;
}

void main() {
  test('two inclusive rules: the preview equals the server, minor for minor',
      () {
    final c = _OfflineBilling();
    c.enabled.value = true;
    c.samplePrice.value = 1000;
    c.taxes.assignAll(const [
      TaxRule(name: 'CGST', percent: 9, inclusive: true),
      TaxRule(name: 'SGST', percent: 9, inclusive: true),
    ]);

    expect(c.inclusiveTaxMinor, serverInclusiveMinor(100000, c.taxes));
  });

  test('CONTROL — one inclusive rule already agreed, and still does', () {
    // Proves the fix did not simply move the disagreement elsewhere.
    final c = _OfflineBilling();
    c.enabled.value = true;
    c.samplePrice.value = 1000;
    c.taxes.assignAll(const [
      TaxRule(name: 'GST', percent: 18, inclusive: true),
    ]);

    expect(c.inclusiveTaxMinor, serverInclusiveMinor(100000, c.taxes));
  });

  test('CONTROL — exclusive tax is unchanged and still matches the server', () {
    final c = _OfflineBilling();
    c.enabled.value = true;
    c.samplePrice.value = 1000;
    c.taxes.assignAll(const [
      TaxRule(name: 'GST', percent: 18),
    ]);

    // Server: round(taxable * p / 100) = 18000; and inclusive is zero.
    expect(c.exclusiveTaxMinor, 18000);
    expect(c.inclusiveTaxMinor, 0);
    expect(c.grandTotalMinor, 118000);
  });
}
