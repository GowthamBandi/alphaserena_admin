import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/dashboard_controller.dart';

class AdminApprovalWidget extends StatelessWidget {
  final DashboardController ctrl;

  const AdminApprovalWidget({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Pending Admin Requests",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 14),

          Obx(() {
            if (ctrl.pendingAdminRequests.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("No pending requests"),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ctrl.pendingAdminRequests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final admin = ctrl.pendingAdminRequests[i];
                return _AdminCard(admin: admin, ctrl: ctrl);
              },
            );
          }),
        ],
      ),
    );
  }

  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10),
      ],
    );
  }
}

// ============================================================
// 🔥 INDIVIDUAL ADMIN CARD
// ============================================================

class _AdminCard extends StatefulWidget {
  final dynamic admin;
  final DashboardController ctrl;

  const _AdminCard({required this.admin, required this.ctrl});

  @override
  State<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<_AdminCard> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.admin;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // 👤 Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.deepPurple.shade100,
            child: Text(
              (a.name ?? "A")[0].toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 📄 Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name ?? "Admin",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  a.email ?? "",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // ⚡ Actions
          isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  children: [
                    _actionBtn(
                      label: "Reject",
                      color: Colors.grey,
                      onTap: _reject,
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      label: "Approve",
                      color: Colors.green,
                      onTap: _approve,
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _approve() async {
    setState(() => isLoading = true);

    await widget.ctrl.updateAdminStatus(widget.admin.docId, "active");

    setState(() => isLoading = false);
  }

  Future<void> _reject() async {
    setState(() => isLoading = true);

    await widget.ctrl.updateAdminStatus(widget.admin.docId, "blocked");

    setState(() => isLoading = false);
  }
}
