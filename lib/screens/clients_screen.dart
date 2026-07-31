// lib/screens/clients_screen.dart
//
// Founder view = READ-ONLY observer. Members are managed by their gym
// (admin/trainer); the founder watches them platform-wide.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/client_controller.dart';
<<<<<<< HEAD
import '../core/theme/serena/serena_tokens.g.dart';
import '../core/widgets/serena/serena_ui.dart';
=======
import '../widgets/page_shell.dart';

const _cActive = Color(0xFF1A7F5A);
const _cInactive = Color(0xFF9AA0A6);
const _cVerified = Color(0xFF3B6FD4);
>>>>>>> origin/main

class ClientsScreen extends StatelessWidget {
  ClientsScreen({super.key});

  final ClientController ctrl = Get.find<ClientController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Members",
      icon: Icons.people_outline,
      trailing: Obx(() => Text("${ctrl.clients.length} total",
          style: AppText.body(size: 13)
              .copyWith(color: context.palette.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(context),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.isLoading.value && ctrl.clients.isEmpty) {
              return const SizedBox(
                  height: 240,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final list = ctrl.filteredClients;
            if (list.isEmpty) {
              return _empty(context, Icons.people_outline, "No members found",
                  "Members added by gyms appear here.");
            }
            return Column(children: [
              for (final c in list) ...[
                _row(context, c),
                const SizedBox(height: 10),
              ],
            ]);
          }),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: InputDecoration(
            hintText: "Search members by name or email…",
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
              _chip(context, "All", "all", ctrl.total),
              _chip(context, "Active", "active", ctrl.active),
              _chip(context, "Inactive", "inactive", ctrl.inactive),
            ])),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.statusFilter.value == value;
    final accent = value == 'inactive' ? _cInactive : p.accent;
    return InkWell(
      onTap: () => ctrl.statusFilter.value = value,
      borderRadius: AppRadii.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: AppRadii.smR,
          border: Border.all(color: selected ? accent : p.border),
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

  Widget _row(BuildContext context, ClientModel c) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: () => _showDetails(context, c),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Row(children: [
            _avatar(context, c.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(size: 14)
                              .copyWith(color: p.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    _pill(c.isActive ? "Active" : "Inactive",
                        c.isActive ? _cActive : _cInactive),
                    if (c.isVerified) ...[
                      const SizedBox(width: 6),
                      _pill("Verified", _cVerified),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(c.email.isEmpty ? c.phone : c.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.business, size: 13, color: p.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(ctrl.getAdminName(c.adminId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textSecondary)),
                    ),
                    Text("  ·  ",
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                    Icon(Icons.fitness_center, size: 13, color: p.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(ctrl.getTrainerName(c.trainerId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textSecondary)),
                    ),
                  ]),
                ],
              ),
            ),
<<<<<<< HEAD
          ],
        );
      }),
    );
  }

  // ============================================================
  // 🔥 KPI STRIP
  // ============================================================
  Widget _kpiSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _kpi("Total Members", ctrl.total, Icons.people,
              const Color(SerenaColor.infoFillLight)),
          _kpi("Active Membership", ctrl.active, Icons.check_circle,
              const Color(SerenaColor.statusActiveLight)),
          _kpi("With Trainer", ctrl.withTrainer, Icons.fitness_center,
              const Color(SerenaColor.accentPurpleLight)),
          _kpi("Unassigned", ctrl.unassigned, Icons.person_off,
              const Color(SerenaColor.statusPendingLight)),
        ],
=======
          ]),
        ),
>>>>>>> origin/main
      ),
    );
  }

