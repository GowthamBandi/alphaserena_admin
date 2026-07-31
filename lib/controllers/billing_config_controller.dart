// lib/controllers/billing_config_controller.dart
//
// Form state + persistence for `platform_billing/config`.
//
// This is the highest-blast-radius document in the console: a wrong rate here
// changes what every gym on the platform is charged on their next renewal. The
// controller therefore (a) validates before writing, (b) never writes a partial
// document, and (c) exposes a live worked example so the founder sees the
// actual rupees a buyer will pay BEFORE saving.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/billing_config_model.dart';
import '../widgets/app_snackbar.dart';

/// Turns a Firestore failure into something the founder can act on, and logs
/// the raw error for us. A permission denial here almost always means the
/// `platform_billing` rule has not been deployed yet — saying so beats printing
/// the SDK's sentence about insufficient permissions.
String _billingError(Object e, {required String action}) {
  debugPrint('💰 [BillingConfig] $action failed: $e');
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Your account cannot edit platform billing. If you are the '
            'founder, the billing security rule may not be deployed yet.';
      case 'unavailable':
        return 'Cannot reach Firestore. Check your connection and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

class BillingConfigController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'platform_billing';
  static const String _docId = 'config';

  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;

  final RxBool enabled = false.obs;
  final RxString currency = 'INR'.obs;
  final RxList<TaxRule> taxes = <TaxRule>[].obs;

  /// The example amount the live preview prices, in whole rupees.
  final RxDouble samplePrice = 1999.0.obs;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    _sub = _db.collection(_collection).doc(_docId).snapshots().listen(
      (snap) {
        final cfg = BillingConfigModel.fromMap(snap.data() ?? const {});
        enabled.value = cfg.enabled;
        currency.value = cfg.currency;
        taxes.assignAll(cfg.taxes);
        isLoading.value = false;
      },
      onError: (Object e) {
        isLoading.value = false;
        AppSnackbar.show(
          title: 'Could not load billing settings',
          message: _billingError(e, action: 'load'),
        );
      },
    );
  }

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
  int get inclusiveTaxMinor {
    final cfg = draft;
    final combined = cfg.inclusivePercent;
    if (combined <= 0) return 0;
    final net = ((_sampleMinor * 100) / (100 + combined)).round();
    return _sampleMinor - net;
  }

  /// What the buyer is actually charged, in minor units.
  int get grandTotalMinor => _sampleMinor + exclusiveTaxMinor;

  Future<void> save() async {
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
      await _db
          .collection(_collection)
          .doc(_docId)
          .set(model.toMap(), SetOptions(merge: true));
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
