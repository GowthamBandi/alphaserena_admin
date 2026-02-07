import 'package:alphaserena_admin_portel/widgets/admin_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../models/admin_model.dart';
import '../widgets/page_shell.dart';

class AdminsScreen extends StatelessWidget {
  AdminsScreen({super.key});

  final adminCtrl = Get.put(AdminController());

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageShell(
          title: "Admins",
          icon: Icons.admin_panel_settings_outlined,
          // actions: [
          //   // Desktop CREATE button
          //   ElevatedButton.icon(
          //     onPressed: () {
          //       showDialog(
          //         context: context,
          //         builder: (_) => AdminFormDialog(),
          //       );
          //     },
          //     icon: const Icon(Icons.add),
          //     label: const Text("Create Admin"),
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: Colors.blue,
          //       foregroundColor: Colors.white,
          //     ),
          //   ),
          //   const SizedBox(width: 20),
          // ],
          child: _buildBody(),
        ),

        // // Floating + button for MOBILE
        // Positioned(
        //   right: 20,
        //   bottom: 20,
        //   child: FloatingActionButton(
        //     backgroundColor: Colors.blue,
        //     child: const Icon(Icons.add),
        //     onPressed: () {
        //       showDialog(
        //         context: Get.context!,
        //         builder: (_) => AdminFormDialog(),
        //       );
        //     },
        //   ),
        // ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // MAIN BODY
  // --------------------------------------------------------------------------
  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(),
        const SizedBox(height: 20),
        _buildContent(),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SEARCH + FILTER BAR
  // --------------------------------------------------------------------------
  Widget _buildTopBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => adminCtrl.search.value = v,
            decoration: InputDecoration(
              hintText: "Search admin by name, email, organization...",
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
        Obx(() {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: adminCtrl.selectedStatus.value,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: "all", child: Text("All")),
                DropdownMenuItem(value: "active", child: Text("Active")),
                DropdownMenuItem(value: "pending", child: Text("Pending")),
                DropdownMenuItem(value: "blocked", child: Text("Blocked")),
              ],
              onChanged: (v) => adminCtrl.selectedStatus.value = v!,
            ),
          );
        }),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // CONTENT
  // --------------------------------------------------------------------------
  Widget _buildContent() {
    return Obx(() {
      if (adminCtrl.isLoading.value) {
        return const Padding(
          padding: EdgeInsets.only(top: 100),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      final admins = adminCtrl.filteredAdmins;

      if (admins.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: Text("No admins found", style: TextStyle(color: Colors.grey))),
        );
      }

      return LayoutBuilder(
        builder: (context, box) {
          return box.maxWidth > 800
              ? _buildTableView(admins)
              : _buildMobileCardView(admins);
        },
      );
    });
  }

  // --------------------------------------------------------------------------
  // TABLE VIEW (DESKTOP)
  // --------------------------------------------------------------------------
  Widget _buildTableView(List<AdminModel> admins) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columns: const [
            DataColumn(label: Text("Name")),
            DataColumn(label: Text("Email")),
            DataColumn(label: Text("Organization")),
            DataColumn(label: Text("Status")),
            DataColumn(label: Text("Plan")),
            DataColumn(label: Text("Actions")),
          ],
          rows: admins.map(_dataRow).toList(),
        ),
      ),
    );
  }

  DataRow _dataRow(AdminModel admin) {
    return DataRow(cells: [
      DataCell(Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.blue.shade100,
          child: Text(admin.name[0].toUpperCase()),
        ),
        const SizedBox(width: 10),
        Text(admin.name),
      ])),
      DataCell(Text(admin.email)),
      DataCell(Text(admin.organizationName)),
      DataCell(_statusBadge(admin.status)),
      DataCell(Text(admin.planName ?? "—")),
      DataCell(_tableActions(admin)),
    ]);
  }

  // --------------------------------------------------------------------------
  // MOBILE LIST CARD VIEW
  // --------------------------------------------------------------------------
  Widget _buildMobileCardView(List<AdminModel> admins) {
    return Column(
      children: admins.map((admin) => _adminCard(admin)).toList(),
    );
  }

  Widget _adminCard(AdminModel admin) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.blue.shade100,
                child: Text(admin.name[0].toUpperCase()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(admin.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _handleMobileAction(v, admin),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: "edit", child: Text("Edit")),
                  PopupMenuItem(value: "delete", child: Text("Delete")),
                ],
              )
            ],
          ),
          const SizedBox(height: 6),
          Text(admin.email),
          Text(admin.organizationName),
          const SizedBox(height: 8),
          _statusBadge(admin.status),
          const SizedBox(height: 4),
          Text("Plan: ${admin.planName ?? 'No Plan'}"),
        ],
      ),
    );
  }

  void _handleMobileAction(String value, AdminModel admin) {
    if (value == "edit") {
      showDialog(
        context: Get.context!,
        builder: (_) => AdminFormDialog(admin: admin),
      );
    } else if (value == "delete") {
      adminCtrl.deleteAdmin(admin.docId);
    }
  }

  // --------------------------------------------------------------------------
  // UTILITIES
  // --------------------------------------------------------------------------
  Widget _tableActions(AdminModel admin) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == "edit") {
          showDialog(
            context: Get.context!,
            builder: (_) => AdminFormDialog(admin: admin),
          );
        } else if (v == "delete") {
          adminCtrl.deleteAdmin(admin.docId);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: "edit", child: Text("Edit")),
        PopupMenuItem(value: "delete", child: Text("Delete")),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color c = {
      "active": Colors.green,
      "pending": Colors.orange,
      "blocked": Colors.red,
    }[status] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(color: c, fontWeight: FontWeight.bold)),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 12),
      ],
    );
  }
}
