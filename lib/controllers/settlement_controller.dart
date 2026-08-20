// ============================================================================
// SETTLEMENT CONTROLLER — the founder's live view of money the platform is
// holding on organizations' behalf.
//
// READS stream from Firestore (the rules grant a super admin read, and a payout
// queue is worthless if it is not live). WRITES all go through
// [SettlementService] → a super-admin Cloud Function, because the rules deny
// client writes to `settlements` outright and the lifecycle guard that prevents
// a double payout only exists inside the backend's transaction.
// ============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/services/settlement_service.dart';
import '../core/utils/console_errors.dart';
import '../models/settlement_model.dart';

/// The console's shared failure classifier, bound to this feature.
///
/// Naming the subject and the exact deploy command is the difference between
/// "something went wrong" and "the `settlements` rules are not deployed" — and
/// on a money screen the second is the only acceptable answer. The deploy
/// remedy is scoped deliberately: a blanket `--only functions` would ship every
/// unrelated change sitting in the backend working tree to a project serving
/// live organizations.
ConsoleError _settlementError(Object e, {String? operation}) =>
    describeConsoleError(
      e,
      operation: operation,
      subject: 'the Settlement workspace',
      deployRemedy: 'firebase deploy --only '
          'firestore:rules,firestore:indexes,'
          'functions:approveSettlement,functions:holdSettlement,'
          'functions:releaseSettlement,functions:cancelSettlement,'
          'functions:retrySettlement,functions:recordPayoutResult,'
          'functions:postSettlementAdjustment,functions:setSettlementConfig,'
          'functions:getSettlementSummary,functions:razorpayWebhook,'
          'functions:autoSettlementEngine',
      logTarget: 'settlements',
    );

/// The workspace's top-level views. Each is a saved query over one collection,
/// not a separate screen — the founder's job is triage, and switching context
/// should cost one tap.
enum SettlementView {
  /// Everything the platform still owes. The default, because it is the queue.
  outstanding,

  /// Clock elapsed but not released — the ones a human must unblock.
  needsAttention,

  /// Cleared and awaiting the founder's bank transfer (manual rail).
  readyToPay,

  settled,
  refundsAndDisputes,

  /// Captured payments with NO settlement: the human exception queue. These
  /// are `paymentAlerts` rows, not settlements — rendered as a distinct card
  /// shape so the two can never be confused.
  exceptions,
  all;

  String get label => switch (this) {
        SettlementView.outstanding => 'Outstanding',
        SettlementView.needsAttention => 'Needs attention',
        SettlementView.readyToPay => 'Ready to pay',
        SettlementView.settled => 'Settled',
        SettlementView.refundsAndDisputes => 'Refunds & disputes',
        SettlementView.exceptions => 'Exceptions',
        SettlementView.all => 'All',
      };
}

class SettlementController extends GetxController {
  // Resolved LAZILY so the screen can be constructed in a widget test without
  // an initialized Firebase app. Matches the controllers that already do this.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── STREAMS ───────────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _settlementsSub;

  /// The OPEN settlement's own document.
  ///
  /// Separate from the list stream on purpose. `syncSelected()` refreshes the
  /// detail pane from `settlements`, which holds only the rows matching the
  /// CURRENT VIEW — so the moment an action moves a row out of that view (hold
  /// a settlement while "Ready to pay" is selected and it is no longer
  /// approved) the lookup returns null and the pane keeps its pre-action
  /// snapshot: stale status, stale badge, and an action bar offering
  /// "Transfer to organization" for a settlement that is on hold. The backend
  /// refused such a transfer, so no money could move — but showing an operator
  /// a false state on a money surface is its own defect.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _selectedSub;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _timelineSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ledgerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _webhookSub;

  // ── STATE ─────────────────────────────────────────────────────────────────
  final RxList<SettlementModel> settlements = <SettlementModel>[].obs;
  final RxBool loading = true.obs;

  /// Set when the stream itself failed. Rendered as a classified error state —
  /// a permanently spinning loader after a rules change is the failure mode
  /// this console has already had to fix once, and on a money screen an
  /// operator must be able to tell an undeployed rule from a missing index
  /// from a genuine outage.
  final Rxn<ConsoleError> error = Rxn<ConsoleError>();

