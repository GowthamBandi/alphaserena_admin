import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';
import '../models/trainer_model.dart';

class DashboardController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // KPI observables
  RxInt adminCount = 0.obs;
  RxInt trainerCount = 0.obs;
  RxInt clientCount = 0.obs;
  RxDouble revenue = 0.0.obs;

  // Recent lists
  RxList<AdminModel> pendingAdminRequests = <AdminModel>[].obs;
  RxList<Map<String, dynamic>> recentActivity = <Map<String, dynamic>>[].obs;

  // Loading
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _startListeners();
  }

  void _startListeners() {
    isLoading.value = true;

    // Admins count & pending requests
    _db.collection('admins').snapshots().listen((snap) {
      adminCount.value = snap.size;
      pendingAdminRequests.value = snap.docs
          .where((d) {
            final status = (d.data() as Map<String, dynamic>?)?['status'] ?? '';
            return status.toString().toLowerCase() == 'pending';
          })
          .map((d) => AdminModel.fromSnapshot(d))
          .toList();
    }, onError: (e) {
      isLoading.value = false;
      print('admins listen error: $e');
    });

    // Trainers count
    _db.collection('trainers').snapshots().listen((snap) {
      trainerCount.value = snap.size;
    }, onError: (e) {
      print('trainers listen error: $e');
    });

    // Clients count
    _db.collection('users').snapshots().listen((snap) {
      clientCount.value = snap.size;
    }, onError: (e) {
      print('users listen error: $e');
    });

    // Revenue (sum of subscription amounts). listens real-time and recomputes sum.
    _db.collection('subscriptions').snapshots().listen((snap) {
      double total = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final amt = data['amount'] ??
            data['price'] ?? // fallback
            0;
        if (amt is num) {
          total += amt.toDouble();
        } else if (amt is String) {
          total += double.tryParse(amt) ?? 0.0;
        }
      }
      revenue.value = total;
    }, onError: (e) {
      print('subscriptions listen error: $e');
    });

    // Recent activity: use users ordered by createdAt (newest first)
    _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(6)
        .snapshots()
        .listen((snap) {
      recentActivity.value = snap.docs.map((d) {
        final data = d.data();
        return {
          'type': 'signup',
          'title': data['name'] ?? data['email'] ?? 'User',
          'subtitle': 'Signed up',
          'time': data['createdAt'] ?? DateTime.now(),
        };
      }).toList();
    }, onError: (e) {
      print('users recentActivity listen error: $e');
    });

    // finalize
    isLoading.value = false;
  }

  // Approve / Reject admin request helper
  Future<void> updateAdminStatus(String docId, String newStatus) async {
    await _db.collection('admins').doc(docId).update({
      'status': newStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}
