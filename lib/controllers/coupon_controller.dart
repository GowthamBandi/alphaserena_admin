// lib/controllers/coupon_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/coupon_model.dart';

class CouponController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // STATES
  RxBool isLoading = false.obs;
  RxBool isSaving = false.obs;

  // LIST OF COUPONS
  RxList<CouponModel> coupons = <CouponModel>[].obs;

  // SEARCH FIELD
  RxString searchQuery = "".obs;

  // FORM CONTROLLERS
  final codeCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final discountCtrl = TextEditingController();
  final maxUsageCtrl = TextEditingController(text: "1");

  RxBool isPercentage = false.obs;
  Rx<DateTime> validFrom = DateTime.now().obs;
  Rx<DateTime> validTo = DateTime.now().add(const Duration(days: 30)).obs;

  // TRACK WHICH DOCUMENT IS BEING EDITED
  RxString editDocId = "".obs;

  // FIRESTORE COLLECTION NAME — canonical, shared with trainersHQ (previewCoupon CF)
  // and allowed by the security rules (super-admin read/write).
  final String collectionName = "coupon_codes";

  @override
  void onInit() {
    super.onInit();
    fetchCoupons();
  }

  // ---------------------------------------------------------------------------
  // REAL-TIME FETCH COUPONS
  // ---------------------------------------------------------------------------
  void fetchCoupons() {
    isLoading.value = true;

    _db.collection(collectionName)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .listen((snapshot) {
      coupons.value = snapshot.docs
          .map((d) => CouponModel.fromMap(d.id, d.data()))
          .toList();

      isLoading.value = false;
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
    maxUsageCtrl.text = "1";

    isPercentage.value = false;
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
    validFrom.value = coupon.validFrom;
    validTo.value = coupon.validTo;
  }

  // ---------------------------------------------------------------------------
  // CREATE OR UPDATE COUPON
  // ---------------------------------------------------------------------------
  Future<void> saveCoupon() async {
    final code = codeCtrl.text.trim();
    final discount = double.tryParse(discountCtrl.text) ?? 0;
    final maxUsage = int.tryParse(maxUsageCtrl.text) ?? 1;

    if (code.isEmpty || discount <= 0) {
      Get.snackbar("Error", "Coupon code & discount are required");
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

    final coupon = CouponModel(
      id: docId,          // both id & docId use same Firestore ID
      docId: docId,
      uid: adminUid,
      code: toCaps(code),
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

    isSaving.value = true;

    try {
      await _db.collection(collectionName).doc(docId).set(coupon.toMap());

      Get.back();
      Get.snackbar(
        "Success",
        editDocId.value.isEmpty ? "Coupon Created" : "Coupon Updated",
      );

      clearForm();
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
