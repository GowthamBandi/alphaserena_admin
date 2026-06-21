// lib/widgets/trainer_form_dialog.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/trainer_controller.dart';
import '../models/trainer_model.dart';

class TrainerFormDialog extends StatefulWidget {
  final TrainerModel? trainer;

  const TrainerFormDialog({super.key, this.trainer});

  @override
  State<TrainerFormDialog> createState() => _TrainerFormDialogState();
}

class _TrainerFormDialogState extends State<TrainerFormDialog> {
  final ctrl = Get.find<TrainerController>();

  @override
  void initState() {
    super.initState();

    if (widget.trainer == null) {
      ctrl.clearForm();
    } else {
      ctrl.loadTrainerToForm(widget.trainer!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xffF6F8FB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          children: [
            _header(),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _profileSection(),
                    const SizedBox(height: 20),

                    _section("Basic Information", _basicForm()),
                    const SizedBox(height: 16),

                    _section("Assignment & Status", _assignment()),
                    const SizedBox(height: 16),

                    if (widget.trainer != null) _section("Clients", _clients()),

                    if (widget.trainer != null) ...[
                      const SizedBox(height: 16),
                      _section("System Metadata", _meta()),
                    ],
                  ],
                ),
              ),
            ),

            _footerActions(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 🔥 HEADER (STICKY)
  // ============================================================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center),
          const SizedBox(width: 10),
          Text(
            widget.trainer == null ? "Create Trainer" : "Edit Trainer",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 👤 PROFILE (LIVE REACTIVE)
  // ============================================================
  Widget _profileSection() {
    return Obx(() {
      final name = ctrl.nameCtrl.text.isEmpty
          ? "New Trainer"
          : ctrl.nameCtrl.text;

      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: Colors.blue.shade100,
              child: Text(name[0].toUpperCase()),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ctrl.emailCtrl.text.isEmpty
                        ? "No email"
                        : ctrl.emailCtrl.text,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            _statusChip(ctrl.selectedStatusForForm.value),
          ],
        ),
      );
    });
  }

  Widget _statusChip(String status) {
    final color = {
      "active": Colors.green,
      "pending": Colors.orange,
      "blocked": Colors.red,
      "suspended": Colors.grey,
    }[status]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ============================================================
  // 🧱 SECTION
  // ============================================================
  Widget _section(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ============================================================
  // 🧾 BASIC FORM
  // ============================================================
  Widget _basicForm() {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _input("Name", ctrl.nameCtrl),
        _input("Email", ctrl.emailCtrl),
        _input("Phone", ctrl.phoneCtrl),
        _input("Specialization", ctrl.specializationCtrl),
        _input("Experience (yrs)", ctrl.experienceCtrl),
        _input("Bio", ctrl.bioCtrl, full: true, maxLines: 3),
      ],
    );
  }

  // ============================================================
  // ⚙️ ASSIGNMENT
  // ============================================================
  Widget _assignment() {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [_statusDropdown(), _adminDropdown()],
    );
  }

  Widget _statusDropdown() {
    return SizedBox(
      width: 260,
      child: Obx(() {
        return DropdownButtonFormField<String>(
          value: ctrl.selectedStatusForForm.value,
          decoration: _inputDecoration("Status"),
          items: ctrl.allowedStatus
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => ctrl.selectedStatusForForm.value = v!,
        );
      }),
    );
  }

  Widget _adminDropdown() {
    return SizedBox(
      width: 260,
      child: Obx(() {
        final options = ctrl.adminOptions;

        return DropdownButtonFormField<String>(
          value: ctrl.assignedByCtrl.value.isEmpty
              ? null
              : ctrl.assignedByCtrl.value,
          decoration: _inputDecoration("Assign Admin"),
          items: options
              .map(
                (e) => DropdownMenuItem(
                  value: e['uid'],
                  child: Text("${e['name']} • ${e['organization']}"),
                ),
              )
              .toList(),
          onChanged: (v) => ctrl.assignedByCtrl.value = v ?? "",
        );
      }),
    );
  }

  // ============================================================
  // 👥 CLIENTS → CHIP VIEW
  // ============================================================
  Widget _clients() {
    final names = ctrl.getClientNames(widget.trainer!.clientIds);

    if (names.isEmpty) {
      return const Text("No clients assigned");
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: names
          .map(
            (n) => Chip(label: Text(n), backgroundColor: Colors.blue.shade50),
          )
          .toList(),
    );
  }

  // ============================================================
  // 🧠 META
  // ============================================================
  Widget _meta() {
    final t = widget.trainer!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metaRow("Created", t.createdAt),
        _metaRow("Updated", t.updatedAt),
        if (t.lastLogin != null) _metaRow("Last Login", t.lastLogin!),
      ],
    );
  }

  Widget _metaRow(String label, DateTime dt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text("$label: ${dt.toLocal()}".split('.').first),
    );
  }

  // ============================================================
  // 🔘 FOOTER ACTIONS (STICKY)
  // ============================================================
  Widget _footerActions() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Obx(() {
        if (ctrl.isProcessing.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(
                  widget.trainer == null ? "Create Trainer" : "Save Changes",
                ),
              ),
            ),

            if (widget.trainer != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ctrl.deleteTrainer(widget.trainer!.docId);
                    Get.back();
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text("Delete"),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  // ============================================================
  // INPUT
  // ============================================================
  Widget _input(
    String label,
    TextEditingController c, {
    bool full = false,
    int maxLines = 1,
  }) {
    return SizedBox(
      width: full ? double.infinity : 260,
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: _inputDecoration(label),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10),
      ],
    );
  }

  void _submit() {
    if (widget.trainer == null) {
      ctrl.createTrainer();
    } else {
      ctrl.updateTrainer(widget.trainer!.docId);
    }
  }
}
