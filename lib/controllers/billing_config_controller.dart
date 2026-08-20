// lib/controllers/billing_config_controller.dart
//
// Form state + persistence for `platform_config/commerce`.
//
// This is the highest-blast-radius document in the console: a wrong rate here
// changes what every gym on the platform is charged on their next renewal. The
// controller therefore (a) validates before writing, (b) never writes a partial
// document, and (c) exposes a live worked example so the founder sees the
// actual rupees a buyer will pay BEFORE saving.
//
// ─────────────────────────────────────────────────────────────────────────
// READ DIRECT, WRITE THROUGH THE SERVER — and why it is asymmetric
// ─────────────────────────────────────────────────────────────────────────
// `platform_config` is `allow read: if isSuperAdmin()` and
// `allow write: if false`. That asymmetry is deliberate and predates this
// screen: the same document family holds the settlement fee terms, and
// `setSettlementConfig` has always been the only way to write them.
//
// This editor previously wrote `platform_billing/config` straight from the
// client. That collection is declared in NO ruleset, and the rules file has no
// wildcard fallback, so every read and write was default-denied — the editor
// could neither load nor save. Worse, the billing engine has never read that
// path: `subscriptions.ts:loadTaxRules` prices from `platform_config/commerce`,
// so even an allowed write would have authored tax into a document nothing
// charges from.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/utils/console_errors.dart';
import '../models/billing_config_model.dart';
import '../widgets/app_snackbar.dart';

