// lib/controllers/coupon_controller.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/constants/firestore_collections.dart';
import '../models/coupon_model.dart';
import '../core/utils/console_errors.dart';

class CouponController extends GetxController {
  // Resolved LAZILY. Constructing the controller must not require an
  // initialized Firebase app, so a widget test can subclass it, skip onInit,
  // and drive the screen's states without a network. Matches
  // SubscriptionController, which already did this for the plan editor.
  late final FirebaseFirestore _db = FirebaseFirestore.instance;

  // STATES
  RxBool isLoading = false.obs;
  RxBool isSaving = false.obs;

  // LIST OF COUPONS
  RxList<CouponModel> coupons = <CouponModel>[].obs;
  /// Set when the stream itself failed. Rendered as a classified error state —
  /// an empty list must never be shown for a load that did not happen.
  final Rxn<ConsoleError> loadError = Rxn<ConsoleError>();

  // SEARCH FIELD
  RxString searchQuery = "".obs;

  // FORM CONTROLLERS
  final codeCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final discountCtrl = TextEditingController();
  // 0 = unlimited redemptions (matches the backend cap gate `maxUsage > 0`).
  final maxUsageCtrl = TextEditingController(text: "0");

  RxBool isPercentage = false.obs;

  /// DRAFT Active value for the edit dialog — only written on Save, so
  /// flipping the switch then pressing Cancel changes nothing.
  RxBool draftActive = true.obs;
  Rx<DateTime> validFrom = DateTime.now().obs;
  Rx<DateTime> validTo = DateTime.now().add(const Duration(days: 30)).obs;

  // TRACK WHICH DOCUMENT IS BEING EDITED
  RxString editDocId = "".obs;

