// ============================================================================
// SETTLEMENT — one member payment the platform is holding on an organization's
// behalf, and the obligation to pass it on.
//
// THIS IS SYSTEM B ONLY. System A (an organization paying TrainersArena for its
// platform subscription) is our own revenue, lives in `admin_payments_history`,
// and never becomes a settlement. The two never meet in this file, in the
// backend, or in the ledger.
//
// ── EVERY AMOUNT HERE IS INTEGER PAISE ──────────────────────────────────────
// Named `*Minor`, parsed as `int`, never as `double`. The legacy
// `memberPayments.amount` field is a rupee double and is precisely the
// structure this system was built to stop depending on: `0.1 + 0.2 != 0.3` is
// not a curiosity in a payout ledger, it is a gym that is short a paise on
// every transaction forever. Conversion to rupees happens ONLY at the display
// edge (`formatMinor`) and never round-trips back into a stored value.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// The settlement lifecycle. Mirrors `SettlementStatus` in the backend's
/// `lib/settlement_core.ts` — the two MUST stay in sync, so this enum is
/// parsed defensively and an unknown value degrades to [unknown] rather than
/// throwing on a status the backend added and the console has not learned yet.
enum SettlementStatus {
  /// Captured; the hold clock is running toward auto-settlement.
  pending,

  /// System-flagged: something blocks release (no bank details, org blocked,
  /// fees unknown). The clock is STOPPED. A queue, not a punishment.
  underReview,

  /// Founder-held with a stated reason. Clock stopped.
  onHold,

  /// Cleared to pay; awaiting payout execution.
  approved,

  /// A payout is IN FLIGHT and its outcome is unknown. Nothing may act on a
  /// settlement in this state — see the backend state machine.
  settling,

  /// Money confirmed delivered, with a bank reference. Terminal.
  settled,

  /// A payout attempt failed. Retryable.
  failed,

  /// The payment was refunded before we paid out. Terminal.
  refunded,

  /// A dispute was lost before we paid out. Terminal.
  chargeback,

  /// Administratively voided. Terminal.
  cancelled,

  /// A status this console build does not recognise.
  unknown;

  static SettlementStatus parse(Object? raw) {
    switch ((raw ?? '').toString()) {
      case 'pending':
        return SettlementStatus.pending;
      case 'under_review':
        return SettlementStatus.underReview;
      case 'on_hold':
        return SettlementStatus.onHold;
      case 'approved':
        return SettlementStatus.approved;
      case 'settling':
        return SettlementStatus.settling;
      case 'settled':
        return SettlementStatus.settled;
      case 'failed':
        return SettlementStatus.failed;
      case 'refunded':
        return SettlementStatus.refunded;
      case 'chargeback':
        return SettlementStatus.chargeback;
      case 'cancelled':
        return SettlementStatus.cancelled;
      default:
        return SettlementStatus.unknown;
    }
  }

  /// The wire value, for querying and for calling the backend.
  String get wire => switch (this) {
        SettlementStatus.pending => 'pending',
        SettlementStatus.underReview => 'under_review',
        SettlementStatus.onHold => 'on_hold',
        SettlementStatus.approved => 'approved',
        SettlementStatus.settling => 'settling',
        SettlementStatus.settled => 'settled',
        SettlementStatus.failed => 'failed',
        SettlementStatus.refunded => 'refunded',
        SettlementStatus.chargeback => 'chargeback',
        SettlementStatus.cancelled => 'cancelled',
        SettlementStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        SettlementStatus.pending => 'Pending',
        SettlementStatus.underReview => 'Under review',
        SettlementStatus.onHold => 'On hold',
        SettlementStatus.approved => 'Approved',
        SettlementStatus.settling => 'Settling',
        SettlementStatus.settled => 'Settled',
        SettlementStatus.failed => 'Failed',
        SettlementStatus.refunded => 'Refunded',
        SettlementStatus.chargeback => 'Chargeback',
        SettlementStatus.cancelled => 'Cancelled',
        SettlementStatus.unknown => 'Unknown',
      };

