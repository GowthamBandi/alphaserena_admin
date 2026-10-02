import 'package:cloud_firestore/cloud_firestore.dart';

/// One refund on a receipt — an entry of the server-maintained `refunds`
/// ledger on `admin_payments_history/{H}` (CONTRACTS C1), keyed by the
/// gateway refund id. Written ONLY by the backend (`refundPayment` and the
/// Razorpay webhook through one shared helper); this console reads it.
class ReceiptRefund {
  final String id;

  /// Integer paise, from the gateway entity.
  final int amountMinor;

  /// `created` (pending at the gateway) | `processed` | `failed` | '' when
  /// the entry does not say.
  final String status;

  /// False once the gateway reported the refund FAILED — the money did not
  /// leave, so it no longer counts against the receipt.
  final bool counted;

  /// `console` (issued by `refundPayment`) | `gateway` (made in the Razorpay
  /// dashboard and recorded by the webhook) | ''.
  final String source;
  final String? requestedBy;
  final String? reason;
  final String? intentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? processedAt;
  final DateTime? failedAt;

  /// Synthesised from a receipt written before the ledger existed: only the
  /// running total (and the latest refund's id / reason / actor) was kept.
  final bool legacy;

  /// For a [legacy] entry: how many refunds the old running total covers
  /// (`refund.count`), when recorded.
  final int? legacyCount;

  const ReceiptRefund({
    required this.id,
    required this.amountMinor,
    this.status = '',
    this.counted = true,
    this.source = '',
    this.requestedBy,
    this.reason,
    this.intentId,
    this.createdAt,
    this.updatedAt,
    this.processedAt,
    this.failedAt,
    this.legacy = false,
    this.legacyCount,
  });

  double get amount => amountMinor / 100;

  /// When the refund was made — the moment it belongs to on a timeline.
  DateTime? get at => createdAt ?? processedAt ?? updatedAt ?? failedAt;

  bool get isFailed => status == 'failed';
  bool get isPending => status == 'created' || status == 'pending';
  bool get isProcessed => status == 'processed';
  bool get fromGateway => source == 'gateway';
  bool get fromConsole => source == 'console';
}

class SubscriptionModel {
  final String id;
  final String adminUid;
  final String adminDocId;

  final String planName;
  final int durationMonths;

  /// What was collected, in integer PAISE. Receipts carry rupees that may be
  /// fractional (a GST-inclusive ₹1,178.82, a manual ₹999.50); the old int
  /// `amountPaid` truncated them — the receipt, the refundable maximum and
  /// revenue all dropped the paise, and a string "999.50" read as ₹0.
  final int amountMinor;

  /// What was collected, in rupees, paise-exact.
  double get amountPaid => amountMinor / 100;
  final int originalAmount;

  final bool couponApplied;
  final String? couponCode;
  final int discountAmount;

  final String paymentId;

  /// The razorpay `pay_…` id exactly as stored on the history doc — the id
  /// the backend `refundPayment` callable requires. Unlike [paymentId] this
  /// NEVER falls back to the doc id: empty means the doc carries no gateway
  /// payment id and the payment cannot be refunded from the console.
  final String razorpayPaymentId;

  final String? orderId;
  final String? signature;

  final DateTime startAt;
  final DateTime expiryAt;
  final DateTime createdAt;

  /// False when the history doc carries NO usable date at all. [createdAt] is
  /// then a placeholder (parse time), never a fact: the revenue engine keeps
  /// such a payment in the all-time total but out of every period sum, and
  /// the console prints "date not recorded" instead of a time. Before this
  /// flag existed the placeholder was `DateTime.now()` at every snapshot, so
  /// an undated receipt re-dated itself to "just now" on each emission —
  /// permanently first in "Recent payments" and permanently "this month".
  final bool createdAtKnown;

  /// Whether the gateway confirmed the money was captured. Written by
  /// `verifyAndActivateSubscription` on every receipt since the capture gate
  /// shipped; docs from before it carry no field and are treated as verified
  /// (absence is age, not doubt). False marks an OPTIMISTIC activation — the
  /// one class of receipt that may describe money the platform does not hold.
  final bool captureVerified;

  /// Paise refunded against this receipt: the server's absolute aggregate
  /// `refund.amountMinor` when present, else the legacy rupee running total
  /// `refund.amount`, else the sum of the counted ledger entries. Counts
  /// refunds made from the console AND (once the webhook records them) in
  /// the Razorpay dashboard.
  final int refundMinor;

  /// Rupees refunded, paise-exact.
  double get refundAmount => refundMinor / 100;

  /// The per-refund ledger (C1), oldest first. A receipt written before the
  /// ledger existed but carrying a legacy `refund.amount` gets ONE
  /// synthesised entry marked [ReceiptRefund.legacy]. Empty when nothing was
  /// ever refunded.
  final List<ReceiptRefund> refunds;

