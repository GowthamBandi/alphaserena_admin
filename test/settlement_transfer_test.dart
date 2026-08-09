// SETTLEMENT V1 — Phase 4Q console tests.
//
// The console mirrors the backend's evidence gate for a fast refusal; the
// backend remains the authority. These tests pin the console's HALF of that
// contract: the draft gating, the file constraints, the model's parsing of the
// evidence the backend writes, and the dialog's product rules (the button
// attests a transfer, the private note says it is private, a concurrent
// completion reads as a conflict — never as a fake success).

import 'dart:typed_data';

import 'package:alphaserena_admin_portel/models/settlement_model.dart';
import 'package:alphaserena_admin_portel/widgets/settlement/transfer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SettlementModel _approved({int netMinor = 488200}) => SettlementModel(
      id: 'pay_T1',
      razorpayPaymentId: 'pay_T1',
      razorpayOrderId: 'order_T1',
      memberPaymentId: 'r1',
      adminId: 'org-a',
      orgName: 'Iron Temple',
      clientId: 'c1',
      memberAuthUid: 'm1',
      memberName: 'Asha',
      planId: 'p1',
      planName: 'Monthly',
      status: SettlementStatus.approved,
      paymentState: PaymentState.captured,
      currency: 'INR',
      grossMinor: 500000,
      gatewayFeeMinor: 10000,
      gatewayTaxMinor: 1800,
      platformFeeMinor: 0,
      platformFeeTaxMinor: 0,
      netMinor: netMinor,
      gatewayNetMinor: netMinor,
      feesFinalized: true,
      refundedGrossMinor: 0,
      recoveryMinor: 0,
      terms: SettlementTerms.fromMap(const {
        'platformFeeBps': 0,
        'platformFeeTaxBps': 1800,
        'gatewayFeeBearer': 'org',
        'holdHours': 24,
      }),
    );

