// lib/widgets/trainer_form_dialog.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/trainer_controller.dart';
import '../models/trainer_model.dart';

class TrainerFormDialog extends StatelessWidget {
  final TrainerModel? trainer;

  TrainerFormDialog({super.key, this.trainer});

  final trainerCtrl = Get.find<TrainerController>();

  @override
  Widget build(BuildContext context) {
    // Load or clear form values
    if (trainer == null) {
      trainerCtrl.clearForm();
    } else {
      trainerCtrl.loadTrainerToForm(trainer!);
    }

    return Dialog(backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _header(),
                const SizedBox(height: 12),
                _topRow(),
                const SizedBox(height: 16),
                _formGrid(),
                const SizedBox(height: 16),
                if (trainer != null) _clientsCard(),
                const SizedBox(height: 12),
                if (trainer != null) _metaCard(),
                const SizedBox(height: 16),
                _actionsRow(),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Get.back(), child: const Text("Cancel")),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Header with title & close
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            trainer == null ? "Create Trainer" : "Edit Trainer",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close))
      ],
    );
  }

  // Top row: profile pic + name/email + status chip
  Widget _topRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _profilePic(),
        const SizedBox(width: 16),
        Expanded(child: _nameEmailBlock()),
        const SizedBox(width: 12),
        Obx(() => _statusChip(trainerCtrl.selectedStatusForForm.value)),
      ],
    );
  }

  Widget _profilePic() {
    final url = trainer?.profilePicUrl ?? "";
    final hasUrl = url.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        height: 96,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => _fallbackAvatar(),
              )
            : _fallbackAvatar(),
      ),
    );
  }

  Widget _fallbackAvatar() {
    final letter = (trainer?.name.isNotEmpty == true) ? trainer!.name[0].toUpperCase() : "?";
    return Container(
      color: Colors.blue.shade50,
      child: Center(
        child: Text(letter, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _nameEmailBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(trainer?.name.isNotEmpty ?? trainerCtrl.nameCtrl.text.isNotEmpty ? trainerCtrl.nameCtrl.text : "New Trainer",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(trainer?.email ?? trainerCtrl.emailCtrl.text, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Obx(() {
          final assignedUid = trainerCtrl.assignedByCtrl.value;
          if (assignedUid.isEmpty) return const Text("Unassigned", style: TextStyle(color: Colors.grey));
          final admin = trainerCtrl.adminCache[assignedUid];
          if (admin == null) return Text("Assigned: $assignedUid", style: const TextStyle(color: Colors.grey));
          return Text("Assigned: ${admin['name']} — ${admin['organization']}", style: const TextStyle(color: Colors.grey));
        }),
      ],
    );
  }

  Widget _statusChip(String status) {
    final color = {
      "pending": Colors.orange,
      "active": Colors.green,
      "blocked": Colors.red,
      "suspended": Colors.grey,
    }[status] ?? Colors.blueGrey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }

  // Responsive form grid
  Widget _formGrid() {
    return LayoutBuilder(builder: (context, box) {
      final isWide = box.maxWidth > 720;
      final colWidth = isWide ? (box.maxWidth - 48) / 2 : double.infinity;

      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _input("Name", trainerCtrl.nameCtrl, width: colWidth),
          _input("Email", trainerCtrl.emailCtrl, width: colWidth),
          _input("Phone", trainerCtrl.phoneCtrl, width: colWidth),
          _input("Specialization", trainerCtrl.specializationCtrl, width: colWidth),
          _input("Experience (yrs)", trainerCtrl.experienceCtrl, width: colWidth),
          _statusDropdown(width: colWidth),
          _assignedAdminDropdown(width: colWidth),
          SizedBox(
            width: isWide ? box.maxWidth : double.infinity,
            child: TextField(
              controller: trainerCtrl.bioCtrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: "Bio", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      );
    });
  }

  Widget _input(String label, TextEditingController ctrl, {double? width}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
      ),
    );
  }

  Widget _statusDropdown({double? width}) {
    return SizedBox(
      width: width,
      child: Obx(() {
        final items = trainerCtrl.allowedStatuses;
        final selected = items.contains(trainerCtrl.selectedStatusForForm.value)
            ? trainerCtrl.selectedStatusForForm.value
            : items.first;
        return InputDecorator(
          decoration: InputDecoration(labelText: "Status", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              items: items.map((s) => DropdownMenuItem(value: s, child: Text(s.capitalize!))).toList(),
              onChanged: (v) => trainerCtrl.selectedStatusForForm.value = v ?? items.first,
            ),
          ),
        );
      }),
    );
  }

  Widget _assignedAdminDropdown({double? width}) {
    return SizedBox(
      width: width,
      child: Obx(() {
        final opts = trainerCtrl.adminOptions;
        final entries = [
          {'uid': '', 'label': 'Unassigned'},
          ...opts.map((a) => {'uid': a['uid']!, 'label': "${a['name']} — ${a['organization']}"}),
        ];
        // ensure current present
        final current = trainerCtrl.assignedByCtrl.value;
        if (current.isNotEmpty && entries.every((e) => e['uid'] != current)) {
          entries.add({'uid': current, 'label': current});
          trainerCtrl.fetchAdminsFor([current]);
        }

        final selected = entries.firstWhere((e) => e['uid'] == trainerCtrl.assignedByCtrl.value, orElse: () => entries.first)['uid']!;
        return InputDecorator(
          decoration: InputDecoration(labelText: "Assigned Admin", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              items: entries.map((e) => DropdownMenuItem(value: e['uid'], child: Text(e['label']!))).toList(),
              onChanged: (v) => trainerCtrl.assignedByCtrl.value = v ?? '',
            ),
          ),
        );
      }),
    );
  }

  // Clients card (shows count and names)
  Widget _clientsCard() {
    final clientIds = trainer!.clientIds;
    final clientNames = trainerCtrl.getClientNames(clientIds);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Text("Clients", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text("(${clientIds.length})", style: const TextStyle(color: Colors.grey)),
            const Spacer(),
            if (clientIds.isNotEmpty)
              TextButton(
                onPressed: () => trainerCtrl.fetchClients(clientIds),
                child: const Text("Refresh"),
              )
          ],
        ),
        const SizedBox(height: 8),
        if (clientIds.isEmpty)
          const Text("No clients assigned", style: TextStyle(color: Colors.grey))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: clientNames.map((n) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(child: Text(n)),
                ],
              ),
            )).toList(),
          ),
      ]),
    );
  }

  // Meta info card
  Widget _metaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Metadata", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _metaRow(Icons.calendar_today, "Created", trainer!.createdAt),
        const SizedBox(height: 6),
        _metaRow(Icons.update, "Updated", trainer!.updatedAt),
        if (trainer!.lastLogin != null) ...[
          const SizedBox(height: 6),
          _metaRow(Icons.login, "Last Login", trainer!.lastLogin!),
        ]
      ]),
    );
  }

  Widget _metaRow(IconData icon, String label, DateTime d) {
    return Row(children: [Icon(icon, size: 14), const SizedBox(width: 8), Text("$label: ${d.toLocal()}".split('.').first)]);
  }

  // Actions row (save/create/delete)
  Widget _actionsRow() {
    return Obx(() {
      if (trainerCtrl.isProcessing.value) {
        return const Center(child: CircularProgressIndicator());
      }

      return Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _submit,
            child: Text(trainer == null ? "Create Trainer" : "Save Changes"),
          ),
        ),
        if (trainer != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                trainerCtrl.deleteTrainer(trainer!.docId);
                Get.back();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Delete"),
            ),
          ),
        ]
      ]);
    });
  }

  void _submit() {
    if (trainer == null) {
      trainerCtrl.createTrainer();
    } else {
      trainerCtrl.updateTrainer(trainer!.docId);
    }
  }
}