  /// The payment reference a MANUAL receipt was recorded with (`reference`).
  /// The idempotency key the founder typed — printed on the receipt row and
  /// searchable on the Payments screen.
  final String? reference;

  /// `manual` for a receipt recorded by the team; absent on online receipts.
  final String? method;

  /// The raw `paymentId` FIELD, never the doc-id fallback [paymentId] uses.
  final String? rawPaymentId;

  /// COVERAGE EVIDENCE (CONTRACTS C4), stamped by the server on receipts
  /// written after the change: the date the term was ADDED TO
  /// (max(now, previous expiry)), the previous end date and plan, and whether
  /// the previous subscription was active. Legacy receipts carry none of it,
  /// and the console says so instead of inventing a span.
  final DateTime? coverageStart;
  final bool hasCoverageEvidence;
  final DateTime? previousExpiry;
  final String? previousPlanId;
  final String? previousPlanName;
  final bool? previousSubscriptionActive;

  /// FALSE when the receipt carries no readable start / expiry / term. The
  /// typed fields are then PLACEHOLDERS (today, today + 30 days, 1 month) —
  /// kept so old call sites compile — and must never be printed as facts.
  /// Before these flags a legacy receipt with no `expiry` was rendered as
  /// "Covers today → in 30 days", a term nobody sold.
  final bool startKnown;
  final bool expiryKnown;
  final bool termKnown;

  /// PRICING EVIDENCE stamped by the backend at grant / activation time:
  /// `plan_term` (list price applies; [listPrice] and the server-computed
  /// [pricingDiscount] / [overpayment] are set), `negotiated_term` (list
  /// basis recorded, no discount computed — the repository defines no
  /// proration), `unpriced` (plan carried no price), or null on a receipt
  /// written before the evidence existed.
  final String? pricingBasis;
  final double? listPrice;
  final int? listTermMonths;
  final double? pricingDiscount;
  final double? overpayment;
  final String? pricingCoupon;

  /// `pricing.term` — `monthly` | `yearly` | `custom` — the sold term the
  /// list price belongs to; null on receipts written before it existed.
  final String? pricingTerm;

  /// Whether the receipt can state the list price it was measured against.
  bool get hasPricingEvidence => pricingBasis != null;

  /// The discount the console may print: the server's evidence when present,
  /// else the legacy explicit field (older online receipts), else nothing.
  double get provenDiscount =>
      pricingDiscount ?? (discountAmount > 0 ? discountAmount.toDouble() : 0);

  /// Paise actually kept after refunds — revenue math sums THIS.
  int get netMinor =>
      (amountMinor - refundMinor) < 0 ? 0 : (amountMinor - refundMinor);

  /// Money actually kept after refunds, in rupees (paise-exact).
  double get netAmount => netMinor / 100;

  /// Nothing left to refund — the founder refund action hides itself here.
  /// Requires a real positive payment: a ₹0 receipt is "nothing paid", never
  /// "fully refunded".
  bool get isFullyRefunded => amountMinor > 0 && netMinor <= 0;

  /// An ONLINE receipt whose capture the gateway never confirmed. A manual
  /// receipt is stamped `captureVerified:false` by definition (no gateway was
  /// involved) and must never be flagged as "capture unverified".
  bool get captureUnverified =>
      razorpayPaymentId.isNotEmpty && !captureVerified;

  /// A receipt written by the RETIRED client-side checkout: a `pay_…`
  /// `paymentId` field but no `razorpayPaymentId` and no manual provenance.
  /// The money came through the gateway — it is not "collected outside the
  /// platform" — but the console holds no gateway id it can refund with.
  bool get isLegacyGatewayReceipt =>
      razorpayPaymentId.isEmpty &&
      method != 'manual' &&
      (reference ?? '').isEmpty &&
      (rawPaymentId ?? '').startsWith('pay_');

  // LIMITS
  final int maxAdmins;
  final int maxTrainers;
  final int maxClients;
  final int maxWorkoutPlans;
  final int maxWorkouts;
  final int maxDietPlans;

  SubscriptionModel({
    required this.id,
    required this.adminUid,
    required this.adminDocId,
    required this.planName,
    required this.durationMonths,
    required num amountPaid,
    required this.originalAmount,
    required this.couponApplied,
    this.couponCode,
    required this.discountAmount,
    required this.paymentId,
    this.razorpayPaymentId = '',
    this.orderId,
    this.signature,
    required this.startAt,
    required this.expiryAt,
    required this.createdAt,
    this.createdAtKnown = true,
    this.captureVerified = true,
    num refundAmount = 0,
    int? refundMinor,
    this.refunds = const [],
    this.reference,
    this.method,
    this.rawPaymentId,
    this.coverageStart,
    this.hasCoverageEvidence = false,
    this.previousExpiry,
    this.previousPlanId,
    this.previousPlanName,
    this.previousSubscriptionActive,
    this.pricingTerm,
    this.startKnown = true,
    this.expiryKnown = true,
    this.termKnown = true,
    this.pricingBasis,
    this.listPrice,
    this.listTermMonths,
    this.pricingDiscount,
    this.overpayment,
    this.pricingCoupon,

    // Limits
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxWorkouts,
    required this.maxDietPlans,
  }) : amountMinor = toMinor(amountPaid),
       refundMinor = refundMinor ?? toMinor(refundAmount);