  /// Whether the platform still HOLDS this money. The sum over these is the
  /// platform's float — the first number an accountant or an acquirer asks for.
  bool get isOutstanding => const {
        SettlementStatus.pending,
        SettlementStatus.underReview,
        SettlementStatus.onHold,
        SettlementStatus.approved,
        SettlementStatus.settling,
        SettlementStatus.failed,
      }.contains(this);

  bool get isTerminal => const {
        SettlementStatus.settled,
        SettlementStatus.refunded,
        SettlementStatus.chargeback,
        SettlementStatus.cancelled,
      }.contains(this);

  /// Needs a human now: either blocked, or a payout that failed.
  bool get needsAttention => const {
        SettlementStatus.underReview,
        SettlementStatus.failed,
      }.contains(this);
}

/// What happened to the member's money at the gateway — an axis INDEPENDENT of
/// whether we have settled it.
///
/// The two are separate because a payment can be disputed AFTER it has been
/// settled, at which point the settlement remains a true historical fact (we
/// did pay, and the gym's bank statement shows it) while the payment becomes a
/// loss recorded as a recovery.
enum PaymentState {
  captured,
  partiallyRefunded,
  refunded,
  disputed,
  chargebackLost,
  chargebackWon,
  unknown;

  static PaymentState parse(Object? raw) => switch ((raw ?? '').toString()) {
        'captured' => PaymentState.captured,
        'partially_refunded' => PaymentState.partiallyRefunded,
        'refunded' => PaymentState.refunded,
        'disputed' => PaymentState.disputed,
        'chargeback_lost' => PaymentState.chargebackLost,
        'chargeback_won' => PaymentState.chargebackWon,
        _ => PaymentState.unknown,
      };

  String get label => switch (this) {
        PaymentState.captured => 'Captured',
        PaymentState.partiallyRefunded => 'Partially refunded',
        PaymentState.refunded => 'Refunded',
        PaymentState.disputed => 'Disputed',
        PaymentState.chargebackLost => 'Chargeback lost',
        PaymentState.chargebackWon => 'Dispute won',
        PaymentState.unknown => 'Unknown',
      };

  /// True when the money is no longer (fully) ours to pass on.
  bool get isClean =>
      this == PaymentState.captured || this == PaymentState.chargebackWon;
}

/// The commercial terms that were in force for ONE settlement, captured as an
/// immutable snapshot at creation.
///
/// Denormalized onto the settlement rather than referenced, so raising the
/// platform fee tomorrow cannot silently restate what a gym was paid last
/// month. A financial record must reproduce the terms actually applied to it.
class SettlementTerms {
  /// Platform commission on gross, in BASIS POINTS. 250 = 2.5%. Integer, never
  /// a float percentage.
  final int platformFeeBps;
  final int platformFeeTaxBps;

  /// `org` (deducted from the gym) or `platform` (absorbed by TrainersArena).
  final String gatewayFeeBearer;

  /// Hours from capture until auto-settlement becomes eligible.
  final int holdHours;

  const SettlementTerms({
    this.platformFeeBps = 0,
    this.platformFeeTaxBps = 1800,
    this.gatewayFeeBearer = 'org',
    this.holdHours = 24,
  });

  factory SettlementTerms.fromMap(Object? raw) {
    final m = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    int i(String k, int fallback) =>
        m[k] is num ? (m[k] as num).toInt() : fallback;
    return SettlementTerms(
      platformFeeBps: i('platformFeeBps', 0),
      platformFeeTaxBps: i('platformFeeTaxBps', 1800),
      gatewayFeeBearer:
          (m['gatewayFeeBearer'] ?? 'org').toString() == 'platform'
              ? 'platform'
              : 'org',
      holdHours: i('holdHours', 24),
    );
  }

  bool get orgBearsGatewayFee => gatewayFeeBearer == 'org';

  /// "2.5%" — for display only.
  String get platformFeeLabel {
    if (platformFeeBps == 0) return '0% (pass-through)';
    final whole = platformFeeBps ~/ 100;
    final frac = platformFeeBps % 100;
    return frac == 0
        ? '$whole%'
        : '$whole.${frac.toString().padLeft(2, '0')}%';
  }
}