void main() {
  // ── TransferDraft: the console-side gate, one refusal at a time ──────────

  TransferDraft draft({
    String utr = 'UTR123',
    DateTime? at,
    String method = 'bank_transfer',
    int? amount = 488200,
    bool uploaded = true,
    bool required = true,
    bool confirmed = true,
  }) =>
      TransferDraft(
        expectedNetMinor: 488200,
        utr: utr,
        transferredAt: at ?? DateTime.now(),
        method: method,
        enteredAmountMinor: amount,
        proofUploaded: uploaded,
        proofRequired: required,
        confirmed: confirmed,
      );

  test('a complete draft is submittable', () {
    expect(draft().submittable, isTrue);
  });

  test('every missing piece blocks, in operator order', () {
    expect(draft(utr: '').firstProblem, contains('UTR'));
    expect(
      TransferDraft(expectedNetMinor: 1, utr: 'x').firstProblem,
      contains('transfer date'),
    );
    expect(draft(method: 'cheque').firstProblem, contains('method'));
    expect(draft(amount: null).firstProblem, contains('amount'));
    expect(draft(uploaded: false).firstProblem, contains('proof'));
    expect(draft(confirmed: false).firstProblem, contains('Confirm'));
  });

  test('AMOUNT MISMATCH blocks — a stale screen must not submit', () {
    final d = draft(amount: 488100);
    expect(d.submittable, isFalse);
    expect(d.firstProblem, contains('exactly'));
  });

  test('a future transfer date blocks', () {
    final d = draft(at: DateTime.now().add(const Duration(days: 3)));
    expect(d.firstProblem, contains('future'));
  });

  test('the audited kill-switch: proof not required → submittable without one', () {
    expect(draft(uploaded: false, required: false).submittable, isTrue);
  });

  // ── proof file constraints (must match backend + storage rules) ──────────

  test('proof constraints mirror the backend exactly', () {
    expect(kProofContentTypes,
        containsAll(['application/pdf', 'image/jpeg', 'image/png']));
    expect(kMaxProofBytes, 10 * 1024 * 1024);
    expect(proofFileProblem(mime: 'application/pdf', sizeBytes: 100), isNull);
    expect(proofFileProblem(mime: 'text/html', sizeBytes: 100),
        contains('PDF, JPEG or PNG'));
    expect(proofFileProblem(mime: 'application/pdf', sizeBytes: 0),
        contains('empty'));
    expect(
        proofFileProblem(
            mime: 'image/png', sizeBytes: kMaxProofBytes + 1),
        contains('10 MB'));
  });

  // ── model parsing: the evidence the backend writes ────────────────────────

  test('SettlementModel parses transfer{} and proof{} as written by the backend', () {
    final m = SettlementModel.fromMap({
      'adminId': 'org-a',
      'status': 'settled',
      'netMinor': 488200,
      'grossMinor': 500000,
      'transfer': {
        'transferredAt': DateTime(2026, 8, 8).toIso8601String(),
        'method': 'bank_transfer',
        'utr': 'UTR999',
        'amountMinor': 488200,
        'notes': 'IMPS same day',
      },
      'proof': {
        'storagePath': 'settlement_proofs/pay_X/1_receipt.pdf',
        'fileName': '1_receipt.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 52341,
        'sha256': 'abc123',
        'uploadedBy': 'founder-1',
      },
    }, 'pay_X');

    expect(m.transfer, isNotNull);
    expect(m.transfer!.amountMinor, 488200);
    expect(m.transfer!.methodLabel, 'Bank transfer');
    expect(m.proof, isNotNull);
    expect(m.proof!.sizeLabel, '51 KB');
    expect(m.proof!.sha256, 'abc123');
  });

  test('an absent or empty proof map parses to null, never a phantom object', () {
    expect(SettlementModel.fromMap({'adminId': 'a'}, 'x').proof, isNull);
    expect(
      SettlementModel.fromMap({
        'adminId': 'a',
        'proof': {'storagePath': ''},
      }, 'x').proof,
      isNull,
    );
  });

  test('ChargedOrderAlert parses the reconcile sweep shape', () {
    final a = ChargedOrderAlert.fromMap({
      'kind': 'charged_not_activated',
      'orderId': 'order_9',
      'paymentId': 'pay_9',
      'type': 'membership',
      'amountPaise': 250000,
      'status': 'open',
    }, 'alert-1');
    expect(a.isOpen, isTrue);
    expect(a.amountPaise, 250000);
  });

  // ── the dialog's product rules ────────────────────────────────────────────

  Future<void> pump(
    WidgetTester tester, {
    SubmitTransfer? onSubmit,
    bool proofRequired = true,
  }) async {
    // A real desktop viewport: the dialog's footer must be tappable, and a
    // tap that silently misses an off-screen button turns an assertion into
    // a false pass/fail.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TransferDialog(
          settlement: _approved(),
          proofRequired: proofRequired,
          onUploadProof: ({
            required Uint8List bytes,
            required String fileName,
            required String contentType,
          }) async =>
              'settlement_proofs/pay_T1/1_$fileName',
          onSubmit: onSubmit ?? (_) async => (ok: true, message: 'ok'),
        ),
      ),
    ));
  }

  testWidgets('the button attests a TRANSFER of the exact amount — never "Mark Paid"',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('Confirm ₹4,882 transfer'), findsOneWidget);
    expect(find.textContaining('Mark Paid'), findsNothing);
  });

  testWidgets('submit is disabled until the draft is complete', (tester) async {
    await pump(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm ₹4,882 transfer'),
    );
    expect(button.onPressed, isNull, reason: 'no UTR, no proof, no attestation');
  });

  testWidgets('the private note says it is private', (tester) async {
    await pump(tester);
    expect(find.text('Private Super Admin note (optional)'), findsOneWidget);
    expect(
      find.textContaining('Never shown to the organization'),
      findsOneWidget,
    );
  });

  testWidgets(
      'an "already settled" refusal renders as a CONFLICT explanation, not a retryable error',
      (tester) async {
    // Drive the draft complete without touching Storage: proof not required.
    await pump(
      tester,
      proofRequired: false,
      onSubmit: (_) async => (
        ok: false,
        message: 'Settlement is already settled.',
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'From your banking app after the transfer'),
      'UTR777',
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, 'Confirm ₹4,882 transfer');
    await tester.ensureVisible(submit);
    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNotNull,
      reason: 'the draft is complete; the button must be live',
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('already completed by another administrator'),
      findsOneWidget,
    );
    // And the dialog did NOT pretend success (it is still on screen).
    expect(find.byType(TransferDialog), findsOneWidget);
    // The submit button is now locked — retrying a done settlement is not offered.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm ₹4,882 transfer'),
    );
    expect(button.onPressed, isNull);
  });
}
