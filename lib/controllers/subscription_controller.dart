// lib/controllers/subscription_controller.dart
//
// Commercial catalog controller — the founder console is the single authoring
// source of truth for `subscription_plans`. Owns the plan list stream and the
// Plan Editor form state (identity, dual pricing, extensible limits,
// capabilities), with all persistence flowing through SubscriptionPlanModel so
// the backend + TrainerHQ read contract is preserved.

import 'dart:async';

import 'package:alphaserena_admin_portel/core/services/plan_highlights.dart';
import 'package:alphaserena_admin_portel/core/validation/capability_dependencies.dart';
import 'package:alphaserena_admin_portel/core/validation/plan_validation.dart';
import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/subscription_plan_model.dart';

class SubscriptionController extends GetxController {
  // Resolved lazily: constructing the controller must not require an
  // initialized Firebase app (widget tests build the editor with a subclass
  // that skips the stream, and nothing else touches Firestore until a real
  // read/write happens).
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'subscription_plans';

  // =========================================================
  // STATE
  // =========================================================
  final RxList<SubscriptionPlanModel> plans = <SubscriptionPlanModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  /// Catalog status filter (null = all).
  final Rx<PlanStatus?> statusFilter = Rx<PlanStatus?>(null);

  List<SubscriptionPlanModel> get filteredPlans {
    final f = statusFilter.value;
    return f == null ? plans : plans.where((p) => p.status == f).toList();
  }

  List<SubscriptionPlanModel> get publishedPlans =>
      plans.where((p) => p.status == PlanStatus.published).toList();

  int statusCount(PlanStatus s) =>
      plans.where((p) => p.status == s).length;

  StreamSubscription? _sub;

  // =========================================================
  // EDIT MODE
  // =========================================================
  final RxString editingDocId = ''.obs;
  bool get isEditMode => editingDocId.value.isNotEmpty;

  DateTime? _editingCreatedAt;

  // =========================================================
  // FORM — IDENTITY
  // =========================================================
  final planNameCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final badgeCtrl = TextEditingController();
  final sortOrderCtrl = TextEditingController(text: '0');

  /// Commercial lifecycle chosen in the editor. Published = live & sold,
  /// Hidden = retained but not sold, Archived = retired (deletable).
  final Rx<PlanStatus> planStatus = PlanStatus.published.obs;
  final RxBool featured = false.obs;

  bool get _formPublished => planStatus.value == PlanStatus.published;

  // =========================================================
  // FORM — PRICING
  // =========================================================
  final monthlyPriceCtrl = TextEditingController();
  final yearlyPriceCtrl = TextEditingController();

  /// The plan's term in months — the single source of truth for the billing
  /// period. Tapping Monthly/Yearly sets it to 1/12; a loaded legacy plan keeps
  /// its exact term (e.g. 6) until the owner explicitly picks a period, so an
  /// edit never silently collapses the term.
  final RxInt termMonths = 1.obs;

  BillingPeriod get selectedPeriod =>
      termMonths.value >= 12 ? BillingPeriod.yearly : BillingPeriod.monthly;

  /// Sensible, non-zero starter caps so a brand-new plan never accidentally
  /// saves a limit of 0 (which for team members would block the feature).
  static const Map<PlanResource, int> _defaultLimits = {
    PlanResource.teamMembers: 2,
    PlanResource.activeClients: 50,
    PlanResource.workoutPlans: 20,
    PlanResource.dietPlans: 20,
    PlanResource.exerciseLibrary: 100,
  };

  // =========================================================
  // FORM — LIMITS
  // One controller + one "unlimited" flag per resource.
  // =========================================================
  final Map<PlanResource, TextEditingController> limitCtrls = {
    for (final r in PlanResource.values)
      r: TextEditingController(text: '${_defaultLimits[r] ?? 0}'),
  };
  final RxMap<PlanResource, bool> limitUnlimited = <PlanResource, bool>{
    for (final r in PlanResource.values) r: false,
  }.obs;