  // FIRESTORE COLLECTION NAME — canonical, ecosystem-shared `coupon_codes`.
  // (Was the orphan `master_coupons`, which trainersHQ's checkout coupon
  // validator + platform_service never read → founder coupons were unredeemable.)
  final String collectionName = FsCollections.couponCodes;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    fetchCoupons();
  }

  @override
  void onClose() {
    _sub?.cancel();
    codeCtrl.dispose();
    descCtrl.dispose();
    discountCtrl.dispose();
    maxUsageCtrl.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // REAL-TIME FETCH COUPONS
  // ---------------------------------------------------------------------------
  void retryLoad() => fetchCoupons();

  void fetchCoupons() {
    isLoading.value = true;
    loadError.value = null;
    _sub?.cancel();
    _sub = _db
        .collection(collectionName)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen((snapshot) {
      coupons.value = snapshot.docs
          .map((d) => CouponModel.fromMap(d.id, d.data()))
          .toList();
      loadError.value = null;
      isLoading.value = false;
    }, onError: (Object e) {
      isLoading.value = false;
      loadError.value = describeStreamError(e, subject: 'the coupon catalog');
      debugPrint('coupon_codes stream error: $e');
    });
  }

  // ---------------------------------------------------------------------------
  // CLEAR FORM
  // ---------------------------------------------------------------------------
  void clearForm() {
    editDocId.value = "";
    codeCtrl.clear();
    descCtrl.clear();
    discountCtrl.clear();
    maxUsageCtrl.text = "0";

    isPercentage.value = false;
    draftActive.value = true;
    validFrom.value = DateTime.now();
    validTo.value = DateTime.now().add(const Duration(days: 30));
  }

  // ---------------------------------------------------------------------------
  // LOAD COUPON DATA INTO FORM FOR EDITING
  // ---------------------------------------------------------------------------
  void loadForEdit(CouponModel coupon) {
    editDocId.value = coupon.docId;

    codeCtrl.text = coupon.code;
    descCtrl.text = coupon.description;
    discountCtrl.text = coupon.discountValue.toString();
    maxUsageCtrl.text = coupon.maxUsage.toString();

    isPercentage.value = coupon.isPercentage;
    draftActive.value = coupon.isActive;
    validFrom.value = coupon.validFrom;
    validTo.value = coupon.validTo;
  }

  // ---------------------------------------------------------------------------
  // CREATE OR UPDATE COUPON
  // ---------------------------------------------------------------------------
  Future<void> saveCoupon() async {
    if (isSaving.value) return; // re-entry guard (double-click)

    final code = codeCtrl.text.trim();
    final discount = double.tryParse(discountCtrl.text) ?? 0;
    final maxUsage = int.tryParse(maxUsageCtrl.text) ?? 0;

    if (code.isEmpty || discount <= 0) {
      Get.snackbar("Error", "Coupon code & discount are required");
      return;
    }
    if (isPercentage.value && discount > 100) {
      Get.snackbar("Error", "A percentage discount cannot exceed 100%");
      return;
    }
    if (maxUsage < 0) {
      Get.snackbar(
          "Error", "Max redemptions cannot be negative (0 = unlimited)");
      return;
    }
    if (!validTo.value.isAfter(validFrom.value)) {
      Get.snackbar("Error", "Valid To must be after Valid From");
      return;
    }

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) {
      Get.snackbar("Error", "Admin UID missing. Login again.");
      return;
    }

    final now = DateTime.now();

    // 🟢 If editing, use the same document ID
    // 🟢 If creating new, generate Firestore doc id
    final String docId = editDocId.value.isEmpty
        ? _db.collection(collectionName).doc().id
        : editDocId.value;

    // The backend redeems by code lookup — duplicate codes make redemption
    // ambiguous, so reject a code already used by a different coupon.
    final normalizedCode = toCaps(code);
    final duplicate = coupons.any(
      (c) => c.code == normalizedCode && c.docId != docId,
    );
    if (duplicate) {
      Get.snackbar("Error", "A coupon with this code already exists");
      return;
    }

    final isEdit = editDocId.value.isNotEmpty;

    isSaving.value = true;

    try {
      if (isEdit) {
        // EDIT: update() ONLY the founder-editable fields. `usedCount` is
        // server-owned (redeemed at checkout) and `createdAt` is immutable —
        // rewriting them from a stale console snapshot could un-cap a capped
        // coupon or falsify its history, so they are never written here.
        await _db.collection(collectionName).doc(docId).update({
          "code": normalizedCode,
          "type": isPercentage.value ? "percent" : "flat",
          "value": discount,
          "isActive": draftActive.value,
          "description": descCtrl.text.trim(),
          "expiresAt": Timestamp.fromDate(validTo.value),
          "isPercentage": isPercentage.value,
          "discountValue": discount,
          "maxUsage": maxUsage,
          "validFrom": Timestamp.fromDate(validFrom.value),
          "validTo": Timestamp.fromDate(validTo.value),
          "updatedAt": Timestamp.fromDate(now),
        });
      } else {
        final coupon = CouponModel(
          id: docId, // both id & docId use same Firestore ID
          docId: docId,
          uid: adminUid,
          code: normalizedCode,
          description: descCtrl.text.trim(),
          isPercentage: isPercentage.value,
          discountValue: discount,
          maxUsage: maxUsage,
          usedCount: 0,
          isActive: true,
          validFrom: validFrom.value,
          validTo: validTo.value,
          createdAt: now,
          updatedAt: now,
        );
        await _db.collection(collectionName).doc(docId).set(coupon.toMap());
      }

      Get.back();
      Get.snackbar(
        "Success",
        isEdit ? "Coupon Updated" : "Coupon Created",
      );

      clearForm();
    } catch (_) {
      Get.snackbar("Error", "Could not save the coupon. Try again.");
    } finally {
      isSaving.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // TOGGLE ACTIVE STATUS
  // ---------------------------------------------------------------------------
  Future<void> toggleCoupon(String docId, bool currentState) async {
    await _db.collection(collectionName).doc(docId).update({
      "isActive": !currentState,
      "updatedAt": DateTime.now().toIso8601String(),
    });
  }
  String toCaps(String text) {
  return text.toUpperCase();
}


  // ---------------------------------------------------------------------------
  // DELETE COUPON
  // ---------------------------------------------------------------------------
  Future<void> deleteCoupon(String docId) async {
    await _db.collection(collectionName).doc(docId).update({
      "isActive": false,
      "updatedAt": DateTime.now().toIso8601String(),
    });
  }
}