/// Turns a backend failure into something the founder can act on, and logs the
/// raw error for us.
///
/// `invalid-argument` is passed through VERBATIM: it is the server's copy of
/// the same validation the dialog runs, and its text names the offending tax.
/// Replacing it with a generic sentence would hide the one message that says
/// what to fix. Every other code is translated — the SDK's own wording either
/// leaks a collection path or tells the founder nothing actionable.
String _billingError(Object e, {required String action}) {
  debugPrint('💰 [BillingConfig] $action failed: $e');
  if (e is FirebaseFunctionsException) {
    switch (e.code) {
      case 'invalid-argument':
        return e.message ?? 'Check the billing settings.';
      case 'permission-denied':
        return 'Your account is not a platform super-admin, so it cannot '
            'change billing.';
      case 'unauthenticated':
        return 'Your session expired. Sign in again and retry.';
      case 'not-found':
        return 'The billing service is unavailable. It may not be deployed '
            'yet — contact engineering before retrying.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Could not reach the billing service. Check your connection '
            'and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Your account cannot read platform billing. Only a platform '
            'super-admin can open this screen.';
      case 'unavailable':
        return 'Cannot reach Firestore. Check your connection and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

class BillingConfigController extends GetxController {
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the dialog's states without a network. Matches the five
  // controllers that already do this.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// The canonical commerce document — the one `loadTaxRules` prices from.
  static const String _collection = 'platform_config';
  static const String _docId = 'commerce';

  /// The privileged write path. `platform_config` is not client-writable.
  static const String _saveCallable = 'setCommerceConfig';

  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;

  /// Set when the READ failed.
  ///
  /// 🔴 Why this cannot be a snackbar. On error this controller used to set
  /// `isLoading = false` and leave `enabled = false` with an empty tax list —
  /// which is byte-for-byte what a platform that has never charged tax looks
  /// like. The dialog then rendered its ordinary editor over a document it had
  /// not read, and its Save button republishes `taxes` and `authoredTaxes` as
  /// WHOLE arrays. One click on a screen that was merely blind wipes the live
  /// tax table for every future order.
  ///
  /// The dialog renders this instead of the editor, so the destructive control
  /// does not exist while the read is unproven.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

  final RxBool enabled = false.obs;
  final RxString currency = 'INR'.obs;
  final RxList<TaxRule> taxes = <TaxRule>[].obs;

  /// The example amount the live preview prices, in whole rupees.
  final RxDouble samplePrice = 1999.0.obs;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// (Re)subscribes to the commerce document.
  void load() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    _sub = _db
        .collection(_collection)
        .doc(_docId)
        .snapshots()
        .listen(
          (snap) {
            final cfg = BillingConfigModel.fromMap(snap.data() ?? const {});
            enabled.value = cfg.enabled;
            currency.value = cfg.currency;
            taxes.assignAll(cfg.taxes);
            loadError.value = null;
            isLoading.value = false;
          },
          onError: (Object e) {
            isLoading.value = false;
            // Classified and PERSISTENT. The snackbar stays as the immediate
            // signal; the state is what stops the editor rendering a tax table
            // nobody read.
            loadError.value =
                describeStreamError(e, subject: 'the platform tax table');
            debugPrint('platform_config/commerce stream error: $e');
            AppSnackbar.show(
              title: 'Could not load billing settings',
              message: _billingError(e, action: 'load'),
            );
          },
        );
  }

  void retryLoad() => load();

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  BillingConfigModel get draft => BillingConfigModel(
    enabled: enabled.value,
    currency: currency.value,
    taxes: taxes.toList(),
  );

  void addTax() =>
      taxes.add(const TaxRule(name: '', percent: 0, inclusive: false));

  void removeTax(int i) {
    if (i >= 0 && i < taxes.length) taxes.removeAt(i);
  }

  void updateTax(int i, TaxRule rule) {
    if (i >= 0 && i < taxes.length) taxes[i] = rule;
  }

  // ── Live worked example ──────────────────────────────────────────────────
  // Mirrors functions/src/lib/pricing.ts exactly (integer minor units, tax on
  // the post-discount amount, inclusive carved out rather than added). It is a
  // PREVIEW only — the server's computation is what is charged.

  int get _sampleMinor => (samplePrice.value * 100).round();

  /// Tax added on top of the plan price, in minor units.
  int get exclusiveTaxMinor {
    final cfg = draft;
    var total = 0;
    for (final t in cfg.liveTaxes.where((t) => !t.inclusive)) {
      total += ((_sampleMinor * t.percent) / 100).round();
    }
    return total;
  }

  /// Tax already contained in the plan price, in minor units.
  ///
  /// 🔴 PER RULE, exactly as `pricing.ts:priceQuote` computes it:
  ///
  ///     amountMinor = round(taxable - taxable / (1 + p/100))
  ///
  /// This previously carved ONE combined rate out of the price
  /// (`sample - round(sample*100/(100+Σp))`). The two agree for a single
  /// inclusive rule and diverge for two — which is the ordinary Indian case,
  /// where GST is authored as CGST 9% + SGST 9% rather than as one 18% line.
  /// On a ₹1000 plan that is ₹165.14 on the buyer's receipt against ₹152.54 in
  /// the founder's preview. Inclusive tax never changes what is CHARGED, so
  /// this was a disclosure defect rather than a pricing one — but the preview
  /// exists precisely so the founder does not have to imagine the outcome, and
  /// the comment above it already promised this mirrored the server exactly.
  ///
  /// The server is the authority. Where they disagreed, the preview moved.
  int get inclusiveTaxMinor {
    final cfg = draft;
    var total = 0;
    for (final t in cfg.liveTaxes.where((t) => t.inclusive)) {
      final amount =
          (_sampleMinor - _sampleMinor / (1 + t.percent / 100)).round();
      if (amount <= 0) continue;
      total += amount;
    }
    return total;
  }

  /// What the buyer is actually charged, in minor units.
  int get grandTotalMinor => _sampleMinor + exclusiveTaxMinor;

  /// The privileged write itself.
  ///
  /// A seam so the double-submit guard below can be PROVEN rather than
  /// asserted: a test counts invocations while firing two saves at once.
  /// Production always binds the real callable.
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> payload) publishCall =
      _callSetCommerceConfig;

  static Future<void> _callSetCommerceConfig(Map<String, dynamic> payload) =>
      FirebaseFunctions.instance
          .httpsCallable(_saveCallable)
          .call<Map<String, dynamic>>(payload);

  Future<void> save() async {
    // The button is disabled while saving, but a UI guard is not the
    // controller's guard — the same rule `AdminController._setStatus` follows.
    // `setCommerceConfig` writes an audit row per call, so a double-click on a
    // cold-started callable records two changes to the platform's commercial
    // terms for one decision.
    if (isSaving.value) return;
    final model = draft;
    final errors = model.validate();
    if (errors.isNotEmpty) {
      AppSnackbar.show(
        title: 'Check the billing settings',
        message: errors.join('\n'),
      );
      return;
    }
    try {
      isSaving.value = true;
      // The server derives the effective table, stamps `updatedAt`/`updatedBy`
      // and writes the audit entry. Deliberately NOT a Firestore write: this
      // document is `allow write: if false` for every client.
      await publishCall(model.toPayload());
      // The snapshot listener re-renders from what was actually stored, so no
      // local state is assumed to have landed.
      AppSnackbar.show(
        title: 'Billing settings saved',
        message: model.enabled
            ? 'New orders will be priced with these taxes.'
            : 'Tax is off — buyers are charged exactly the plan price.',
      );
    } catch (e) {
      AppSnackbar.show(
        title: 'Could not save',
        message: _billingError(e, action: 'save'),
      );
    } finally {
      isSaving.value = false;
    }
  }
}
