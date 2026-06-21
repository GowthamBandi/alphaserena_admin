import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class AdminAnalyticsController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final String adminUid;

  AdminAnalyticsController(this.adminUid);

  // ============================================================
  // 🔥 LIVE COUNTS
  // ============================================================
  final RxInt trainers = 0.obs;
  final RxInt clients = 0.obs;
  final RxInt workouts = 0.obs;
  final RxInt dietPlans = 0.obs;

  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _listenAll();
  }

  void _listenAll() async {
    isLoading.value = true;

    /// TRAINERS
    _db
        .collection("trainers")
        .where("assignedBy", isEqualTo: adminUid)
        .snapshots()
        .listen((snap) {
          trainers.value = snap.docs.length;
        });

    /// CLIENTS
    _db
        .collection("clients")
        .where("adminId", isEqualTo: adminUid)
        .snapshots()
        .listen((snap) {
          clients.value = snap.docs.length;
        });

    /// WORKOUTS
    _db
        .collection("workout_plans")
        .where("adminId", isEqualTo: adminUid)
        .snapshots()
        .listen((snap) {
          workouts.value = snap.docs.length;
        });

    /// DIET PLANS
    _db
        .collection("diet_plans")
        .where("adminId", isEqualTo: adminUid)
        .snapshots()
        .listen((snap) {
          dietPlans.value = snap.docs.length;
        });

    isLoading.value = false;
  }
}
