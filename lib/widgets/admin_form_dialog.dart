// lib/widgets/admin_form_dialog.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../models/admin_model.dart';
import '../models/subscription_model.dart';

class AdminFormDialog extends StatelessWidget {
  final AdminModel? admin; // null = create

  AdminFormDialog({super.key, this.admin});

  final adminCtrl = Get.find<AdminController>();

  @override
  Widget build(BuildContext context) {
    admin == null ? adminCtrl.clearForm() : adminCtrl.loadAdminToForm(admin!);

    return Dialog(backgroundColor: Colors.blue.shade100,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _header(),
                const SizedBox(height: 20),

                _sectionTitle("Admin Details"),
                _detailsSection(),

                const SizedBox(height: 24),

                _sectionTitle("Account Settings"),
                _accountSection(),

                if (admin != null) ...[
                  const SizedBox(height: 24),
                  _sectionTitle("Subscription Details"),
                  _subscriptionSection(admin!),
                ],

                const SizedBox(height: 26),
                _actionButtons(),
                const SizedBox(height: 12),

                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text("Cancel"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------
  Widget _header() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          admin == null ? "Create Admin" : "Edit Admin",
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),IconButton(onPressed: (){Get.back();}, icon: Icon(Icons.close))
      ],
    );
  }

  // ---------------------------------------------------------------
  // SECTION TITLE
  // ---------------------------------------------------------------
  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // DETAILS SECTION
  // ---------------------------------------------------------------
  Widget _detailsSection() {
    return _card(
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _input("Name", adminCtrl.nameCtrl, 260),
          _input("Email", adminCtrl.emailCtrl, 260),
          _input("Phone", adminCtrl.phoneCtrl, 260),
          _input("Organization", adminCtrl.orgCtrl, 260),
          _input("Address", adminCtrl.addressCtrl, double.infinity),
          _input("GST Number", adminCtrl.gstCtrl, 260),
          _input("PAN Number", adminCtrl.panCtrl, 260),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // ACCOUNT SECTION
  // ---------------------------------------------------------------
  Widget _accountSection() {
    return _card(
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _dropdown(
            "Role",
            adminCtrl.selectedRole,
            adminCtrl.allowedRoles,
            width: 260,
          ),
          _dropdown(
            "Status",
            adminCtrl.selectedStatus,
            adminCtrl.allowedStatus,
            width: 260,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // SUBSCRIPTION SECTION (READ-ONLY)
  // ---------------------------------------------------------------
  Widget _subscriptionSection(AdminModel admin) {
    final subMap = admin.subscription;

    if (subMap == null) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text("No active subscription"),
        ),
      );
    }

    final sub = SubscriptionModel.fromMap("x", subMap);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subRow("Plan", sub.planName),
          _subRow("Started At", sub.startAt.toString().split(" ").first),
          _subRow("Expires On", sub.expiryAt.toString().split(" ").first),
          const Divider(height: 24),

          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _limitChip("Admins", sub.maxAdmins),
              _limitChip("Trainers", sub.maxTrainers),
              _limitChip("Clients", sub.maxClients),
              _limitChip("Workout Plans", sub.maxWorkoutPlans),
              _limitChip("Diet Plans", sub.maxDietPlans),
            ],
          ),
        ],
      ),
    );
  }

  // TEXT + VALUE ROW
  Widget _subRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value),
        ],
      ),
    );
  }

  // COOL SUBSCRIPTION LIMIT CHIP
  Widget _limitChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(value.toString(), style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // ACTION BUTTONS (Create / Save / Delete)
  // ---------------------------------------------------------------
  Widget _actionButtons() {
    return Obx(() {
      if (adminCtrl.isProcessing.value) {
        return const CircularProgressIndicator();
      }

      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _submit,
              child: Text(admin == null ? "Create" : "Save"),
            ),
          ),
          if (admin != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  adminCtrl.deleteAdmin(admin!.docId);
                  Get.back();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Delete"),
              ),
            ),
          ]
        ],
      );
    });
  }

  // ---------------------------------------------------------------
  // INPUT FIELD
  // ---------------------------------------------------------------
  Widget _input(String label, TextEditingController ctrl, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // DROPDOWN FIELD
  // ---------------------------------------------------------------
  Widget _dropdown(
      String label, RxString selected, List<String> items,
      {double? width}) {
    return SizedBox(
      width: width,
      child: Obx(() {
        final value = items.contains(selected.value)
            ? selected.value
            : items.first;

        return InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
              onChanged: (v) => selected.value = v!,
            ),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------
  void _submit() {
    admin == null ? _createAdmin() : _updateAdmin();
  }

  void _createAdmin() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final newAdmin = AdminModel(
      docId: id,
      uid: id,
      name: adminCtrl.nameCtrl.text,
      email: adminCtrl.emailCtrl.text,
      phone: adminCtrl.phoneCtrl.text,
      organizationName: adminCtrl.orgCtrl.text,
      role: adminCtrl.selectedRole.value,
      status: adminCtrl.selectedStatus.value,
      address: adminCtrl.addressCtrl.text,
      gstNumber: adminCtrl.gstCtrl.text,
      panNumber: adminCtrl.panCtrl.text,
      isVerified: false,
      profilePicUrl: null,
      subscription: null,
      subscriptionLimits: AdminSubscriptionLimits.fromMap(null),
      planName: null,
      planExpiry: null,
      trainerIds: const [],
      clientIds: const [],
      isSubscriptionActive: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    adminCtrl.createAdmin(newAdmin);
    Get.back();
  }

  // ---------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------
  void _updateAdmin() {
    adminCtrl.updateAdmin(
      admin!.docId,
      {
        "name": adminCtrl.nameCtrl.text,
        "email": adminCtrl.emailCtrl.text,
        "phone": adminCtrl.phoneCtrl.text,
        "organizationName": adminCtrl.orgCtrl.text,
        "address": adminCtrl.addressCtrl.text,
        "gstNumber": adminCtrl.gstCtrl.text,
        "panNumber": adminCtrl.panCtrl.text,
        "role": adminCtrl.selectedRole.value,
        "status": adminCtrl.selectedStatus.value,
        "updatedAt": DateTime.now().toIso8601String(),
      },
    );

    Get.back();
  }

  // ---------------------------------------------------------------
  // CARD WRAPPER
  // ---------------------------------------------------------------
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: child,
    );
  }
}