/// Where a payout is going, as stored on the settlement — ALWAYS MASKED.
///
/// The backend stores only the last four digits (`describeDestination`), which
/// is what makes it safe for the owning organization to read its own settlement
/// row and for the value to appear in an indefinitely-retained audit log.
class DestinationSummary {
  final String mode; // 'bank' | 'upi'
  final String label; // already masked: '••••••••9012'
  final String accountName;
  final String ifsc;
  final String bankName;

  const DestinationSummary({
    required this.mode,
    required this.label,
    this.accountName = '',
    this.ifsc = '',
    this.bankName = '',
  });

  static DestinationSummary? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final label = (m['label'] ?? '').toString();
    if (label.isEmpty) return null;
    return DestinationSummary(
      mode: (m['mode'] ?? 'bank').toString(),
      label: label,
      accountName: (m['accountName'] ?? '').toString(),
      ifsc: (m['ifsc'] ?? '').toString(),
      bankName: (m['bankName'] ?? '').toString(),
    );
  }

  bool get isUpi => mode == 'upi';
}

/// ── DEFENSIVE PARSING ───────────────────────────────────────────────────────
/// Matches the house style: a stored value may be a `Timestamp`, an ISO string,
/// or absent, and a model that throws on any of those turns a data anomaly into
/// a blank financial screen during an incident.

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Reads an integer paise value. A `double` that is not whole is REFUSED
/// (returns 0) rather than rounded: a fractional paise cannot exist, and
/// silently rounding one would hide the bug that produced it.
int _minor(Object? v) {
  if (v is int) return v;
  if (v is num) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt() : 0;
  }
  return 0;
}

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => (v ?? '').toString();

/// ============================================================================
/// THE SETTLEMENT
/// ============================================================================
class SettlementModel {
  final String id;

  // ── Identity ──────────────────────────────────────────────────────────────
  /// The Razorpay payment id. This IS the document id — the choice that makes
  /// creation idempotent across the three producers that race to record it.
  final String razorpayPaymentId;
  final String razorpayOrderId;

  /// The `memberPayments` receipt this settles. Kept so the legacy coach-app
  /// earnings screen can be reconciled against the settlement.
  final String memberPaymentId;

  // ── Parties ───────────────────────────────────────────────────────────────
  final String adminId;

  /// Display snapshot, taken at creation. If a gym renames itself, historical
  /// settlements keep the name in force at the time — which is what a financial
  /// record should do.
  final String orgName;
  final String clientId;
  final String memberAuthUid;
  final String memberName;
  final String planId;
  final String planName;

  // ── State ─────────────────────────────────────────────────────────────────
  final SettlementStatus status;
  final PaymentState paymentState;

  // ── Money (ALL INTEGER PAISE) ─────────────────────────────────────────────
  final String currency;
  final int grossMinor;
  final int gatewayFeeMinor;
  final int gatewayTaxMinor;
  final int platformFeeMinor;
  final int platformFeeTaxMinor;

  /// What the organization actually receives.
  final int netMinor;

  /// Cash the platform actually receives from the gateway.
  final int gatewayNetMinor;

  /// Whether Razorpay has reported its ACTUAL fee. Until this is true the net
  /// is provisional and the settlement is deliberately ineligible for release.
  final bool feesFinalized;

  final int refundedGrossMinor;

  /// What the organization owes back after a post-settlement reversal.
  final int recoveryMinor;

  final SettlementTerms terms;

  // ── Clock ─────────────────────────────────────────────────────────────────
  final DateTime? capturedAt;

  /// The precomputed auto-settlement deadline. STORED, not derived: a later
  /// change to the hold policy must not retroactively re-time an existing
  /// obligation.
  final DateTime? autoSettleAt;

  // ── Decisions ─────────────────────────────────────────────────────────────
  final String approvedBy;
  final DateTime? approvedAt;

  /// 'manual' (a founder clicked) or 'auto' (the 24-hour engine).
  final String approvalMode;
  final String holdReason;
  final String heldBy;
  final DateTime? heldAt;
  final String reviewReason;
  final String cancelReason;

  // ── Payout ────────────────────────────────────────────────────────────────
  final String payoutRail;
  final int payoutAttempt;

