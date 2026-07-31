// lib/screens/trainers_screen.dart
//
// Founder view = READ-ONLY observer. Trainers are created/managed by their gym
// owner (via the createTrainer Cloud Function), not from the founder console.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/trainer_controller.dart';
import '../core/theme/serena/serena_tokens.g.dart';
import '../core/widgets/serena/serena_ui.dart';
import '../models/trainer_model.dart';
<<<<<<< HEAD
=======
import '../widgets/page_shell.dart';

const _cActive = Color(0xFF1A7F5A);
const _cPending = Color(0xFF3B6FD4);
const _cBlocked = Color(0xFFD4341F);
const _cSuspended = Color(0xFFB06A00);

Color _statusColor(String s) {
  switch (s.toLowerCase()) {
    case 'active':
      return _cActive;
    case 'pending':
      return _cPending;
    case 'blocked':
      return _cBlocked;
    case 'suspended':
      return _cSuspended;
    default:
      return const Color(0xFF9AA0A6);
  }
}
>>>>>>> origin/main

class TrainersScreen extends StatelessWidget {
  TrainersScreen({super.key});

  final TrainerController ctrl = Get.find<TrainerController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Trainers",
      icon: Icons.fitness_center_outlined,
      trailing: Obx(() => Text("${ctrl.trainers.length} total",
          style: AppText.body(size: 13)
              .copyWith(color: context.palette.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
<<<<<<< HEAD
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
                  ],
                  onChanged: (v) => ctrl.selectedStatus.value = v!,
                );
              }),
            ],
          ),
=======
          _toolbar(context),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.isLoading.value && ctrl.trainers.isEmpty) {
              return const SizedBox(
                  height: 240,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final list = ctrl.filteredTrainers;
            if (list.isEmpty) {
              return _empty(context, Icons.fitness_center_outlined,
                  "No trainers found",
                  "Trainers created by gyms appear here.");
            }
            return Column(children: [
              for (final t in list) ...[
                _row(context, t),
                const SizedBox(height: 10),
              ],
            ]);
          }),
>>>>>>> origin/main
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
<<<<<<< HEAD
        _kpi("Total", ctrl.totalCount, const Color(SerenaColor.infoFillLight)),
        _kpi("Active", ctrl.activeCount,
            const Color(SerenaColor.statusActiveLight)),
        _kpi("Inactive", ctrl.inactiveCount,
            const Color(SerenaColor.statusBlockedLight)),
=======
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: InputDecoration(
            hintText: "Search trainers by name or email…",
            prefixIcon: Icon(Icons.search, color: p.textMuted),
            filled: true,
            fillColor: p.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.border)),
          ),
        ),
        const SizedBox(height: 14),
        Obx(() => Wrap(spacing: 10, runSpacing: 10, children: [
              _chip(context, "All", "all", ctrl.totalCount),
              _chip(context, "Active", "active", ctrl.activeCount),
              _chip(context, "Pending", "pending", ctrl.pendingCount),
              _chip(context, "Blocked", "blocked", ctrl.blockedCount),
              _chip(context, "Suspended", "suspended", ctrl.suspendedCount),
            ])),
>>>>>>> origin/main
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.selectedStatus.value == value;
    final accent = value == 'all' ? p.accent : _statusColor(value);
    return InkWell(
      onTap: () => ctrl.selectedStatus.value = value,
      borderRadius: AppRadii.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
<<<<<<< HEAD
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10),
          ],
=======
          color: selected ? accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: AppRadii.smR,
          border: Border.all(color: selected ? accent : p.border),
>>>>>>> origin/main
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: AppText.label(size: 13)
                  .copyWith(color: selected ? accent : p.textSecondary)),
          const SizedBox(width: 6),
          Text("$count",
              style: AppText.label(size: 11)
                  .copyWith(color: selected ? accent : p.textMuted)),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, TrainerModel t) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: () => _showDetails(context, t),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Row(children: [
            _avatar(context, t.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(size: 14)
                              .copyWith(color: p.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(t.status),
                  ]),
                  const SizedBox(height: 3),
                  Text(t.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.business, size: 13, color: p.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(ctrl.getAdminName(t.assignedBy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textSecondary)),
                    ),
                    if ((t.specialization ?? '').isNotEmpty) ...[
                      Text("  ·  ",
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                      Flexible(
                        child: Text(t.specialization!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(size: 12)
                                .copyWith(color: p.textSecondary)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${t.clientIds.length}",
                    style: AppText.label(size: 15)
                        .copyWith(color: p.textPrimary)),
                Text("clients",
                    style:
                        AppText.body(size: 11).copyWith(color: p.textMuted)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, TrainerModel t) {
    final p = context.palette;
    Get.dialog(Dialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _avatar(context, t.name, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(t.name,
                      style: AppText.title(size: 20)
                          .copyWith(color: p.textPrimary)),
                ),
                _statusChip(t.status),
              ]),
              const SizedBox(height: 20),
              _detail(context, Icons.email_outlined, "Email", t.email),
              _detail(context, Icons.phone_outlined, "Phone",
                  t.phone.isEmpty ? "—" : t.phone),
              _detail(context, Icons.business, "Organization",
                  ctrl.getAdminName(t.assignedBy)),
              _detail(context, Icons.star_outline, "Specialization",
                  (t.specialization ?? '').isEmpty ? "—" : t.specialization!),
              _detail(context, Icons.timeline, "Experience",
                  t.experience == null ? "—" : "${t.experience} yrs"),
              _detail(context, Icons.people_outline, "Clients",
                  "${t.clientIds.length}"),
              _detail(context, Icons.calendar_today_outlined, "Joined",
                  DateFormat('d MMM yyyy').format(t.createdAt)),
              if ((t.bio ?? '').isNotEmpty)
                _detail(context, Icons.notes, "Bio", t.bio!),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Get.back(), child: const Text("Close")),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _detail(
      BuildContext context, IconData icon, String label, String value) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: p.textMuted),
        const SizedBox(width: 12),
        SizedBox(
            width: 110,
            child: Text(label,
                style: AppText.body(size: 13).copyWith(color: p.textMuted))),
        Expanded(
          child: SelectableText(value,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
        ),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final c = _statusColor(status);
    final label = status.isEmpty
        ? "unknown"
        : "${status[0].toUpperCase()}${status.substring(1).toLowerCase()}";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: AppText.label(size: 11).copyWith(color: c)),
    );
  }

  Widget _avatar(BuildContext context, String name, {double size = 38}) {
    final p = context.palette;
    final letter = name.trim().isEmpty ? "?" : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(letter,
          style: AppText.label(size: size * 0.4).copyWith(color: p.accent)),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String sub) {
    final p = context.palette;
    return Container(
      width: double.infinity,
<<<<<<< HEAD
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              t.email,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
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
    };
    return SerenaStatusPill(
      label: status.toUpperCase(),
      status: map[status] ?? SerenaStatus.neutral,
    );
  }

=======
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(icon, size: 40, color: p.textMuted.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text(title,
            style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
        const SizedBox(height: 4),
        Text(sub, style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      ]),
    );
  }
>>>>>>> origin/main
}