  final Rx<SettlementView> view = SettlementView.outstanding.obs;
  final RxString search = ''.obs;
  final RxString orgFilter = ''.obs;

  /// Server-computed platform float. Deliberately not derived from
  /// [settlements], which is paginated — see [SettlementSummary].
  final Rxn<SettlementSummary> summary = Rxn<SettlementSummary>();
  final RxBool summaryLoading = false.obs;

  // ── DETAIL ────────────────────────────────────────────────────────────────
  final Rxn<SettlementModel> selected = Rxn<SettlementModel>();
  final RxList<SettlementTimelineEntry> timeline =
      <SettlementTimelineEntry>[].obs;
  final RxList<LedgerEntryModel> ledger = <LedgerEntryModel>[].obs;
  final RxList<WebhookEventModel> webhookEvents = <WebhookEventModel>[].obs;
  final RxBool detailLoading = false.obs;

  /// True while a money action is in flight. Every action button reads this —
  /// a double-click on Approve must not reach the backend twice, even though
  /// the backend would reject the second call anyway. Defence in depth on the
  /// one path that moves money.
  final RxBool acting = false.obs;

  /// How many rows the queue holds. Bounded because a settlement list is read,
  /// not scrolled forever, and an unbounded stream on a money collection is a
  /// bill as well as a memory problem.
  static const int _pageLimit = 300;

  // ── EXCEPTION QUEUE (charged_not_activated) ───────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSub;
  final RxList<ChargedOrderAlert> exceptions = <ChargedOrderAlert>[].obs;
  final RxBool exceptionsLoading = true.obs;

  /// Set when the `paymentAlerts` stream itself failed.
  ///
  /// 🔴 Without this the view rendered "No exceptions" — the reassuring copy
  /// for a healthy platform — for a read that never happened. On the queue of
  /// members who were CHARGED and never activated, an unread queue and an
  /// empty one are not the same fact. Same shape as [error], which the
  /// settlements queue beside it has always carried.
  final Rxn<ConsoleError> exceptionsError = Rxn<ConsoleError>();

  /// Set when the per-payment webhook-evidence stream failed.
  ///
  /// 🔴 Its `onError` only wrote a `debugPrint`, so an unread stream and a
  /// payment with no webhook evidence were the same empty list — and the panel
  /// renders a SPECIFIC DIAGNOSIS for that empty case: "the Razorpay webhook
  /// may not be registered". A Firestore read failure therefore sent the
  /// operator to investigate the gateway's webhook configuration. An empty
  /// state that merely says nothing is a lie of omission; one that names a
  /// probable cause it did not observe sends someone down the wrong road.
  final RxBool webhookError = false.obs;

  /// The webhook stream's FAILURE branch. Named so a test drives the real
  /// handler rather than a re-description of it.
  @visibleForTesting
  void onWebhookStreamError(Object e) {
    webhookError.value = true;
    debugPrint('webhook stream error: $e');
  }

  // ── PROOF UPLOAD ──────────────────────────────────────────────────────────
  /// -1 = idle; 0..1 = uploading. One task at a time — a transfer confirmation
  /// carries exactly one proof.
  final RxDouble uploadProgress = (-1.0).obs;
  UploadTask? _uploadTask;

  @override
  void onInit() {
    super.onInit();
    _bindSettlements();
    _bindExceptions();
    refreshSummary();
  }

  @override
  void onClose() {
    _settlementsSub?.cancel();
    _selectedSub?.cancel();
    _timelineSub?.cancel();
    _ledgerSub?.cancel();
    _webhookSub?.cancel();
    _alertsSub?.cancel();
    _uploadTask?.cancel();
    super.onClose();
  }

  void retryExceptions() => _bindExceptions();