  /// The key sent to the rail. On a stuck payout this is what an operator uses
  /// to ask the rail what actually happened, instead of guessing and risking a
  /// double payment.
  final String payoutIdempotencyKey;
  final String railPayoutId;

  /// The bank reference. The number a gym owner quotes.
  final String utr;
  final DateTime? settledAt;
  final String settledBy;
  final DestinationSummary? destination;
  final String lastFailureReason;
  final String lastFailureMessage;

  /// 'permanent' | 'transient' | 'unknown' — drives whether retrying is futile.
  final String failureClass;

  final String createdFrom;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The manual transfer's evidence, present only once settled by hand.
  /// Written atomically with `status: settled` and frozen by terminality —
  /// there is no write path that can alter these afterwards.
  final SettlementTransfer? transfer;

  /// The verified proof document behind [transfer]. `sha256` was computed by
  /// the BACKEND from the actual bytes in Storage, so this metadata describes
  /// the object that exists, not the object the console claimed to upload.
  final SettlementProof? proof;

  const SettlementModel({
    required this.id,
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.memberPaymentId,
    required this.adminId,
    required this.orgName,
    required this.clientId,
    required this.memberAuthUid,
    required this.memberName,
    required this.planId,
    required this.planName,
    required this.status,
    required this.paymentState,
    required this.currency,
    required this.grossMinor,
    required this.gatewayFeeMinor,
    required this.gatewayTaxMinor,
    required this.platformFeeMinor,
    required this.platformFeeTaxMinor,
    required this.netMinor,
    required this.gatewayNetMinor,
    required this.feesFinalized,
    required this.refundedGrossMinor,
    required this.recoveryMinor,
    required this.terms,
    this.capturedAt,
    this.autoSettleAt,
    this.approvedBy = '',
    this.approvedAt,
    this.approvalMode = '',
    this.holdReason = '',
    this.heldBy = '',
    this.heldAt,
    this.reviewReason = '',
    this.cancelReason = '',
    this.payoutRail = 'manual',
    this.payoutAttempt = 0,
    this.payoutIdempotencyKey = '',
    this.railPayoutId = '',
    this.utr = '',
    this.settledAt,
    this.settledBy = '',
    this.destination,
    this.lastFailureReason = '',
    this.lastFailureMessage = '',
    this.failureClass = '',
    this.createdFrom = '',
    this.createdAt,
    this.updatedAt,
    this.transfer,
    this.proof,
  });

  factory SettlementModel.fromMap(Map<String, dynamic> m, String id) {
    return SettlementModel(
      id: id,
      razorpayPaymentId: _str(m['razorpayPaymentId']).isEmpty
          ? id
          : _str(m['razorpayPaymentId']),
      razorpayOrderId: _str(m['razorpayOrderId']),
      memberPaymentId: _str(m['memberPaymentId']),
      adminId: _str(m['adminId']),
      orgName: _str(m['orgName']),
      clientId: _str(m['clientId']),
      memberAuthUid: _str(m['memberAuthUid']),
      memberName: _str(m['memberName']),
      planId: _str(m['planId']),
      planName: _str(m['planName']).isEmpty
          ? 'Membership'
          : _str(m['planName']),
      status: SettlementStatus.parse(m['status']),
      paymentState: PaymentState.parse(m['paymentState']),
      currency: _str(m['currency']).isEmpty ? 'INR' : _str(m['currency']),
      grossMinor: _minor(m['grossMinor']),
      gatewayFeeMinor: _minor(m['gatewayFeeMinor']),
      gatewayTaxMinor: _minor(m['gatewayTaxMinor']),
      platformFeeMinor: _minor(m['platformFeeMinor']),
      platformFeeTaxMinor: _minor(m['platformFeeTaxMinor']),
      netMinor: _minor(m['netMinor']),
      gatewayNetMinor: _minor(m['gatewayNetMinor']),
      feesFinalized: m['feesFinalized'] == true,
      refundedGrossMinor: _minor(m['refundedGrossMinor']),
      recoveryMinor: _minor(m['recoveryMinor']),
      terms: SettlementTerms.fromMap(m['terms']),
      capturedAt: _date(m['capturedAt']),
      autoSettleAt: _date(m['autoSettleAt']),
      approvedBy: _str(m['approvedBy']),
      approvedAt: _date(m['approvedAt']),
      approvalMode: _str(m['approvalMode']),
      holdReason: _str(m['holdReason']),
      heldBy: _str(m['heldBy']),
      heldAt: _date(m['heldAt']),
      reviewReason: _str(m['reviewReason']),
      cancelReason: _str(m['cancelReason']),
      payoutRail: _str(m['payoutRail']).isEmpty
          ? 'manual'
          : _str(m['payoutRail']),
      payoutAttempt: _int(m['payoutAttempt']),
      payoutIdempotencyKey: _str(m['payoutIdempotencyKey']),
      railPayoutId: _str(m['railPayoutId']),
      utr: _str(m['utr']),
      settledAt: _date(m['settledAt']),
      settledBy: _str(m['settledBy']),
      destination: DestinationSummary.fromMap(m['destinationSummary']),
      lastFailureReason: _str(m['lastFailureReason']),
      lastFailureMessage: _str(m['lastFailureMessage']),
      failureClass: _str(m['failureClass']),
      createdFrom: _str(m['createdFrom']),
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
      transfer: SettlementTransfer.fromMap(m['transfer']),
      proof: SettlementProof.fromMap(m['proof']),
    );
  }