<<<<<<< HEAD
  Widget _kpi(String title, int value, IconData icon, Color color) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Column(
=======
  void _showDetails(BuildContext context, ClientModel c) {
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
>>>>>>> origin/main
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _avatar(context, c.name, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(c.name,
                      style: AppText.title(size: 20)
                          .copyWith(color: p.textPrimary)),
                ),
                _pill(c.isActive ? "Active" : "Inactive",
                    c.isActive ? _cActive : _cInactive),
              ]),
              const SizedBox(height: 20),
              _detail(context, Icons.email_outlined, "Email",
                  c.email.isEmpty ? "—" : c.email),
              _detail(context, Icons.phone_outlined, "Phone",
                  c.phone.isEmpty ? "—" : c.phone),
              _detail(context, Icons.flag_outlined, "Goal",
                  (c.goal ?? '').isEmpty ? "—" : c.goal!),
              _detail(context, Icons.business, "Organization",
                  ctrl.getAdminName(c.adminId)),
              _detail(context, Icons.fitness_center, "Trainer",
                  ctrl.getTrainerName(c.trainerId)),
              _detail(context, Icons.cake_outlined, "Age",
                  c.age == null ? "—" : "${c.age}"),
              _detail(context, Icons.calendar_today_outlined, "Joined",
                  DateFormat('d MMM yyyy').format(c.createdAt)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Get.back(), child: const Text("Close")),
              ),
            ],
          ),
<<<<<<< HEAD
        ],
      ),
    );
  }

  // ============================================================
  // 📊 ANALYTICS ROW
  // ============================================================
  Widget _analyticsRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _growthCard()),
          const SizedBox(width: 16),
          Expanded(child: _segmentationCard()),
        ],
      ),
    );
  }

  Widget _growthCard() {
    return _card(
      "Growth Trend",
      const Center(child: Text("📈 Chart Placeholder")),
      height: 200,
    );
  }

  Widget _segmentationCard() {
    final fatLoss = ctrl.clients.where((c) => c.goal == "Fat Loss").length;
    final muscle = ctrl.clients.where((c) => c.goal == "Muscle Gain").length;

    return _card(
      "Client Goals",
      Column(
        children: [
          _segRow("Fat Loss", fatLoss, Colors.orange),
          _segRow("Muscle Gain", muscle, Colors.blue),
        ],
      ),
      height: 200,
    );
  }

  Widget _segRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 6, backgroundColor: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text("$value"),
        ],
      ),
    );
  }

  // ============================================================
  // 🧾 CLIENT TABLE
  // ============================================================
  Widget _clientsTable() {
    final list = ctrl.filteredClients;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _tableHeader(),
          const Divider(),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("No clients found"))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Row(
      children: const [
        Expanded(flex: 3, child: Text("Client")),
        Expanded(flex: 2, child: Text("Goal")),
        Expanded(flex: 2, child: Text("Trainer")),
        Expanded(flex: 1, child: Text("Status")),
      ],
    );
  }

  Widget _row(ClientModel c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: _clientCell(c)),
          Expanded(flex: 2, child: Text(c.goal ?? "-")),
          Expanded(flex: 2, child: Text(ctrl.getTrainerName(c.trainerId))),
          Expanded(flex: 1, child: _status(c)),
        ],
      ),
    );
  }

  Widget _clientCell(ClientModel c) {
    final letter = c.name.isNotEmpty ? c.name[0].toUpperCase() : "?";

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.blue.shade100,
          child: Text(letter),
=======
>>>>>>> origin/main
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

<<<<<<< HEAD
  Widget _status(ClientModel c) {
    // SDS semantic status pill from the REAL membership state (green active /
    // neutral inactive). Read-only: the founder console cannot write per-org
    // client records (that's trainersHQ's job; the rules deny it).
    return SerenaStatusPill(
      label: c.membershipActive ? "ACTIVE" : "INACTIVE",
      status: c.membershipActive ? SerenaStatus.active : SerenaStatus.neutral,
    );
  }

  // ============================================================
  // ⚡ SIDE PANEL
  // ============================================================
  Widget _sidePanel() {
    return Container(
      margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Clients",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ...ctrl.clients
              .take(6)
              .map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : "?"),
                  ),
                  title: Text(c.name),
                  subtitle: Text(c.goal ?? ""),
                ),
              ),
        ],
      ),
    );
  }

  // ============================================================
  // 🎨 UI HELPERS
  // ============================================================
  Widget _card(String title, Widget child, {double? height}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 10),
      ],
=======
  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: AppText.label(size: 11).copyWith(color: c)),
      );

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
>>>>>>> origin/main
    );
  }
}