  /// Rupees (possibly fractional) → integer paise. Non-finite → 0.
  static int toMinor(num rupees) {
    final d = rupees.toDouble();
    if (!d.isFinite) return 0;
    return (d * 100).round();
  }

  // Tolerant helpers — the real `admin_payments_history` doc (written by
  // trainersHQ verifyAndActivateSubscription) uses `amount`/`startedAt`/`expiry`
  // and a Firestore Timestamp `createdAt`. Earlier this model read
  // `amountPaid`/`startAt`/`expiryAt` and passed a Timestamp into
  // DateTime.tryParse(String) → revenue showed ₹0 and the stream threw. These
  // helpers read either shape and any date type.
  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  /// A money field in rupees → paise, reading numeric strings too.
  static int _minorFromRupees(dynamic v) => toMinor(_double(v));

  /// A field that is already integer paise.
  static int? _minorField(dynamic v) {
    if (v is int) return v;
    if (v is num && v.isFinite) return v.round();
    if (v is String) {
      final d = double.tryParse(v.trim());
      return (d != null && d.isFinite) ? d.round() : null;
    }
    return null;
  }

  static String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// The refund ledger (C1) — or ONE synthesised legacy entry when the
  /// receipt predates it but carries a refund total.
  static List<ReceiptRefund> _parseRefunds(dynamic rawLedger, dynamic rawAgg) {
    final out = <ReceiptRefund>[];
    if (rawLedger is Map) {
      rawLedger.forEach((k, v) {
        if (v is! Map) return;
        final minor =
            _minorField(v['amountMinor']) ?? _minorFromRupees(v['amount']);
        final status = (v['status'] ?? '').toString();
        out.add(
          ReceiptRefund(
            id: k.toString(),
            amountMinor: minor,
            status: status,
            counted: v['counted'] is bool
                ? v['counted'] as bool
                : status != 'failed',
            source: (v['source'] ?? '').toString(),
            requestedBy: _text(v['requestedBy']),
            reason: _text(v['reason']),
            intentId: _text(v['intentId']),
            createdAt: _date(v['createdAt']),
            updatedAt: _date(v['updatedAt']),
            processedAt: _date(v['processedAt']),
            failedAt: _date(v['failedAt']),
            legacy: v['legacy'] == true,
          ),
        );
      });
    }
    if (out.isEmpty && rawAgg is Map) {
      final minor =
          _minorField(rawAgg['amountMinor']) ??
          _minorFromRupees(rawAgg['amount']);
      if (minor > 0) {
        final count = rawAgg['count'];
        out.add(
          ReceiptRefund(
            id: _text(rawAgg['id']) ?? 'legacy',
            amountMinor: minor,
            status: (rawAgg['status'] ?? '').toString(),
            source: (rawAgg['lastSource'] ?? 'console').toString(),
            requestedBy: _text(rawAgg['refundedBy']),
            reason: _text(rawAgg['reason']),
            createdAt: _date(rawAgg['refundedAt']),
            legacy: true,
            legacyCount: count is num ? count.toInt() : null,
          ),
        );
      }
    }
    out.sort((a, b) {
      final x = a.at, y = b.at;
      if (x == null && y == null) return a.id.compareTo(b.id);
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return out;
  }

  factory SubscriptionModel.fromMap(String id, Map<String, dynamic> map) {
    final rawLimits = map['limits'];
    final Map limits = rawLimits is Map ? rawLimits : const {};
    final rawRefund = map['refund'];
    int lim(String flat, String nested) =>
        _int(map[flat] ?? limits[nested] ?? limits[flat]);

    final months = _int(map['durationMonths'] ?? map['months']);
    final createdAt = _date(
      map['createdAt'] ?? map['paidAt'] ?? map['timestamp'] ?? map['date'],
    );
    final startAt = _date(map['startedAt'] ?? map['startAt']);
    final expiryAt = _date(
      map['expiry'] ?? map['expiryAt'] ?? map['planExpiry'],
    );
    final rawPricing = map['pricing'];
    final Map pricing = rawPricing is Map ? rawPricing : const {};
    double? pnum(String k) {
      final v = pricing[k];
      return v is num ? v.toDouble() : null;
    }

    final basis = pricing['basis']?.toString();
    final refunds = _parseRefunds(map['refunds'], rawRefund);
    // The aggregate is the server's absolute figure; a missing aggregate
    // falls back to the ledger itself (counted entries only).
    final int refundMinor = rawRefund is Map
        ? (_minorField(rawRefund['amountMinor']) ??
              _minorFromRupees(rawRefund['amount']))
        : refunds
              .where((r) => r.counted)
              .fold<int>(0, (acc, r) => acc + r.amountMinor);
    final term = pricing['term']?.toString();
    final prevActive = map['previousSubscriptionActive'];

    return SubscriptionModel(
      id: id,
      adminUid: (map['adminUid'] ?? map['adminId'] ?? '').toString(),
      adminDocId: (map['adminDocId'] ?? map['adminId'] ?? map['adminUid'] ?? '')
          .toString(),
      planName: (map['planName'] ?? map['plan'] ?? map['title'] ?? '')
          .toString(),
      durationMonths: months > 0 ? months : 1,

      originalAmount: _int(map['originalAmount'] ?? map['amount']),
      // Rupees, paise-exact; numeric strings ("999.50") read as numbers.
      amountPaid: _double(
        map['amount'] ??
            map['amountPaid'] ??
            map['price'] ??
            map['paidAmount'] ??
            map['totalAmount'],
      ),
      discountAmount: _int(map['discountAmount'] ?? map['discount']),
      couponApplied:
          map['couponApplied'] == true ||
          (map['couponCode']?.toString().isNotEmpty ?? false),
      couponCode: map['couponCode']?.toString(),

      paymentId: (map['paymentId'] ?? map['razorpayPaymentId'] ?? id)
          .toString(),
      // NO fallback to paymentId: the backend's historyDocMatches requires the
      // literal `razorpayPaymentId` field on the doc — a fallback id would
      // offer a refund action that always fails server-side.
      razorpayPaymentId: (map['razorpayPaymentId'] ?? '').toString(),
      orderId: map['orderId']?.toString(),
      signature: map['signature']?.toString(),

      startAt: startAt ?? DateTime.now(),
      expiryAt: expiryAt ?? DateTime.now().add(const Duration(days: 30)),
      startKnown: startAt != null,
      expiryKnown: expiryAt != null,
      termKnown: months > 0,
      createdAt: createdAt ?? DateTime.now(),
      createdAtKnown: createdAt != null,
      captureVerified: map['captureVerified'] != false,
      refundMinor: refundMinor,
      refunds: refunds,
      reference: _text(map['reference']),
      method: _text(map['method']),
      rawPaymentId: _text(map['paymentId']),
      coverageStart: _date(map['coverageStart']),
      hasCoverageEvidence: map['coverageStart'] != null,
      previousExpiry: _date(map['previousExpiry']),
      previousPlanId: _text(map['previousPlanId']),
      previousPlanName: _text(map['previousPlanName']),
      previousSubscriptionActive: prevActive is bool ? prevActive : null,
      pricingTerm: (term == null || term.isEmpty) ? null : term,
      pricingBasis: (basis == null || basis.isEmpty) ? null : basis,
      listPrice: pnum('listPrice'),
      listTermMonths: pricing['listTermMonths'] is num
          ? (pricing['listTermMonths'] as num).toInt()
          : null,
      pricingDiscount: pnum('discount'),
      overpayment: pnum('overpayment'),
      pricingCoupon: pricing['coupon']?.toString(),

      maxAdmins: lim('maxAdmins', 'admins'),
      maxTrainers: lim('maxTrainers', 'trainers'),
      maxClients: lim('maxClients', 'clients'),
      maxWorkoutPlans: lim('maxWorkoutPlans', 'workoutPlans'),
      maxWorkouts: lim('maxWorkouts', 'workouts'),
      maxDietPlans: lim('maxDietPlans', 'dietPlans'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "adminUid": adminUid,
      "adminDocId": adminDocId,
      "planName": planName,
      "durationMonths": durationMonths,

      "originalAmount": originalAmount,
      "amountPaid": amountPaid,
      "discountAmount": discountAmount,
      "couponApplied": couponApplied,
      "couponCode": couponCode,

      "paymentId": paymentId,
      "orderId": orderId,
      "signature": signature,

      "startAt": startAt.toIso8601String(),
      "expiryAt": expiryAt.toIso8601String(),
      "createdAt": createdAt.toIso8601String(),

      // LIMITS
      "maxAdmins": maxAdmins,
      "maxTrainers": maxTrainers,
      "maxClients": maxClients,
      "maxWorkoutPlans": maxWorkoutPlans,
      "maxWorkouts": maxWorkouts,
      "maxDietPlans": maxDietPlans,
    };
  }
}
