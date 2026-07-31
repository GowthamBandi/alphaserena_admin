import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins the refund-facing receipt contract:
//   • razorpayPaymentId reads ONLY the literal `razorpayPaymentId` field —
//     the backend's historyDocMatches requires it, so falling back to
//     `paymentId` would offer refunds that always fail.
//   • isFullyRefunded needs a real positive payment AND nothing left.

void main() {
  test('razorpayPaymentId reads only the literal field — no paymentId or '
      'doc-id fallback', () {
    final withField = SubscriptionModel.fromMap('doc1', {
      'paymentId': 'legacy_id',
      'razorpayPaymentId': 'pay_abc123',
      'amount': 500,
    });
    expect(withField.razorpayPaymentId, 'pay_abc123');

    final withoutField = SubscriptionModel.fromMap('doc2', {
      'paymentId': 'pay_should_not_leak',
      'amount': 500,
    });
    expect(withoutField.razorpayPaymentId, isEmpty);
    // paymentId keeps its own tolerant behavior for display.
    expect(withoutField.paymentId, 'pay_should_not_leak');
  });

  test('isFullyRefunded is false for a zero-amount receipt', () {
    final zero = SubscriptionModel.fromMap('doc3', {
      'razorpayPaymentId': 'pay_x',
      'amount': 0,
    });
    expect(zero.amountPaid, 0);
    expect(zero.isFullyRefunded, isFalse);
  });

  test('isFullyRefunded is true when refunded >= paid, false when partial', () {
    final full = SubscriptionModel.fromMap('doc4', {
      'razorpayPaymentId': 'pay_x',
      'amount': 500,
      'refund': {'amount': 500},
    });
    expect(full.isFullyRefunded, isTrue);
    expect(full.netAmount, 0);

    final partial = SubscriptionModel.fromMap('doc5', {
      'razorpayPaymentId': 'pay_x',
      'amount': 500,
      'refund': {'amount': 200},
    });
    expect(partial.isFullyRefunded, isFalse);
    expect(partial.netAmount, 300);
  });
}