  void _bindExceptions() {
    exceptionsLoading.value = true;
    exceptionsError.value = null;
    // Equality-only query — no composite index needed on `paymentAlerts`.
    // Status + ordering are handled client-side over a bounded window.
    _alertsSub = _db
        .collection('paymentAlerts')
        .where('kind', isEqualTo: 'charged_not_activated')
        .limit(100)
        .snapshots()
        .listen(
          (snap) {
            final rows = snap.docs
                .map((d) => ChargedOrderAlert.fromMap(d.data(), d.id))
                .where((a) => a.isOpen)
                .toList()
              ..sort((a, b) {
                final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                return bt.compareTo(at);
              });
            exceptions.value = rows;
            exceptionsError.value = null;
            exceptionsLoading.value = false;
          },
          onError: (Object e) {
            exceptionsLoading.value = false;
            exceptionsError.value =
                _settlementError(e, operation: 'the exception queue');
            debugPrint('paymentAlerts stream error: $e');
          },
        );
  }

  // ── QUERY ─────────────────────────────────────────────────────────────────

  /// Builds the Firestore query for the active view.
  ///
  /// Server-side filtering is used wherever an index makes it possible, and the
  /// remaining predicates run client-side over the already-streamed page. The
  /// split is deliberate: `needsAttention` depends on comparing a stored
  /// deadline to *now*, which no Firestore index can express as a live query,
  /// so it filters in memory over a small, already-filtered set.
  Query<Map<String, dynamic>> _query() {
    final base = _db.collection('settlements');
    switch (view.value) {
      case SettlementView.settled:
        return base
            .where('status', isEqualTo: 'settled')
            .orderBy('settledAt', descending: true)
            .limit(_pageLimit);
      case SettlementView.readyToPay:
        return base
            .where('status', isEqualTo: 'approved')
            .orderBy('createdAt', descending: true)
            .limit(_pageLimit);
      case SettlementView.needsAttention:
        return base
            .where('status', whereIn: const ['under_review', 'failed'])
            .orderBy('createdAt', descending: true)
            .limit(_pageLimit);
      case SettlementView.refundsAndDisputes:
        return base
            .where('paymentState', whereIn: const [
              'refunded',
              'partially_refunded',
              'disputed',
              'chargeback_lost',
            ])
            .orderBy('createdAt', descending: true)
            .limit(_pageLimit);
      case SettlementView.outstanding:
        return base
            .where('status', whereIn: const [
              'pending',
              'under_review',
              'on_hold',
              'approved',
              'settling',
              'failed',
            ])
            .orderBy('createdAt', descending: true)
            .limit(_pageLimit);
      case SettlementView.exceptions:
      case SettlementView.all:
        return base.orderBy('createdAt', descending: true).limit(_pageLimit);
    }
  }

  void _bindSettlements() {
    // The exceptions view is a different collection entirely (`paymentAlerts`,
    // bound once in onInit); re-querying settlements for it would stream 300
    // money documents nobody is looking at.
    if (view.value == SettlementView.exceptions) {
      loading.value = false;
      error.value = null;
      return;
    }
    _settlementsSub?.cancel();
    loading.value = true;
    error.value = null;

    _settlementsSub = _query().snapshots().listen(
      (snap) {
        settlements.value = snap.docs
            .map((d) => SettlementModel.fromMap(d.data(), d.id))
            .toList();
        loading.value = false;
        error.value = null;
      },
      onError: (Object e) {
        // Classified rather than stringified: the overwhelmingly likely causes
        // on a fresh deploy are an undeployed `settlements` rules block or a
        // missing composite index, and those need different actions. An
        // operator staring at a spinner would learn neither.
        loading.value = false;
        error.value = _settlementError(e, operation: 'the settlements queue');
        debugPrint('SettlementController stream error: $e');
      },
    );
  }

  void setView(SettlementView v) {
    if (view.value == v) return;
    view.value = v;
    _bindSettlements();
  }

  void retryLoad() => _bindSettlements();

  // ── CLIENT-SIDE FILTERING ─────────────────────────────────────────────────

