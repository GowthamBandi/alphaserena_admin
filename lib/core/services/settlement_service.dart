// ============================================================================
// SETTLEMENT SERVICE — the ONE portal path for every settlement action.
//
// Every method here calls a super-admin Cloud Function. NOTHING in this file
// writes Firestore, and that is the whole point: the security rules deny client
// writes to `settlements`, `ledger_txns`, `ledger_entries` and `platform_config`
// outright — including from a super admin — so a compromised console session
// cannot approve a payout, edit a ledger entry, or change the platform's fee.
//
// The backend owns the entire lifecycle: it re-reads status inside a Firestore
// transaction, asserts the transition is legal, posts the balanced ledger entry
// atomically with the status change, writes the audit record BEFORE any
// irreversible gateway call, and enforces idempotency on a deterministic key.
// None of that can be replicated client-side, and attempting to would create a
// second, divergent copy of the guard that prevents a double payout.
//
// Reads are a different matter and go direct to Firestore (streams, in the
// controller): the rules permit a super admin to read, live updates are what a
// payout queue needs, and a read cannot move money.
// ============================================================================

import 'package:cloud_functions/cloud_functions.dart';

/// What a settlement callable returned. Deliberately thin — the console's
/// source of truth is the Firestore stream, which updates the moment the
/// backend commits. Anything richer here would be a second copy of state that
/// can disagree with the document.
class SettlementActionResult {
  final bool ok;
  final String settlementId;

  /// Which rail handled it: 'manual' | 'razorpayx'.
  final String rail;

  /// True when the rail is MANUAL and the money now awaits a human transfer.
  /// The settlement stays `approved` rather than advancing to `settling` —
  /// nothing is in flight, and the lifecycle must not claim otherwise.
  final bool awaitingManual;

  final String message;

  const SettlementActionResult({
    required this.ok,
    this.settlementId = '',
    this.rail = '',
    this.awaitingManual = false,
    this.message = '',
  });

  factory SettlementActionResult.fromData(Object? raw) {
    final d = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    return SettlementActionResult(
      ok: d['ok'] == true,
      settlementId: (d['settlementId'] ?? '').toString(),
      rail: (d['rail'] ?? '').toString(),
      awaitingManual: d['awaitingManual'] == true,
      message: (d['message'] ?? '').toString(),
    );
  }
}

/// The platform-wide float and throughput figures.
///
/// Computed SERVER-SIDE rather than by summing a paginated client query,
/// because "total outstanding" is the money the platform is holding on trust
/// and a number of that significance must not silently depend on how many rows
/// a stream happened to deliver. [outstandingTruncated] surfaces the cap rather
/// than quietly understating the liability.
class SettlementSummary {
  final int outstandingMinor;
  final int outstandingCount;
  final bool outstandingTruncated;
  final Map<String, ({int count, int netMinor})> byStatus;
  final int settledLast24hMinor;
  final int settledLast24hCount;
  final int autoSettledLast24h;

  const SettlementSummary({
    this.outstandingMinor = 0,
    this.outstandingCount = 0,
    this.outstandingTruncated = false,
    this.byStatus = const {},
    this.settledLast24hMinor = 0,
    this.settledLast24hCount = 0,
    this.autoSettledLast24h = 0,
  });

  factory SettlementSummary.fromData(Object? raw) {
    final d = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final by = <String, ({int count, int netMinor})>{};
    if (d['byStatus'] is Map) {
      for (final e in (d['byStatus'] as Map).entries) {
        final v = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : {};
        by[e.key.toString()] = (
          count: v['count'] is num ? (v['count'] as num).toInt() : 0,
          netMinor: v['netMinor'] is num ? (v['netMinor'] as num).toInt() : 0,
        );
      }
    }
    int i(String k) => d[k] is num ? (d[k] as num).toInt() : 0;
    return SettlementSummary(
      outstandingMinor: i('outstandingMinor'),
      outstandingCount: i('outstandingCount'),
      outstandingTruncated: d['outstandingTruncated'] == true,
      byStatus: by,
      settledLast24hMinor: i('settledLast24hMinor'),
      settledLast24hCount: i('settledLast24hCount'),
      autoSettledLast24h: i('autoSettledLast24h'),
    );
  }
}