  // ── DERIVED ───────────────────────────────────────────────────────────────

  /// Total deducted from the member's payment before the gym is paid.
  int get totalDeductionsMinor => grossMinor - netMinor;

  /// Whether the money breakdown is arithmetically closed.
  ///
  /// Displayed rather than assumed: a settlement whose parts do not sum to its
  /// gross is a real anomaly, and the console showing it is how a human learns
  /// about it. The backend refuses to post such a settlement to the ledger, so
  /// a `false` here means something needs investigating, not ignoring.
  bool get breakdownCloses {
    final accounted = netMinor +
        platformFeeMinor +
        platformFeeTaxMinor +
        (terms.orgBearsGatewayFee ? gatewayFeeMinor + gatewayTaxMinor : 0);
    return accounted == grossMinor;
  }

  /// Time until auto-settlement, or `null` when there is no running clock
  /// (held, disputed, terminal — all of which zero the deadline).
  Duration? timeUntilAutoSettle() {
    final due = autoSettleAt;
    if (due == null || status != SettlementStatus.pending) return null;
    final remaining = due.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the clock has run out but the settlement is still pending — i.e.
  /// the sweep should have taken it. Persisting means something is blocking it.
  bool get isOverdue {
    final due = autoSettleAt;
    return status == SettlementStatus.pending &&
        due != null &&
        due.isBefore(DateTime.now());
  }

  /// Whether retrying this payout can plausibly succeed. A closed account fails
  /// identically every time; the console says "fix the bank details" instead of
  /// offering a button that will not work.
  bool get isRetryFutile => failureClass == 'permanent';

  /// Whether a founder action is even possible right now. `settling` is the
  /// deliberate exception: money is in flight and its location is unknown.
  bool get isActionable =>
      !status.isTerminal && status != SettlementStatus.settling;
}

/// ============================================================================
/// TIMELINE ENTRY — the settlement's own append-only history.
///
/// Deliberately separate from `audit_logs`, which is the platform-wide
/// privileged-action register. This is the SETTLEMENT'S story, and it includes
/// events that are not privileged actions at all: the clock elapsed, the
/// gateway reported a fee. Forcing those into `audit_logs` would either pollute
/// it or leave this history with holes.
/// ============================================================================
/// The manual transfer's recorded facts — what the founder actually did at the
/// bank, as accepted by the backend's evidence gate.
class SettlementTransfer {
  final DateTime? transferredAt;

  /// 'bank_transfer' | 'upi' | 'other' — the closed vocabulary the gate accepts.
  final String method;
  final String utr;

  /// INTEGER PAISE, verified equal to the settlement's net at settle time.
  final int amountMinor;

  /// ORG-VISIBLE remarks. Private founder notes never reach this document —
  /// they live in `audit_logs`, which organizations cannot read.
  final String notes;