  /// The rows actually rendered: the streamed page narrowed by the search box,
  /// the organization filter, and (for `needsAttention`) the overdue predicate
  /// that no index can express.
  List<SettlementModel> get visible {
    final q = search.value.trim().toLowerCase();
    final org = orgFilter.value;

    return settlements.where((s) {
      if (org.isNotEmpty && s.adminId != org) return false;

      if (view.value == SettlementView.needsAttention) {
        // A settlement still waiting for its clock is HEALTHY and must not
        // clutter the queue a human is meant to work through.
        final blocked = s.status.needsAttention;
        if (!blocked && !s.isOverdue) return false;
      }

      if (q.isEmpty) return true;
      return s.orgName.toLowerCase().contains(q) ||
          s.memberName.toLowerCase().contains(q) ||
          s.planName.toLowerCase().contains(q) ||
          s.razorpayPaymentId.toLowerCase().contains(q) ||
          s.razorpayOrderId.toLowerCase().contains(q) ||
          s.utr.toLowerCase().contains(q) ||
          s.adminId.toLowerCase().contains(q) ||
          s.clientId.toLowerCase().contains(q);
    }).toList();
  }

  /// Organizations present in the current page, for the filter dropdown.
  List<({String id, String name})> get organizations {
    final seen = <String, String>{};
    for (final s in settlements) {
      if (s.adminId.isEmpty) continue;
      seen.putIfAbsent(s.adminId, () => s.orgName.isEmpty ? s.adminId : s.orgName);
    }
    final list = seen.entries.map((e) => (id: e.key, name: e.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ── PAGE-LEVEL AGGREGATES ─────────────────────────────────────────────────
  //
  // These describe THE VISIBLE PAGE, not the platform. The platform-wide float
  // comes from [summary] (server-computed). Keeping the two visually distinct
  // matters: a founder must never read a page total as the total liability.

  int get visibleNetMinor =>
      visible.fold(0, (t, s) => t + (s.status.isOutstanding ? s.netMinor : 0));

  int get visibleGrossMinor => visible.fold(0, (t, s) => t + s.grossMinor);

  int countWhere(bool Function(SettlementModel) test) =>
      settlements.where(test).length;

  // ── PLATFORM-WIDE COUNTERS ────────────────────────────────────────────────
  //
  // These describe THE PLATFORM, never the visible page, and the distinction
  // is a safety property rather than a nicety. They were previously derived
  // from `settlements` — the streamed page — so switching to "Ready to pay"
  // made the strip announce "Needs attention 0 · Nothing blocked" while three
  // settlements were in fact blocked. A filtered view silently rewrote a
  // platform health indicator into a lie an operator would act on.

  /// Blocked or failed payouts across the whole platform, from the server's
  /// own status census rather than from whatever the current view streamed.
  /// `null` when the census could not be read.
  ///
  /// 🔴 This used to fall back to `countWhere((x) => x.status.needsAttention)`
  /// over the STREAMED PAGE — the very derivation the comment above records as
  /// a shipped defect. Moving the counter server-side fixed the filtered-view
  /// case and left the discredited math as the null branch, so one failed
  /// `getSettlementSummary` brought the lie back for the whole session
  /// (`refreshSummary` runs once at boot; changing view does not re-fetch).
  /// On "Ready to pay" the fallback is structurally 0 — that view streams
  /// `status == 'approved'`, disjoint from {under_review, failed}.
  ///
  /// There is no safe local answer to "is anything blocked across the
  /// platform", so the honest return is "I do not know", which the strip
  /// renders as '—' exactly as the two tiles beside it already do.
  int? get needsAttentionCount {
    final by = summary.value?.byStatus;
    if (by == null) return null;
    return (by['under_review']?.count ?? 0) + (by['failed']?.count ?? 0);
  }

  /// Pending settlements whose hold window has elapsed, counted server-side.
  ///
  /// A count() aggregation rather than a document read: the answer is one
  /// number, and the composite index (`status`, `autoSettleAtMs`) that the
  /// auto-settlement sweep already relies on serves it exactly.
  final RxInt overdueTotal = 0.obs;

  /// Whether [overdueTotal] reflects a count that actually ran. Its aggregate
  /// failure is swallowed below, and an `RxInt` that stays at its initial 0
  /// is indistinguishable from a genuine "nothing is overdue".
  final RxBool overdueAvailable = false.obs;

  /// Page-scoped overdue, used only to decorate rows.
  int get overdueOnPage => settlements.where((s) => s.isOverdue).length;

  Future<void> refreshSummary() async {
    summaryLoading.value = true;
    try {
      summary.value = await SettlementService.summary();
    } catch (e) {
      debugPrint('getSettlementSummary failed: $e');
      // Deliberately NOT surfaced as a blocking error: the summary is a
      // headline, and losing it must not hide the queue underneath it.
    }
    try {
      final agg = await _db
          .collection('settlements')
          .where('status', isEqualTo: 'pending')
          .where('autoSettleAtMs', isLessThanOrEqualTo: DateTime.now()
              .millisecondsSinceEpoch)
          .count()
          .get();
      overdueTotal.value = agg.count ?? 0;
      overdueAvailable.value = true;
    } catch (e) {
      overdueAvailable.value = false;
      debugPrint('overdue count failed: $e');
    }
    summaryLoading.value = false;
  }

  // ── DETAIL ────────────────────────────────────────────────────────────────

  void openSettlement(SettlementModel s) {
    selected.value = s;
    _bindDetail(s);
  }

  void closeSettlement() {
    selected.value = null;
    _selectedSub?.cancel();
    _timelineSub?.cancel();
    _ledgerSub?.cancel();
    _webhookSub?.cancel();
    webhookError.value = false;
    timeline.clear();
    ledger.clear();
    webhookEvents.clear();
  }

  void _bindDetail(SettlementModel s) {
    detailLoading.value = true;
    // The settlement's OWN document — the authority on its status, and the
    // only source that stays correct when the row leaves the current view.
    _selectedSub?.cancel();
    _selectedSub = _db
        .collection('settlements')
        .doc(s.id)
        .snapshots()
        .listen(
      (doc) {
        final data = doc.data();
        if (!doc.exists || data == null) return;
        // Guard against a late frame from a previously-open settlement
        // overwriting the one the operator is looking at now.
        if (selected.value?.id != doc.id) return;
        selected.value = SettlementModel.fromMap(data, doc.id);
      },
      onError: (Object e) => debugPrint('settlement detail stream failed: $e'),
    );
    _timelineSub?.cancel();
    _ledgerSub?.cancel();
    _webhookSub?.cancel();
    timeline.clear();
    ledger.clear();
    webhookEvents.clear();

    _timelineSub = _db
        .collection('settlements')
        .doc(s.id)
        .collection('timeline')
        .orderBy('createdAt', descending: false)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            timeline.value = snap.docs
                .map((d) => SettlementTimelineEntry.fromMap(d.data(), d.id))
                .toList();
            detailLoading.value = false;
          },
          onError: (Object e) {
            detailLoading.value = false;
            debugPrint('timeline stream error: $e');
          },
        );

    // The ledger legs behind this settlement — ordered by transaction then leg,
    // so a capture reads as a coherent balanced block rather than interleaved.
    _ledgerSub = _db
        .collection('ledger_entries')
        .where('settlementId', isEqualTo: s.id)
        .limit(100)
        .snapshots()
        .listen(
          (snap) {
            final rows = snap.docs
                .map((d) => LedgerEntryModel.fromMap(d.data(), d.id))
                .toList()
              ..sort((a, b) {
                final t = a.txnId.compareTo(b.txnId);
                return t != 0 ? t : a.seq.compareTo(b.seq);
              });
            ledger.value = rows;
          },
          onError: (Object e) => debugPrint('ledger stream error: $e'),
        );

    // Webhook evidence for this payment. Matched on the payload's nested
    // payment id, which Firestore cannot query — so a bounded recent window is
    // streamed and filtered in memory. Acceptable because it is a detail
    // panel, not a queue, and the alternative is a denormalized index field on
    // an evidence collection that must stay exactly as the gateway sent it.
    _webhookSub = _db
        .collection('webhook_events')
        .orderBy('receivedAt', descending: true)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            webhookEvents.value = snap.docs
                .map((d) => WebhookEventModel.fromMap(d.data(), d.id))
                .where((w) => _mentionsPayment(w, s.razorpayPaymentId))
                .toList();
          },
          onError: onWebhookStreamError,
        );
  }

  bool _mentionsPayment(WebhookEventModel w, String paymentId) {
    if (paymentId.isEmpty) return false;
    // A shallow scan of the retained payload. Cheap, and correct for every
    // Razorpay event shape (payment / refund / dispute / payout all carry the
    // id either as `id` or `payment_id`).
    bool scan(Object? node, int depth) {
      if (depth > 6) return false;
      if (node is String) return node == paymentId;
      if (node is Map) {
        for (final v in node.values) {
          if (scan(v, depth + 1)) return true;
        }
      }
      if (node is List) {
        for (final v in node) {
          if (scan(v, depth + 1)) return true;
        }
      }
      return false;
    }

    return scan(w.payload, 0);
  }

  /// Keeps the open detail pane in sync with the live list, so a status change
  /// caused by the sweep — or by the founder's own action — is reflected
  /// without reopening the row.
  void syncSelected() {
    final id = selected.value?.id;
    if (id == null) return;
    final fresh = settlements.firstWhereOrNull((s) => s.id == id);
    if (fresh != null) selected.value = fresh;
  }

  // ── ACTIONS ───────────────────────────────────────────────────────────────
  //
  // Every one returns a result record rather than throwing, so the UI can show
  // the backend's own message. Those messages are written for the founder
  // ("A payout is in flight for this settlement and must resolve first") and
  // replacing them with a generic failure would send an operator to the logs
  // during exactly the incident the message was written to explain.

  Future<({bool ok, String message})> _guard(
    Future<String> Function() action,
  ) async {
    if (acting.value) {
      return (ok: false, message: 'Another action is still running.');
    }
    acting.value = true;
    try {
      final message = await action();
      await refreshSummary();
      return (ok: true, message: message);
    } on FirebaseFunctionsException catch (e) {
      return (ok: false, message: e.message ?? 'The action was refused.');
    } catch (e) {
      return (ok: false, message: e.toString());
    } finally {
      acting.value = false;
    }
  }

  Future<({bool ok, String message})> approve(String id, {String? note}) =>
      _guard(() async {
        final r = await SettlementService.approve(settlementId: id, note: note);
        return r.awaitingManual
            ? 'Approved. Transfer the money, then record the bank reference.'
            : r.message.isEmpty
                ? 'Approved and sent to the payout rail.'
                : r.message;
      });

  Future<({bool ok, String message})> hold(String id, String reason) =>
      _guard(() async {
        await SettlementService.hold(settlementId: id, reason: reason);
        return 'Held. The auto-settlement clock is stopped.';
      });

  Future<({bool ok, String message})> release(String id, {String? note}) =>
      _guard(() async {
        await SettlementService.release(settlementId: id, note: note);
        return 'Released. The hold period restarts from now.';
      });

  Future<({bool ok, String message})> cancel(String id, String reason) =>
      _guard(() async {
        await SettlementService.cancel(settlementId: id, reason: reason);
        return 'Cancelled. The liability remains posted until you adjust it.';
      });

  Future<({bool ok, String message})> retry(String id) => _guard(() async {
        final r = await SettlementService.retry(settlementId: id);
        return r.awaitingManual
            ? 'Retry authorised. Transfer the money, then record the reference.'
            : 'Retry sent to the payout rail.';
      });

  /// Confirms an AUTOMATED-RAIL payout the founder learned about from the rail
  /// (settlement in `settling`). UTR only — the rail did the transfer.
  Future<({bool ok, String message})> confirmPaid(String id, String utr) =>
      _guard(() async {
        await SettlementService.recordPayout(
          settlementId: id,
          settled: true,
          utr: utr,
        );
        return 'Settled. The payout is recorded against the ledger.';
      });

  /// Uploads a transfer proof to THIS settlement's own folder.
  ///
  /// The path is constructed HERE, never accepted from a caller — the UI can
  /// pick a file but can never pick a settlement id, so a proof cannot be
  /// steered into another settlement's folder. The Storage rules enforce the
  /// same boundary independently (super-admin write, refused once settled).
  ///
  /// Returns the storage path. Throws on failure or cancellation — the dialog
  /// shows the reason and lets the founder retry.
  Future<String> uploadProof({
    required String settlementId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final problem = proofFileProblem(mime: contentType, sizeBytes: bytes.length);
    if (problem != null) throw StateError(problem);

    // A timestamped name so a corrected re-upload never overwrites the file a
    // previous attempt may have referenced; the stray object is inert.
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'settlement_proofs/$settlementId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final task = FirebaseStorage.instance.ref(path).putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            // The backend reads this custom key for `proof.uploadedBy`,
            // falling back to the confirming founder when absent.
            customMetadata: {
              'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
            },
          ),
        );
    _uploadTask = task;
    uploadProgress.value = 0;
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) {
        uploadProgress.value = s.bytesTransferred / s.totalBytes;
      }
    });
    try {
      await task;
      // Verify the object actually landed — a resumed/cancelled task can
      // complete without success on web.
      final meta = await FirebaseStorage.instance.ref(path).getMetadata();
      if ((meta.size ?? 0) <= 0) {
        throw StateError('The upload did not complete. Try again.');
      }
      return path;
    } finally {
      await sub.cancel();
      _uploadTask = null;
      uploadProgress.value = -1;
    }
  }

  void cancelUpload() {
    _uploadTask?.cancel();
  }

  /// The V1 MANUAL settle: full evidence, exactly as the backend gate demands.
  ///
  /// The backend re-reads the settlement inside its transaction and re-runs
  /// every check there — this call transports the founder's assertions, it
  /// does not establish them. A refusal comes back with the backend's own
  /// founder-facing message and is surfaced verbatim.
  Future<({bool ok, String message})> confirmTransfer({
    required String settlementId,
    required String utr,
    required DateTime transferredAt,
    required String method,
    required int amountMinor,
    String? notes,
    String? internalNote,
    String? proofStoragePath,
  }) =>
      _guard(() async {
        await SettlementService.recordPayout(
          settlementId: settlementId,
          settled: true,
          utr: utr,
          transferredAtMs: transferredAt.millisecondsSinceEpoch,
          transferMethod: method,
          transferAmountMinor: amountMinor,
          proofStoragePath: proofStoragePath,
          transferNotes: notes,
          internalNote: internalNote,
        );
        return 'Transfer confirmed. The settlement is now settled and the '
            'payout is on the ledger.';
      });

  Future<({bool ok, String message})> markFailed(
    String id,
    String reason,
  ) =>
      _guard(() async {
        await SettlementService.recordPayout(
          settlementId: id,
          settled: false,
          failureReason: reason,
          message: reason,
        );
        return 'Recorded as failed.';
      });

  /// Refunds the member at the gateway.
  ///
  /// The settlement is NOT updated here. Razorpay emits `refund.processed`, the
  /// webhook applies the reversal to the settlement and the ledger atomically,
  /// and this list re-renders when that lands. Optimistically rewriting the row
  /// would put the console ahead of the ledger — and if the webhook never
  /// arrived, permanently wrong.
  Future<({bool ok, String message})> refund(
    String razorpayPaymentId, {
    int? amountRupees,
    String? reason,
  }) =>
      _guard(() async {
        final r = await SettlementService.refundMemberPayment(
          razorpayPaymentId: razorpayPaymentId,
          amountRupees: amountRupees,
          reason: reason,
        );
        return 'Refund ${r.refundId} ${r.status} at the gateway. The '
            'settlement updates when Razorpay confirms it.';
      });

  Future<({bool ok, String message})> postAdjustment({
    required String account,
    required String direction,
    required int amountMinor,
    required String memo,
    String? settlementId,
    String? adminId,
  }) =>
      _guard(() async {
        final txnId = await SettlementService.postAdjustment(
          account: account,
          direction: direction,
          amountMinor: amountMinor,
          memo: memo,
          settlementId: settlementId,
          adminId: adminId,
        );
        return 'Adjustment posted ($txnId).';
      });
}