  // =========================================================
  // FORM — CAPABILITIES
  // =========================================================
  // Progress defaults ON for a new plan: it is today's ungated baseline in
  // TrainerHQ, and the backend projects capabilities onto `admins.features`
  // at activation — a plan authored without it would genuinely revoke the
  // feature on the buyer's next renewal. The founder can still turn it off.
  final RxMap<String, bool> capabilities = <String, bool>{
    for (final s in PlanCapabilities.slugs) s: s == PlanCapabilities.progress,
  }.obs;

  // =========================================================
  // FORM — HIGHLIGHTS
  // `points` holds the founder's hand-written marketing lines and NOTHING
  // else. Capacity is already on the card as chips, so nothing is generated:
  // what is typed here is exactly what the buyer reads.
  // =========================================================
  final RxList<String> points = <String>[].obs;

  // =========================================================
  // INIT
  // =========================================================
  @override
  void onInit() {
    super.onInit();
    fetchPlans();
  }

  // =========================================================
  // FETCH PLANS (REALTIME) — sorted by owner sort order, then price.
  // =========================================================
  void fetchPlans() {
    isLoading.value = true;
    _sub?.cancel();

    _sub = _db.collection(_collection).snapshots().listen(
      (snapshot) {
        final list = snapshot.docs
            .map((d) => SubscriptionPlanModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) {
          final o = a.sortOrder.compareTo(b.sortOrder);
          return o != 0 ? o : a.price.compareTo(b.price);
        });
        plans.value = list;
        isLoading.value = false;
      },
      onError: (e) {
        isLoading.value = false;
        AppSnackbar.show(title: "Error", message: "Failed to load plans");
      },
    );
  }

  // =========================================================
  // CLEAR FORM
  // =========================================================
  void clearForm() {
    editingDocId.value = '';
    _editingCreatedAt = null;

    planNameCtrl.clear();
    descriptionCtrl.clear();
    badgeCtrl.clear();
    sortOrderCtrl.text = _nextSortOrder().toString();
    planStatus.value = PlanStatus.published;
    featured.value = false;

    monthlyPriceCtrl.clear();
    yearlyPriceCtrl.clear();
    termMonths.value = 1;

    for (final r in PlanResource.values) {
      limitCtrls[r]!.text = '${_defaultLimits[r] ?? 0}';
      limitUnlimited[r] = false;
    }
    // Same baseline the field initializer authors for a brand-new controller:
    // Progress ON. clearForm() runs on EVERY "New plan", so seeding false here
    // would have every plan authored after the first silently sold without the
    // capability — and the backend projection would then revoke the feature on
    // the buyer's next renewal.
    for (final s in PlanCapabilities.slugs) {
      capabilities[s] = s == PlanCapabilities.progress;
    }
    points.clear();
  }

  /// Suggest the next free sort order so new plans don't collide by default.
  int _nextSortOrder() {
    if (plans.isEmpty) return 0;
    final maxOrder =
        plans.map((p) => p.sortOrder).fold<int>(-1, (a, b) => b > a ? b : a);
    return maxOrder + 1;
  }

  // =========================================================
  // LOAD FOR EDIT
  // =========================================================
  void loadPlanForEdit(SubscriptionPlanModel plan) {
    editingDocId.value = plan.docId;
    _editingCreatedAt = plan.createdAt;

    planNameCtrl.text = plan.planName;
    descriptionCtrl.text = plan.description;
    badgeCtrl.text = plan.badge;
    sortOrderCtrl.text = plan.sortOrder.toString();
    planStatus.value = plan.status;
    featured.value = plan.featured;

    monthlyPriceCtrl.text = _priceText(plan.monthlyPrice);
    yearlyPriceCtrl.text = _priceText(plan.yearlyPrice);
    termMonths.value = plan.durationMonths; // preserve the exact term

    for (final r in PlanResource.values) {
      final v = plan.limitOf(r);
      final isUnlimited = v == SubscriptionPlanModel.unlimited;
      limitUnlimited[r] = isUnlimited;
      // Unlimited leaves the number field EMPTY (not '0') so toggling
      // Unlimited off never presents a value that validation rejects.
      limitCtrls[r]!.text = isUnlimited ? '' : v.toString();
    }
    // A LEGACY plan declares no capabilities at all (empty map): orgs on it
    // are ungated today, so ALL capability slugs are seeded ON — the truthful
    // baseline of what its buyers can do right now. Anything less (or an
    // all-false map from merely re-saving) would have the backend projection
    // revoke features on every buyer's next renewal. The founder can then
    // deliberately disable what this tier should not include.
    final legacyUngated = plan.capabilities.isEmpty;
    for (final s in PlanCapabilities.slugs) {
      capabilities[s] = legacyUngated || plan.capable(s);
    }
    // A legacy plan could carry a capability its capacity no longer supports —
    // drop any impossible one so the editor opens in a saveable state.
    reconcileCapabilities();
    // Legacy docs (no customPoints field) load their whole points list here so
    // nothing hand-written is lost. A doc saved under the old generate+compose
    // rule keeps only its custom lines — the generated bullets it carried in
    // `points` are dropped on the next save, which is the intent.
    points.assignAll(PlanHighlights.sanitize(plan.customPoints));
  }

  static String _priceText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // =========================================================
  // READ FORM → resolved values
  // =========================================================
  Map<PlanResource, int> _resolvedLimits() {
    final out = <PlanResource, int>{};
    for (final r in PlanResource.values) {
      if (limitUnlimited[r] == true) {
        out[r] = SubscriptionPlanModel.unlimited;
      } else {
        out[r] = int.tryParse(limitCtrls[r]!.text.trim()) ?? 0;
      }
    }
    return out;
  }

  /// The limits currently entered in the form (decoded; -1 = Unlimited) for
  /// LIVE capability-dependency evaluation. A resource whose text field is
  /// empty (and not Unlimited) is OMITTED — "no information", not 0 — so a
  /// transient mid-edit state never reads as a hard zero.
  Map<PlanResource, int> currentLimits() {
    final limits = _resolvedLimits();
    for (final r in PlanResource.values) {
      if (limitUnlimited[r] != true && limitCtrls[r]!.text.trim().isEmpty) {
        limits.remove(r);
      }
    }
    return limits;
  }

  /// Turn off any enabled capability whose capacity dependency is no longer
  /// met, so the editor can never hold — or save — an impossible plan.
  ///
  /// A limit whose text field is transiently EMPTY (select-all-delete mid-edit,
  /// Unlimited toggle off) is treated as "no information", NOT as 0 — its
  /// dependency rules are skipped so a keystroke can never silently disable a
  /// capability that would then stay off. Save-time validation still catches a
  /// field left empty (it resolves to 0 there and 0 is rejected).
  void reconcileCapabilities() {
    // currentLimits() omits empty (no-information) fields so blockerFor
    // treats them as unconstrained instead of 0.
    final limits = currentLimits();
    for (final slug in PlanCapabilities.slugs) {
      if (capabilities[slug] == true &&
          CapabilityDependencies.blockerFor(slug, limits) != null) {
        capabilities[slug] = false;
      }
    }
  }

  /// Per-month prices of the published plans OTHER than the one being edited,
  /// feeding the live preview's cross-catalog BEST VALUE / savings framing
  /// (the same arithmetic TrainerHQ runs over the visible catalog).
  List<double> publishedPeerPerMonth() => plans
      .where((p) =>
          p.status == PlanStatus.published && p.docId != editingDocId.value)
      .map((p) => p.durationMonths > 0 ? p.price / p.durationMonths : p.price)
      .toList();

  List<PlanPeer> _peers() => plans
      .map((p) => PlanPeer(
            docId: p.docId,
            name: p.planName,
            badge: p.badge,
            sortOrder: p.sortOrder,
            isActive: p.isActive,
          ))
      .toList();

  // =========================================================
  // SAVE PLAN (CREATE / UPDATE)
  // =========================================================
  Future<void> savePlan() async {
    if (isSaving.value) return;

    final limits = _resolvedLimits();
    final capsMap = Map<String, bool>.from(capabilities);
    final monthlyPrice = double.tryParse(monthlyPriceCtrl.text.trim()) ?? 0;
    final yearlyPrice = double.tryParse(yearlyPriceCtrl.text.trim()) ?? 0;
    final sortOrder = int.tryParse(sortOrderCtrl.text.trim()) ?? 0;

    // Only a Published plan is live (isActive) and only a live plan may be
    // featured; Archived always implies not live.
    final isActive = _formPublished;
    final isArchived = planStatus.value == PlanStatus.archived;
    final isFeatured = isActive && featured.value;

    final errors = PlanValidation.validate(
      name: planNameCtrl.text,
      badge: badgeCtrl.text,
      sortOrder: sortOrder,
      active: isActive,
      featured: isFeatured,
      billingPeriod: selectedPeriod,
      durationMonths: termMonths.value,
      monthlyPrice: monthlyPrice,
      yearlyPrice: yearlyPrice,
      limits: limits,
      capabilities: capsMap,
      peers: _peers(),
      selfDocId: editingDocId.value,
    );
    if (errors.isNotEmpty) {
      AppSnackbar.show(title: "Check the plan", message: errors.first);
      return;
    }

    final now = DateTime.now();
    final docId = isEditMode
        ? editingDocId.value
        : _db.collection(_collection).doc().id;

    final plan = SubscriptionPlanModel(
      id: docId,
      docId: docId,
      planName: planNameCtrl.text.trim(),
      description: descriptionCtrl.text.trim(),
      badge: badgeCtrl.text.trim(),
      sortOrder: sortOrder,
      isActive: isActive,
      archived: isArchived,
      featured: isFeatured,
      monthlyPrice: monthlyPrice,
      yearlyPrice: yearlyPrice,
      durationMonths: termMonths.value,
      limits: limits,
      capabilities: capsMap,
      // The rendered list TrainerHQ shows IS the founder's list — the two
      // fields are deliberately identical now that nothing is generated.
      points: PlanHighlights.sanitize(points),
      customPoints: PlanHighlights.sanitize(points),
      createdAt: isEditMode ? (_editingCreatedAt ?? now) : now,
      updatedAt: now,
    );

    isSaving.value = true;
    try {
      await _db.collection(_collection).doc(docId).set(plan.toMap());
      // Only close the editor if it is still open: a founder who dismissed the
      // dialog while a slow write was in flight must not have the page behind
      // it popped out from under them.
      if (Get.isDialogOpen ?? false) Get.back();
      AppSnackbar.show(
        title: "Success",
        message: isEditMode ? "Plan updated" : "Plan created",
        background: Colors.green,
      );
      clearForm();
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Failed to save plan");
    } finally {
      isSaving.value = false;
    }
  }

  // =========================================================
  // DELETE PLAN
  // =========================================================
  bool _deletingPlan = false;

  Future<void> deletePlan(String docId) async {
    if (_deletingPlan) return; // re-entry guard (double-click)
    _deletingPlan = true;
    try {
      await _db.collection(_collection).doc(docId).delete();
      AppSnackbar.show(title: "Deleted", message: "Plan removed");
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Delete failed");
    } finally {
      _deletingPlan = false;
    }
  }

  // =========================================================
  // STATUS LIFECYCLE (publish / hide / archive / restore)
  // Stored as isActive + archived; the backend & TrainerHQ only read isActive
  // (verifyAndActivateSubscription rejects isActive:false), so existing
  // subscribers always keep their plan regardless of these transitions.
  // =========================================================
  bool _settingStatus = false;

  Future<void> setPlanStatus(
    SubscriptionPlanModel plan,
    PlanStatus target,
  ) async {
    if (_settingStatus) return; // re-entry guard (double-click)
    if (plan.status == target) return;

    // Going live (Published) must pass the same uniqueness gate as a save — a
    // cloned/edited draft could otherwise publish with a badge or sort order
    // that collides with another live plan.
    if (target == PlanStatus.published) {
      final conflict = _reactivationConflict(plan);
      if (conflict != null) {
        AppSnackbar.show(title: "Can't publish yet", message: conflict);
        return;
      }
      // ...and the FULL save-time validation: a hidden draft with a 0 price,
      // a 0/missing limit, or an impossible capability must not go live from
      // the card menu when savePlan would have rejected it.
      final errors = PlanValidation.validate(
        name: plan.planName,
        badge: plan.badge,
        sortOrder: plan.sortOrder,
        active: true,
        featured: plan.featured,
        billingPeriod: plan.billingPeriod,
        durationMonths: plan.durationMonths,
        monthlyPrice: plan.monthlyPrice,
        yearlyPrice: plan.yearlyPrice,
        limits: plan.limits,
        capabilities: plan.capabilities,
        peers: _peers(),
        selfDocId: plan.docId,
      );
      if (errors.isNotEmpty) {
        AppSnackbar.show(title: "Can't publish yet", message: errors.first);
        return;
      }
    }

    final isActive = target == PlanStatus.published;
    final isArchived = target == PlanStatus.archived;
    _settingStatus = true;
    try {
      await _db.collection(_collection).doc(plan.docId).update({
        'isActive': isActive,
        'archived': isArchived,
        // Only a live plan may stay featured.
        if (!isActive) 'featured': false,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      AppSnackbar.show(
        title: target.label,
        message: switch (target) {
          PlanStatus.published => "Plan is live and purchasable",
          PlanStatus.hidden => "Plan hidden from new subscribers",
          PlanStatus.archived => "Plan archived",
        },
        background: Colors.green,
      );
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Could not update plan status");
    } finally {
      _settingStatus = false;
    }
  }

  /// Uniqueness reasons a draft cannot be activated as-is, or null when clear.
  String? _reactivationConflict(SubscriptionPlanModel plan) {
    for (final other in plans) {
      if (other.docId == plan.docId || !other.isActive) continue;
      if (other.sortOrder == plan.sortOrder) {
        return 'Sort order ${plan.sortOrder} is already used by "${other.planName}". Edit this plan first.';
      }
      if (plan.badge.isNotEmpty &&
          other.badge.trim().toLowerCase() ==
              plan.badge.trim().toLowerCase()) {
        return 'The badge "${plan.badge}" is already used by "${other.planName}". Edit this plan first.';
      }
    }
    return null;
  }

  // =========================================================
  // CLONE PLAN — one-click duplicate, saved as an INACTIVE draft.
  // =========================================================
  bool _cloningPlan = false;

  Future<void> clonePlan(SubscriptionPlanModel plan) async {
    if (_cloningPlan) return; // re-entry guard (double-click = two drafts)
    _cloningPlan = true;
    try {
      final now = DateTime.now();
      final docId = _db.collection(_collection).doc().id;
      // A draft copy must not carry a live plan's unique identity — clear the
      // badge, drop featured, and give it a fresh sort order so it can never
      // collide when later activated.
      final copy = plan.copyWith(
        id: docId,
        docId: docId,
        planName: "${plan.planName} (Copy)",
        badge: '',
        featured: false,
        sortOrder: _nextSortOrder(),
        isActive: false,
        archived: false, // a clone is a fresh Hidden draft, never archived
        createdAt: now,
        updatedAt: now,
      );
      await _db.collection(_collection).doc(docId).set(copy.toMap());
      AppSnackbar.show(
        title: "Cloned",
        message: "Draft copy created (inactive) — edit then activate",
        background: Colors.green,
      );
    } catch (e) {
      AppSnackbar.show(title: "Error", message: "Could not clone plan");
    } finally {
      _cloningPlan = false;
    }
  }

  // =========================================================
  // FEATURE BULLETS
  // =========================================================
  /// Adds a highlight. Returns false when nothing was added — blank input, or
  /// a line already present (case-insensitively). Refusing the duplicate here
  /// keeps the editor's chips and the buyer's bullets identical; the old
  /// behaviour accepted it and let save-time dedup drop it silently.
  bool addPoint(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    if (PlanHighlights.isDuplicate(points, text)) return false;
    points.add(text);
    return true;
  }

  void removePoint(int index) {
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
  }

  // =========================================================
  // CLEANUP
  // =========================================================
  @override
  void onClose() {
    _sub?.cancel();
    planNameCtrl.dispose();
    descriptionCtrl.dispose();
    badgeCtrl.dispose();
    sortOrderCtrl.dispose();
    monthlyPriceCtrl.dispose();
    yearlyPriceCtrl.dispose();
    for (final c in limitCtrls.values) {
      c.dispose();
    }
    super.onClose();
  }
}