/// The commercial terms in force platform-wide.
class SettlementConfig {
  final int platformFeeBps;
  final int platformFeeTaxBps;
  final String gatewayFeeBearer;
  final int holdHours;
  final bool autoSettleEnabled;
  final String payoutRail;

  const SettlementConfig({
    this.platformFeeBps = 0,
    this.platformFeeTaxBps = 1800,
    this.gatewayFeeBearer = 'org',
    this.holdHours = 24,
    this.autoSettleEnabled = true,
    this.payoutRail = 'manual',
  });

  factory SettlementConfig.fromData(Object? raw) {
    final d = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final t = d['terms'] is Map
        ? Map<String, dynamic>.from(d['terms'] as Map)
        : const {};
    int i(Map m, String k, int fallback) =>
        m[k] is num ? (m[k] as num).toInt() : fallback;
    return SettlementConfig(
      platformFeeBps: i(t, 'platformFeeBps', 0),
      platformFeeTaxBps: i(t, 'platformFeeTaxBps', 1800),
      gatewayFeeBearer: (t['gatewayFeeBearer'] ?? 'org').toString(),
      holdHours: i(t, 'holdHours', 24),
      autoSettleEnabled: d['autoSettleEnabled'] != false,
      payoutRail: (d['payoutRail'] ?? 'manual').toString(),
    );
  }
}

class SettlementService {
  SettlementService._();

