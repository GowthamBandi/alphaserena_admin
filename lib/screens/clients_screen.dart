// lib/screens/clients_screen.dart

import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/client_controller.dart';

class ClientsScreen extends StatelessWidget {
  ClientsScreen({super.key});

  final ctrl = Get.put(ClientController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F6FA),

      appBar: AppBar(
        title: const Text("Client Intelligence"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            _kpiSection(),
            _analyticsRow(),

            /// 🔥 MAIN CONTENT
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: _clientsTable()),
                  Expanded(flex: 1, child: _sidePanel()),
                ],
              ),
            ),
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
          _kpi("Total Clients", ctrl.total, Icons.people, Colors.blue),
          _kpi("Active", ctrl.active, Icons.check_circle, Colors.green),
          _kpi("Inactive", ctrl.inactive, Icons.block, Colors.red),
          _kpi("Verified", ctrl.verified, Icons.verified, Colors.purple),
        ],
      ),
    );
  }

  Widget _kpi(String title, int value, IconData icon, Color color) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600)),
              Text(
                "$value",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
    return Row(
      children: const [
        Expanded(flex: 3, child: Text("Client")),
        Expanded(flex: 2, child: Text("Goal")),
        Expanded(flex: 2, child: Text("Trainer")),
        Expanded(flex: 1, child: Text("Status")),
        Expanded(flex: 1, child: Text("Actions")),
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
          Expanded(flex: 1, child: _actions(c)),
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
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              c.email,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _status(ClientModel c) {
    final color = c.isActive ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        c.isActive ? "ACTIVE" : "INACTIVE",
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _actions(ClientModel c) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == "delete") ctrl.deleteClient(c.docId);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: "edit", child: Text("Edit")),
        PopupMenuItem(
          value: "delete",
          child: Text("Delete", style: TextStyle(color: Colors.red)),
        ),
      ],
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
                  leading: CircleAvatar(child: Text(c.name[0])),
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
        BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10),
      ],
    );
  }
}