  const SettlementTransfer({
    this.transferredAt,
    this.method = '',
    this.utr = '',
    this.amountMinor = 0,
    this.notes = '',
  });

  static SettlementTransfer? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    return SettlementTransfer(
      transferredAt: _date(m['transferredAt']),
      method: _str(m['method']),
      utr: _str(m['utr']),
      amountMinor: _minor(m['amountMinor']),
      notes: _str(m['notes']),
    );
  }

  String get methodLabel => switch (method) {
        'bank_transfer' => 'Bank transfer',
        'upi' => 'UPI',
        'other' => 'Other',
        _ => method.isEmpty ? '—' : method,
      };
}

/// The proof document's server-verified metadata.
class SettlementProof {
  final String storagePath;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// Computed by the backend from the bytes in Storage at settle time.
  final String sha256;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const SettlementProof({
    this.storagePath = '',
    this.fileName = '',
    this.contentType = '',
    this.sizeBytes = 0,
    this.sha256 = '',
    this.uploadedBy = '',
    this.uploadedAt,
  });

  static SettlementProof? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final p = SettlementProof(
      storagePath: _str(m['storagePath']),
      fileName: _str(m['fileName']),
      contentType: _str(m['contentType']),
      sizeBytes: _int(m['sizeBytes']),
      sha256: _str(m['sha256']),
      uploadedBy: _str(m['uploadedBy']),
      uploadedAt: _date(m['uploadedAt']),
    );
    return p.storagePath.isEmpty ? null : p;
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '—';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRANSFER DRAFT — the console-side mirror of the backend evidence gate
// ═════════════════════════════════════════════════════════════════════════════

/// Proof upload constraints. MUST match the backend
/// (`PROOF_CONTENT_TYPES` / `MAX_PROOF_BYTES` in settlement_core.ts) and the
/// Storage rule — the console validates for a fast, friendly refusal; the
/// backend and the rules are the authority.
const kProofContentTypes = ['application/pdf', 'image/jpeg', 'image/png'];
const kMaxProofBytes = 10 * 1024 * 1024;
const kTransferMethods = ['bank_transfer', 'upi', 'other'];

/// What the founder has filled into the transfer confirmation, validated as a
/// PURE function so the dialog's gating is unit-testable without widgets.
///
/// This mirrors — never replaces — `manualSettleBlockedBy` on the server. A
/// draft this validator passes can still be refused by the backend (a refund
/// may have landed since), and the dialog surfaces that refusal verbatim.
class TransferDraft {
  final int expectedNetMinor;
  final String utr;
  final DateTime? transferredAt;
  final String method;
  final int? enteredAmountMinor;
  final String proofStoragePath;
  final bool proofUploaded;
  final bool proofRequired;
  final bool confirmed;

  const TransferDraft({
    required this.expectedNetMinor,
    this.utr = '',
    this.transferredAt,
    this.method = '',
    this.enteredAmountMinor,
    this.proofStoragePath = '',
    this.proofUploaded = false,
    this.proofRequired = true,
    this.confirmed = false,
  });

  /// The first thing still missing, in the order an operator fixes them —
  /// or null when the draft is submittable.
  String? get firstProblem {
    if (utr.trim().isEmpty) return 'Enter the bank reference (UTR).';
    if (transferredAt == null) return 'Pick the transfer date.';
    if (transferredAt!.isAfter(DateTime.now().add(const Duration(hours: 26)))) {
      return 'The transfer date cannot be in the future.';
    }
    if (!kTransferMethods.contains(method)) return 'Choose the payment method.';
    if (enteredAmountMinor == null) return 'Enter the transferred amount.';
    if (enteredAmountMinor != expectedNetMinor) {
      return 'The amount must be exactly the settlement net '
          '(${formatMinor(expectedNetMinor)}). If the number looks wrong, '
          'close this dialog — the settlement may have changed.';
    }
    if (proofRequired && !proofUploaded) {
      return 'Upload the transfer proof document.';
    }
    if (!confirmed) return 'Confirm that the transfer was actually made.';
    return null;
  }