  static FirebaseFunctions get _fn => FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final r = await _fn.httpsCallable(name).call(data);
    return r.data is Map
        ? Map<String, dynamic>.from(r.data as Map)
        : <String, dynamic>{};
  }

  /// Approves a settlement and hands it to the configured payout rail.
  ///
  /// On the MANUAL rail this does not move money: it clears the settlement and
  /// queues it for the founder's bank transfer, then [recordPayout] closes it
  /// with the UTR. The result's [SettlementActionResult.awaitingManual] tells
  /// the UI which of the two happened, so the console never claims a transfer
  /// occurred that nobody performed.
  ///
  /// Throws [FirebaseFunctionsException] when the backend refuses — the message
  /// is written for the founder ("A payout is in flight for this settlement")
  /// and should be surfaced verbatim rather than replaced with a generic error.
  static Future<SettlementActionResult> approve({
    required String settlementId,
    String? note,
  }) async {
    final d = await _call('approveSettlement', {
      'settlementId': settlementId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return SettlementActionResult.fromData(d);
  }

  /// Stops the clock. The reason is REQUIRED by the backend, and deliberately:
  /// a hold with no stated reason is indistinguishable from a mistake three
  /// weeks later, when the money is still sitting there and nobody remembers.
  static Future<void> hold({
    required String settlementId,
    required String reason,
  }) =>
      _call('holdSettlement', {
        'settlementId': settlementId,
        'reason': reason.trim(),
      });

  /// Returns a held or under-review settlement to the auto-settlement queue.
  ///
  /// THE CLOCK RESTARTS from now. Restoring the original deadline would
  /// auto-settle a six-day-held settlement on the very next sweep, silently
  /// discarding the review that was just performed.
  static Future<void> release({
    required String settlementId,
    String? note,
  }) =>
      _call('releaseSettlement', {
        'settlementId': settlementId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// Voids a settlement permanently.
  ///
  /// Does NOT reverse the float: the platform still holds the member's money,
  /// it has simply stopped intending to pass it on through this record.
  /// Discharging the liability requires an explicit [postAdjustment], by a
  /// human, with a memo — so a cancel can never quietly convert a customer's
  /// money into platform revenue.
  static Future<void> cancel({
    required String settlementId,
    required String reason,
  }) =>
      _call('cancelSettlement', {
        'settlementId': settlementId,
        'reason': reason.trim(),
      });

  /// Re-attempts a failed payout. The backend re-reads the org's bank details
  /// first, so a gym that corrected its IFSC is retried against the new one.
  static Future<SettlementActionResult> retry({
    required String settlementId,
  }) async {
    final d = await _call('retrySettlement', {'settlementId': settlementId});
    return SettlementActionResult.fromData(d);
  }

  /// Records the outcome of a payout.
  ///
  /// The UTR is REQUIRED on success, and this is not bureaucracy: it is the
  /// only externally verifiable evidence that the transfer happened. A
  /// settlement marked settled without one is indistinguishable from a
  /// mistaken click, and "we definitely paid you" does not survive a gym
  /// owner's bank statement.
  ///
  /// TWO CONFIRMATION CONTRACTS, chosen by the settlement's CURRENT status —
  /// the backend routes on a fresh read, so the console only supplies what
  /// each path needs:
  ///   • `settling` (automated rail reported back): UTR only.
  ///   • `approved` (V1 MANUAL transfer): full evidence — the transfer date,
  ///     method, the EXACT net amount as a cross-check, and the storage path
  ///     of the uploaded proof. The backend re-verifies every one of these
  ///     inside the settle transaction (`manualSettleBlockedBy`), re-reads the
  ///     proof OBJECT from Storage, computes its sha256 itself, and refuses an
  ///     amount that no longer matches — so nothing here is trusted, merely
  ///     transported.
  ///
  /// [internalNote] is the founder's PRIVATE remark: the backend writes it to
  /// `audit_logs` (super-admin-read) and NEVER to the settlement document or
  /// timeline, both of which the owning organization can read.
  static Future<void> recordPayout({
    required String settlementId,
    required bool settled,
    String? utr,
    String? failureReason,
    String? message,
    int? transferredAtMs,
    String? transferMethod,
    int? transferAmountMinor,
    String? proofStoragePath,
    String? transferNotes,
    String? internalNote,
  }) =>
      _call('recordPayoutResult', {
        'settlementId': settlementId,
        'settled': settled,
        if (utr != null && utr.trim().isNotEmpty) 'utr': utr.trim(),
        if (failureReason != null && failureReason.trim().isNotEmpty)
          'failureReason': failureReason.trim(),
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
        if (transferredAtMs != null) 'transferredAtMs': transferredAtMs,
        if (transferMethod != null && transferMethod.isNotEmpty)
          'transferMethod': transferMethod,
        if (transferAmountMinor != null)
          'transferAmountMinor': transferAmountMinor,
        if (proofStoragePath != null && proofStoragePath.isNotEmpty)
          'proofStoragePath': proofStoragePath,
        if (transferNotes != null && transferNotes.trim().isNotEmpty)
          'transferNotes': transferNotes.trim(),
        if (internalNote != null && internalNote.trim().isNotEmpty)
          'internalNote': internalNote.trim(),
      });

  /// Posts a balanced manual correction to the ledger.
  ///
  /// THE ONLY WAY to change a financial outcome after the fact — there is no
  /// edit path anywhere in this system. The backend supplies the contra leg and
  /// refuses anything that does not balance, so a one-sided entry cannot reach
  /// an append-only ledger.
  ///
  /// [amountMinor] is INTEGER PAISE and is validated strictly server-side: a
  /// fractional or string amount is rejected, never best-effort interpreted.
  static Future<String> postAdjustment({
    required String account,
    required String direction, // 'debit' | 'credit'
    required int amountMinor,
    required String memo,
    String? settlementId,
    String? adminId,
  }) async {
    final d = await _call('postSettlementAdjustment', {
      'account': account,
      'direction': direction,
      'amountMinor': amountMinor,
      'memo': memo.trim(),
      if (settlementId != null && settlementId.isNotEmpty)
        'settlementId': settlementId,
      if (adminId != null && adminId.isNotEmpty) 'adminId': adminId,
    });
    return (d['txnId'] ?? '').toString();
  }

  /// Updates the platform's settlement terms.
  ///
  /// Changes apply to FUTURE settlements only: existing ones carry their own
  /// immutable terms snapshot and their own precomputed deadline, so raising
  /// the fee cannot restate historical payouts and shortening the hold cannot
  /// dump an unreviewed queue into the payout rail.
  static Future<SettlementConfig> setConfig({
    int? platformFeeBps,
    int? platformFeeTaxBps,
    String? gatewayFeeBearer,
    int? holdHours,
    bool? autoSettleEnabled,
    String? payoutRail,
  }) async {
    final terms = <String, dynamic>{
      if (platformFeeBps != null) 'platformFeeBps': platformFeeBps,
      if (platformFeeTaxBps != null) 'platformFeeTaxBps': platformFeeTaxBps,
      if (gatewayFeeBearer != null) 'gatewayFeeBearer': gatewayFeeBearer,
      if (holdHours != null) 'holdHours': holdHours,
    };
    final d = await _call('setSettlementConfig', {
      if (terms.isNotEmpty) 'terms': terms,
      if (autoSettleEnabled != null) 'autoSettleEnabled': autoSettleEnabled,
      if (payoutRail != null) 'payoutRail': payoutRail,
    });
    return SettlementConfig.fromData(d['config']);
  }

  /// The dashboard's headline figures, computed server-side.
  static Future<SettlementSummary> summary() async {
    final d = await _call('getSettlementSummary', const {});
    return SettlementSummary.fromData(d);
  }

  /// Refunds a member's payment at the gateway.
  ///
  /// ── WHY THIS REUSES `refundPayment` RATHER THAN ADDING A SETTLEMENT-SPECIFIC
  /// REFUND ────────────────────────────────────────────────────────────────────
  /// `refundPayment` already owns everything dangerous about a refund: it
  /// validates the amount strictly (a negative would otherwise fall through to
  /// a FULL refund), claims a per-payment lock so a double-click cannot issue
  /// two partials, audits BEFORE the irreversible gateway call, and records a
  /// `paymentAlerts` row if post-gateway bookkeeping fails. Duplicating that
  /// for Tier-2 would be a second implementation of the most failure-prone code
  /// in the platform.
  ///
  /// `historyDocId` is deliberately NOT sent: that parameter stamps an
  /// `admin_payments_history` receipt, which is SYSTEM A (the organization's own
  /// subscription payment). A member payment has no such receipt, and passing
  /// one would stamp a refund onto an unrelated org's Tier-1 record.
  ///
  /// ── HOW THE SETTLEMENT LEARNS ABOUT IT ──────────────────────────────────────
  /// It does not learn from this call. Razorpay emits `refund.processed`, the
  /// webhook receives it, and `applyGatewayReversal` reverses the float (or
  /// books a recovery, if we already settled) atomically with the ledger. That
  /// indirection is the point: a refund issued from the Razorpay DASHBOARD
  /// instead of this button flows through exactly the same path, so the two
  /// can never diverge. The console therefore tells the operator the settlement
  /// will update shortly rather than optimistically rewriting it.
  static Future<({String refundId, double amountRupees, String status})>
      refundMemberPayment({
    required String razorpayPaymentId,
    int? amountRupees,
    String? reason,
  }) async {
    final d = await _call('refundPayment', {
      'paymentId': razorpayPaymentId,
      if (amountRupees != null && amountRupees > 0) 'amount': amountRupees,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return (
      refundId: (d['refundId'] ?? '').toString(),
      amountRupees: d['amount'] is num ? (d['amount'] as num).toDouble() : 0.0,
      status: (d['status'] ?? '').toString(),
    );
  }
}
