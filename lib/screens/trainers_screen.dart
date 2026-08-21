// lib/screens/trainers_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/trainer_controller.dart';
import '../core/theme/serena/serena_tokens.g.dart';
import '../core/widgets/serena/serena_ui.dart';
import '../models/trainer_model.dart';
import '../core/widgets/console/console_chrome.dart';

class TrainersScreen extends StatelessWidget {
  TrainersScreen({super.key});

  final ctrl = Get.put(TrainerController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F6FA),

      body: Column(
        children: [
          _header(),

          /// 🔥 SAFE EXPANDED (NO FLEX ERROR)
          Expanded(
            child: Obx(() {
              final err = ctrl.loadError.value;
              if (err != null) {
                return ConsoleErrorState(error: err, onRetry: ctrl.retryLoad);
              }
              if (ctrl.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final list = ctrl.filteredTrainers;

              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),

                  child: Column(
                    children: [
                      _kpis(),
                      const SizedBox(height: 20),

                      /// 🔥 TABLE AREA (SCROLL SAFE)
                      Expanded(child: _table(list)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 HEADER (PRO LEVEL)
  // ============================================================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                "Trainers",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Read-only cross-org oversight. Trainers are created/managed per
              // org in trainersHQ (createTrainer/setTrainerStatus CFs); the
              // shared rules deny founder writes to `trainers`.
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => ctrl.search.value = v,
                  decoration: InputDecoration(
                    hintText: "Search trainers...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xffF1F3F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Obx(() {
                return DropdownButton<String>(
                  value: ctrl.selectedStatus.value,
                  items: const [
                    DropdownMenuItem(value: "all", child: Text("All")),
                    DropdownMenuItem(value: "active", child: Text("Active")),
                    DropdownMenuItem(value: "inactive", child: Text("Inactive")),
                    // T-2: reachable only here. "All" means all SEATS, so a
                    // soft-deleted document is not silently mixed into it.
                    DropdownMenuItem(value: "removed", child: Text("Removed")),
                  ],
                  onChanged: (v) => ctrl.selectedStatus.value = v!,
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📊 KPI STRIP
  // ============================================================
  Widget _kpis() {
    return Row(
      children: [
        _kpi("Total", ctrl.totalCount, const Color(SerenaColor.infoFillLight)),
        _kpi("Active", ctrl.activeCount,
            const Color(SerenaColor.statusActiveLight)),
        _kpi("Inactive", ctrl.inactiveCount,
            const Color(SerenaColor.statusBlockedLight)),
        // T-2: soft-deleted documents get their own number. Folded into
        // Inactive they made "Inactive" mean two different things, and made
        // Total disagree with the organization's real seat usage.
        _kpi("Removed", ctrl.removedCount,
            const Color(SerenaColor.textMutedLight)),
      ],
    );
  }

  Widget _kpi(String title, int value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Text(
              "$value",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 📋 TABLE (ENTERPRISE GRID STYLE)
  // ============================================================
  Widget _table(List<TrainerModel> list) {
    if (list.isEmpty) {
      return const Center(child: Text("No trainers found"));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10),
        ],
      ),

      child: Column(
        children: [
          /// HEADER ROW
          _tableHeader(),

          const Divider(height: 1),

          /// DATA
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => _row(list[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text("Trainer")),
          Expanded(flex: 2, child: Text("Phone")),
          Expanded(flex: 1, child: Text("Clients")),
          Expanded(flex: 2, child: Text("Admin")),
          Expanded(flex: 1, child: Text("Status")),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _row(TrainerModel t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 3, child: _trainerCell(t)),
          Expanded(flex: 2, child: Text(t.phone)),
          Expanded(flex: 1, child: Text("${t.clientIds.length}")),
          Expanded(flex: 2, child: Text(ctrl.getAdminName(t.assignedBy))),
          Expanded(flex: 1, child: _statusChip(t.status)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(String name) {
    return Container(
      color: Colors.blue.shade100,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  // ============================================================
  // 👤 TRAINER CELL (IMAGE SAFE)
  // ============================================================
  Widget _trainerCell(TrainerModel t) {
    final url = ctrl.fixStorageUrl(t.profilePicUrl);

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.blue.shade100,
          child: ClipOval(
            child: url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,

                    /// 🔥 LOADING
                    placeholder: (context, _) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),

                    /// 🔥 ERROR (IMPORTANT)
                    errorWidget: (context, _, _) => _fallbackAvatar(t.name),
                  )
                : _fallbackAvatar(t.name),
          ),
        ),
        const SizedBox(width: 12),
        // Expanded + ellipsis: this Column was an UNCONSTRAINED child of a Row,
        // so it took its intrinsic width. A long email is unbreakable, so it
        // overflowed the flex-3 cell and painted the yellow-and-black stripes
        // over the row — guaranteed, not theoretical, at narrow widths.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                t.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // STATUS
  // ============================================================
  Widget _statusChip(String status) {
    // M4: SDS semantic status (green active / amber pending / red blocked /
    // neutral suspended) replaces hardcoded Material colors. The `?? neutral`
    // also removes the prior force-unwrap crash on an unmapped status.
    const map = {
      "active": SerenaStatus.active,
      "pending": SerenaStatus.pending,
      "blocked": SerenaStatus.blocked,
      "suspended": SerenaStatus.neutral,
      // Previously unmapped, so a REMOVED trainer fell through to `?? neutral`
      // and rendered identically to a suspended one.
      "removed": SerenaStatus.neutral,
    };
    return SerenaStatusPill(
      label: status.toUpperCase(),
      status: map[status] ?? SerenaStatus.neutral,
    );
  }

}