  bool get submittable => firstProblem == null;
}

/// Validates a picked file BEFORE any bytes leave the browser.
String? proofFileProblem({required String? mime, required int sizeBytes}) {
  if (mime == null || !kProofContentTypes.contains(mime)) {
    return 'The proof must be a PDF, JPEG or PNG.';
  }
  if (sizeBytes <= 0) return 'That file is empty.';
  if (sizeBytes > kMaxProofBytes) {
    return 'The proof must be 10 MB or smaller '
        '(this file is ${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB).';
  }
  return null;
}

// ═════════════════════════════════════════════════════════════════════════════
// EXCEPTION QUEUE — charged_not_activated alerts (NOT settlements)
// ═════════════════════════════════════════════════════════════════════════════

/// A payment that was captured but never activated: no receipt, no settlement,
/// a HUMAN decision required. Sourced from `paymentAlerts` (the reconciliation
/// sweep writes them); `pendingOrders` itself is server-only by rule.
class ChargedOrderAlert {
  final String id;
  final String orderId;
  final String paymentId;

  /// 'membership' | 'subscription' — only membership orders would ever settle.
  final String type;
  final String planId;
  final String adminUid;
  final String memberUid;
  final int amountPaise;
  final String status;
  final DateTime? orderCreatedAt;
  final DateTime? createdAt;

  const ChargedOrderAlert({
    required this.id,
    this.orderId = '',
    this.paymentId = '',
    this.type = '',
    this.planId = '',
    this.adminUid = '',
    this.memberUid = '',
    this.amountPaise = 0,
    this.status = '',
    this.orderCreatedAt,
    this.createdAt,
  });

  factory ChargedOrderAlert.fromMap(Map<String, dynamic> m, String id) {
    return ChargedOrderAlert(
      id: id,
      orderId: _str(m['orderId']),
      paymentId: _str(m['paymentId']),
      type: _str(m['type']),
      planId: _str(m['planId']),
      adminUid: _str(m['adminUid']),
      memberUid: _str(m['memberUid']),
      amountPaise: _minor(m['amountPaise']),
      status: _str(m['status']),
      orderCreatedAt: _date(m['orderCreatedAt']),
      createdAt: _date(m['createdAt']),
    );
  }

  bool get isOpen => status == 'open';
}

class SettlementTimelineEntry {
  final String id;
  final String event;

  /// 'founder' | 'system' | 'gateway' — the first question asked about any
  /// disputed payout is which of the three caused it.
  final String actor;
  final String actorUid;
  final String message;
  final SettlementStatus? fromStatus;
  final SettlementStatus? toStatus;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  const SettlementTimelineEntry({
    required this.id,
    required this.event,
    required this.actor,
    required this.actorUid,
    required this.message,
    this.fromStatus,
    this.toStatus,
    this.details = const {},
    this.createdAt,
  });

  factory SettlementTimelineEntry.fromMap(Map<String, dynamic> m, String id) {
    return SettlementTimelineEntry(
      id: id,
      event: _str(m['event']),
      actor: _str(m['actor']),
      actorUid: _str(m['actorUid']),
      message: _str(m['message']),
      fromStatus:
          m['fromStatus'] == null ? null : SettlementStatus.parse(m['fromStatus']),
      toStatus:
          m['toStatus'] == null ? null : SettlementStatus.parse(m['toStatus']),
      details: m['details'] is Map
          ? Map<String, dynamic>.from(m['details'] as Map)
          : const {},
      createdAt: _date(m['createdAt']),
    );
  }

  bool get isSystem => actor == 'system';
  bool get isGateway => actor == 'gateway';
}

/// ============================================================================
/// LEDGER ENTRY — one leg of a balanced double-entry transaction.
/// ============================================================================
class LedgerEntryModel {
  final String id;
  final String txnId;
  final int seq;
  final String event;
  final String account;

  /// 'asset' | 'liability' | 'income' | 'expense'.
  final String accountType;

  /// 'debit' | 'credit'.
  final String direction;
  final int amountMinor;

  /// Pre-signed for aggregation: summing this over an account gives its
  /// balance with no client-side knowledge of debit/credit conventions.
  final int signedMinor;
  final String memo;
  final String settlementId;
  final String adminId;
  final DateTime? createdAt;

