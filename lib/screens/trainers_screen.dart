import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/trainer_controller.dart';
import '../../models/trainer_model.dart';
import '../../widgets/trainer_form_dialog.dart';
import '../../widgets/page_shell.dart';

class TrainersScreen extends StatelessWidget {
  TrainersScreen({super.key});

  final trainerCtrl = Get.put(TrainerController());

  // -------------------------------------------------------------------------
  // 🔥 FIX FIREBASE STORAGE URL FOR WEB
  // -------------------------------------------------------------------------
  String fixStorageUrl(String? url) {
    if (url == null || url.isEmpty) return "";
    if (url.contains("firebasestorage.googleapis.com")) return url;
    return url.replaceAll("firebasestorage.app", "firebasestorage.googleapis.com");
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Trainers",
      icon: Icons.fitness_center_outlined,
      child: _body(),
    );
  }

  // -------------------------------------------------------------------------
  // MAIN BODY
  // -------------------------------------------------------------------------
  Widget _body() {
    return Obx(() {
      if (trainerCtrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final trainers = trainerCtrl.filteredTrainers;
      if (trainers.isEmpty) {
        return const Center(child: Text("No trainers found"));
      }

      return Column(
        children: [
          _topBar(),
          const SizedBox(height: 20),
          _trainerGrid(trainers),
        ],
      );
    });
  }

  // -------------------------------------------------------------------------
  // TOP BAR
  // -------------------------------------------------------------------------
  Widget _topBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => trainerCtrl.search.value = v,
            decoration: InputDecoration(
              hintText: "Search trainer...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // STATUS FILTER
        Obx(
          () => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              underline: const SizedBox(),
              value: trainerCtrl.selectedStatus.value,
              items: const [
                DropdownMenuItem(value: "all", child: Text("All")),
                DropdownMenuItem(value: "pending", child: Text("Pending")),
                DropdownMenuItem(value: "active", child: Text("Active")),
                DropdownMenuItem(value: "blocked", child: Text("Blocked")),
                DropdownMenuItem(value: "suspended", child: Text("Suspended")),
              ],
              onChanged: (v) => trainerCtrl.selectedStatus.value = v!,
            ),
          ),
        )
      ],
    );
  }

  // -------------------------------------------------------------------------
  // GRID VIEW
  // -------------------------------------------------------------------------
  Widget _trainerGrid(List<TrainerModel> trainers) {
    return LayoutBuilder(
      builder: (context, box) {
        int cross = 1;
        if (box.maxWidth > 1300) cross = 5;
        else if (box.maxWidth > 1000) cross = 4;
        else if (box.maxWidth > 700) cross = 2;

        return GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            childAspectRatio: 0.85, 
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
          ),
          itemCount: trainers.length,
          itemBuilder: (_, i) => _trainerCard(trainers[i]),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // CORPORATE CARD (NEW UI)
  // -------------------------------------------------------------------------
  Widget _trainerCard(TrainerModel t) {
    final admin = trainerCtrl.adminCache[t.assignedBy] ?? {};
    final adminName = admin["name"] ?? "Unassigned";
    final adminOrg = admin["organization"] ?? "";

    final imgUrl = fixStorageUrl(t.profilePicUrl);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff121417),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black.withOpacity(0.25),
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          // --------------------------------------------------------------
          // TOP LEFT: STATUS BADGE
          // --------------------------------------------------------------
          Positioned(
            left: 14,
            top: 14,
            child: _statusBadge(t.status),
          ),

          // --------------------------------------------------------------
          // TOP RIGHT: MORE MENU
          // --------------------------------------------------------------
          Positioned(
            right: 6,
            top: 6,
            child: _actionMenu(t),
          ),

          // --------------------------------------------------------------
          // MAIN CONTENT
          // --------------------------------------------------------------
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ------- Profile Picture -------
                  ClipRRect(
                    borderRadius: BorderRadius.circular(60),
                    child: SizedBox(
                      height: 90,
                      width: 90,
                      child: imgUrl.isEmpty
                          ? _fallbackAvatar(t.name)
                          : CachedNetworkImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _fallbackAvatar(t.name),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ------- Name -------
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontSize: 19,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ------- Specialization -------
                  Text(
                    t.specialization ?? "Trainer",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ------- Info Lines -------
                  _infoLine(Icons.email_outlined, t.email),
                  _infoLine(Icons.phone, t.phone),
                  _infoLine(Icons.admin_panel_settings,
                      adminName == "Unassigned" ? "Not Assigned" : "$adminName — $adminOrg"),
                  _infoLine(Icons.group, "${t.clientIds.length} Clients"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FALLBACK AVATAR
  // -------------------------------------------------------------------------
  Widget _fallbackAvatar(String name) {
    return Container(
      color: Colors.grey.shade800,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : "?",
          style: const TextStyle(fontSize: 32, color: Colors.white),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // TOP-RIGHT MENU
  // -------------------------------------------------------------------------
  Widget _actionMenu(TrainerModel t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      color: Colors.white,
      onSelected: (v) {
        if (v == "edit") {
          showDialog(
            context: Get.context!,
            builder: (_) => TrainerFormDialog(trainer: t),
          );
        } else if (v == "delete") {
          trainerCtrl.deleteTrainer(t.docId);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: "edit", child: Text("Edit")),
        PopupMenuItem(
            value: "delete",
            child: Text("Delete", style: TextStyle(color: Colors.red))),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // INFO ROW
  // -------------------------------------------------------------------------
  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // STATUS BADGE (TOP LEFT)
  // -------------------------------------------------------------------------
  Widget _statusBadge(String status) {
    final color = {
      "pending": Colors.orange,
      "active": Colors.green,
      "blocked": Colors.red,
      "suspended": Colors.grey,
    }[status]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.25),
        borderRadius: BorderRadius.circular(14),
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
}
