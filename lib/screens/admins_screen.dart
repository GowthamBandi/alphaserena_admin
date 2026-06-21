// lib/screens/admins_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../models/admin_model.dart';
import '../widgets/admin_form_dialog.dart';
import '../widgets/admin_details_dialog.dart';

class AdminsScreen extends StatelessWidget {
  AdminsScreen({super.key});

  final ctrl = Get.find<AdminController>();

  /// 🔥 ENTERPRISE SELECTION STATE
  final RxSet<String> selectedIds = <String>{}.obs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),

      body: Column(
        children: [
          _header(),

          _topBar(),

          Obx(
            () => selectedIds.isNotEmpty ? _bulkActionBar() : const SizedBox(),
          ),

          Expanded(child: Obx(() => _grid())),
        ],
      ),
    );
  }

  // ============================================================
  // 🧠 HEADER (SAAS STYLE)
  // ============================================================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          const Text(
            "Admin Management",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),

          Obx(
            () => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${ctrl.admins.length} admins",
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const Spacer(),

          ElevatedButton.icon(
            onPressed: () {
              ctrl.clearForm();
              Get.dialog(AdminFormDialog());
            },
            icon: const Icon(Icons.add),
            label: const Text("Create Admin"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔍 TOP BAR
  // ============================================================
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => ctrl.search.value = v,
              decoration: InputDecoration(
                hintText: "Search admins...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          Obx(
            () => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButton<String>(
                underline: const SizedBox(),
                value: ctrl.statusFilter.value,
                items: const [
                  DropdownMenuItem(value: "all", child: Text("All")),
                  DropdownMenuItem(value: "active", child: Text("Active")),
                  DropdownMenuItem(value: "pending", child: Text("Pending")),
                  DropdownMenuItem(value: "blocked", child: Text("Blocked")),
                ],
                onChanged: (v) => ctrl.statusFilter.value = v!,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🧠 BULK ACTION BAR
  // ============================================================
  Widget _bulkActionBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text("${selectedIds.length} selected"),

          const SizedBox(width: 20),

          TextButton(
            onPressed: () => _bulkUpdate("active"),
            child: const Text("Approve"),
          ),

          TextButton(
            onPressed: () => _bulkUpdate("blocked"),
            child: const Text("Block"),
          ),

          TextButton(onPressed: _bulkDelete, child: const Text("Delete")),

          const Spacer(),

          IconButton(
            onPressed: () => selectedIds.clear(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🧱 GRID VIEW (MAIN UI)
  // ============================================================
  Widget _grid() {
    if (ctrl.isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = ctrl.filteredAdmins;

    if (list.isEmpty) {
      return const Center(child: Text("No admins found"));
    }

    return LayoutBuilder(
      builder: (_, box) {
        int cross = 1;
        if (box.maxWidth > 1400)
          cross = 4;
        else if (box.maxWidth > 1000)
          cross = 3;
        else if (box.maxWidth > 700)
          cross = 2;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (_, i) => _adminCard(list[i]),
        );
      },
    );
  }

  // ============================================================
  // 💎 ADMIN CARD (CORE UI)
  // ============================================================
  Widget _adminCard(AdminModel a) {
    final selected = selectedIds.contains(a.docId);
    Map<String, dynamic> safeMap(dynamic value) {
      if (value is Map) {
        return value.map((key, val) => MapEntry(key.toString(), val));
      }
      return {};
    }

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    /// ✅ SAFE DATA EXTRACTION
    final limits = safeMap(a.subscriptionLimits);
    final usage = safeMap(limits['usage']);

    final maxTrainers = toInt(limits['maxTrainers']);
    final maxClients = toInt(limits['maxClients']);
    final maxWorkoutPlans = toInt(limits['maxWorkoutPlans']);
    final maxDietPlans = toInt(limits['maxDietPlans']);

    final usedTrainers = toInt(usage['trainers']);
    final usedClients = toInt(usage['clients']);
    final usedWorkouts = toInt(usage['workoutPlans']);
    final usedDiets = toInt(usage['dietPlans']);

    return GestureDetector(
      onTap: () => Get.dialog(AdminDetailsDialog(admin: a)),
      onLongPress: () => _toggleSelection(a.docId),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),

        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          border: selected ? Border.all(color: Colors.blue, width: 2) : null,
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(.06),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ======================================================
            // HEADER
            // ======================================================
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(a.name.isNotEmpty ? a.name[0] : "?"),
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        a.organizationName,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                _statusBadge(a.status),
              ],
            ),

            const SizedBox(height: 14),

            // ======================================================
            // PLAN + EXPIRY
            // ======================================================
            Row(
              children: [
                const Icon(Icons.workspace_premium, size: 16),
                const SizedBox(width: 6),
                Text(
                  a.planName ?? "No Plan",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),

            if (a.planExpiry != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Expires: ${a.planExpiry!.day}/${a.planExpiry!.month}/${a.planExpiry!.year}",
                  style: TextStyle(
                    fontSize: 12,
                    color: _expiryColor(a.planExpiry!),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ======================================================
            // USAGE SECTION
            // ======================================================
            _usageRow("Trainers", usedTrainers, maxTrainers),
            _usageRow("Clients", usedClients, maxClients),
            _usageRow("Workout Plans", usedWorkouts, maxWorkoutPlans),
            _usageRow("Diet Plans", usedDiets, maxDietPlans),

            const Spacer(),

            // ======================================================
            // ACTIONS
            // ======================================================
            Row(
              children: [
                TextButton(
                  onPressed: () => ctrl.updateStatus(a.docId, "active"),
                  child: const Text("Approve"),
                ),
                TextButton(
                  onPressed: () => ctrl.updateStatus(a.docId, "blocked"),
                  child: const Text("Block"),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    ctrl.loadToForm(a);
                    Get.dialog(AdminFormDialog(admin: a));
                  },
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _expiryColor(DateTime date) {
    final diff = date.difference(DateTime.now()).inDays;

    if (diff <= 3) return Colors.red;
    if (diff <= 7) return Colors.orange;
    return Colors.green;
  }

  Widget _usageRow(String label, int used, int max) {
    final double progress = max == 0
        ? 0.0
        : (used / max).clamp(0.0, 1.0).toDouble();

    final color = progress > 0.9
        ? Colors.red
        : progress > 0.7
        ? Colors.orange
        : Colors.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                "$used / $max",
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS BADGE
  // ============================================================
  Widget _statusBadge(String status) {
    final color = {
      "active": Colors.green,
      "pending": Colors.orange,
      "blocked": Colors.red,
    }[status]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // BULK LOGIC
  // ============================================================
  void _toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
  }

  void _bulkUpdate(String status) {
    for (final id in selectedIds) {
      ctrl.updateStatus(id, status);
    }
    selectedIds.clear();
  }

  void _bulkDelete() {
    for (final id in selectedIds) {
      ctrl.deleteAdmin(id);
    }
    selectedIds.clear();
  }
}