  const LedgerEntryModel({
    required this.id,
    required this.txnId,
    required this.seq,
    required this.event,
    required this.account,
    required this.accountType,
    required this.direction,
    required this.amountMinor,
    required this.signedMinor,
    required this.memo,
    required this.settlementId,
    required this.adminId,
    this.createdAt,
  });

  factory LedgerEntryModel.fromMap(Map<String, dynamic> m, String id) {
    return LedgerEntryModel(
      id: id,
      txnId: _str(m['txnId']),
      seq: _int(m['seq']),
      event: _str(m['event']),
      account: _str(m['account']),
      accountType: _str(m['accountType']),
      direction: _str(m['direction']),
      amountMinor: _minor(m['amountMinor']),
      signedMinor: _minor(m['signedMinor']),
      memo: _str(m['memo']),
      settlementId: _str(m['settlementId']),
      adminId: _str(m['adminId']),
      createdAt: _date(m['createdAt']),
    );
  }

  bool get isDebit => direction == 'debit';

  /// `org_payable:uid` → `org_payable`. The tenant suffix is noise in a list.
  String get accountBase => account.split(':').first;
}

/// ============================================================================
/// WEBHOOK EVENT — what the gateway asserted, retained as evidence.
///
/// This is what a chargeback representment is argued from, and the only way to
/// answer "did Razorpay ever tell us about this refund".
/// ============================================================================
class WebhookEventModel {
  final String id;
  final String event;

  /// 'processed' | 'ignored' | 'retry' | 'failed' | 'processing'.
  final String status;
  final bool signatureVerified;
  final String result;
  final String error;
  final DateTime? receivedAt;
  final DateTime? processedAt;
  final Map<String, dynamic> payload;

  const WebhookEventModel({
    required this.id,
    required this.event,
    required this.status,
    required this.signatureVerified,
    required this.result,
    required this.error,
    this.receivedAt,
    this.processedAt,
    this.payload = const {},
  });

  factory WebhookEventModel.fromMap(Map<String, dynamic> m, String id) {
    return WebhookEventModel(
      id: id,
      event: _str(m['event']),
      status: _str(m['status']),
      signatureVerified: m['signatureVerified'] == true,
      result: _str(m['result']),
      error: _str(m['error']),
      receivedAt: _date(m['receivedAt']),
      processedAt: _date(m['processedAt']),
      payload: m['payload'] is Map
          ? Map<String, dynamic>.from(m['payload'] as Map)
          : const {},
    );
  }

  bool get isHealthy => status == 'processed' || status == 'ignored';
}

/// ============================================================================
/// MONEY FORMATTING — THE EDGE.
///
/// The single place paise become rupees. Never store the output, never parse it
/// back. Mirrors `formatMinor` in the backend's `lib/money.ts` so the two can
/// never disagree about what a stored amount means.
/// ============================================================================
String formatMinor(int amountMinor, {String currency = 'INR'}) {
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  final negative = amountMinor < 0;
  final abs = amountMinor.abs();
  final major = abs ~/ 100;
  final minor = abs % 100;

  // Indian grouping: the last three digits, then pairs (12,34,567).
  final s = major.toString();
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }

  // Paise are shown only when non-zero, so a whole-rupee payout reads "₹499"
  // while a fee-deducted one keeps its exact value.
  final body =
      minor == 0 ? grouped : '$grouped.${minor.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$symbol$body';
}

/// Compact form for KPI tiles, where a full number would overflow the card.
String formatMinorCompact(int amountMinor, {String currency = 'INR'}) {
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  final abs = amountMinor.abs();
  final rupees = abs / 100;
  final sign = amountMinor < 0 ? '-' : '';
  if (rupees >= 10000000) {
    return '$sign$symbol${(rupees / 10000000).toStringAsFixed(2)} Cr';
  }
  if (rupees >= 100000) {
    return '$sign$symbol${(rupees / 100000).toStringAsFixed(2)} L';
  }
  if (rupees >= 1000) {
    return '$sign$symbol${(rupees / 1000).toStringAsFixed(1)}K';
  }
  return formatMinor(amountMinor, currency: currency);
}
