import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../models/admin_model.dart';

class AdminFormDialog extends StatefulWidget {
  final AdminModel? admin;

  const AdminFormDialog({super.key, this.admin});

  @override
  State<AdminFormDialog> createState() => _AdminFormDialogState();
}

class _AdminFormDialogState extends State<AdminFormDialog> {
  final ctrl = Get.find<AdminController>();

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    if (widget.admin == null) {
      ctrl.clearForm();
    } else {
      ctrl.loadToForm(widget.admin!);
    }
  }

  bool get isEdit => widget.admin != null;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: const Color(0xFFF4F6FA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          children: [
            /// ================= LEFT (FORM) =================
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(),

                        const SizedBox(height: 24),

                        _section(
                          "Basic Info",
                          Icons.person_outline,
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _field(
                                "Name",
                                ctrl.nameCtrl,
                                validator: (v) =>
                                    v!.isEmpty ? "Required" : null,
                              ),
                              _field(
                                "Email",
                                ctrl.emailCtrl,
                                validator: (v) => !GetUtils.isEmail(v!)
                                    ? "Invalid email"
                                    : null,
                              ),
                              _field(
                                "Phone",
                                ctrl.phoneCtrl,
                                validator: (v) =>
                                    v!.length < 8 ? "Invalid phone" : null,
                              ),
                              _field(
                                "Organization",
                                ctrl.orgCtrl,
                                validator: (v) =>
                                    v!.isEmpty ? "Required" : null,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        _section(
                          "Business Info",
                          Icons.business_outlined,
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _field("Address", ctrl.addressCtrl, full: true),
                              _field("GST Number", ctrl.gstCtrl),
                              _field("PAN Number", ctrl.panCtrl),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        _section(
                          "Account Status",
                          Icons.security_outlined,
                          _statusDropdown(),
                        ),

                        const SizedBox(height: 28),

                        _actions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            /// ================= RIGHT PANEL =================
            Container(
              width: 280,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overview",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),

                  const SizedBox(height: 16),

                  _info("Mode", isEdit ? "Edit" : "Create"),

                  if (isEdit) ...[
                    _info("ID", widget.admin!.docId),
                    _info(
                      "Created",
                      widget.admin!.createdAt.toString().split(" ").first,
                    ),
                  ],

                  const SizedBox(height: 24),

                  const Divider(),

                  const SizedBox(height: 16),

                  const Text(
                    "Subscription",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  if (!isEdit || !widget.admin!.isSubscriptionActive)
                    _empty("No active plan")
                  else
                    _subscription(widget.admin!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            isEdit ? "Edit Admin" : "Create Admin",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
      ],
    );
  }

  // ============================================================
  Widget _section(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(blurRadius: 10, color: Colors.black.withOpacity(.04)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ============================================================
  Widget _field(
    String label,
    TextEditingController controller, {
    bool full = false,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: full ? double.infinity : 250,
      child: TextFormField(
        controller: controller,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ============================================================
  Widget _statusDropdown() {
    return Obx(() {
      return DropdownButtonFormField<String>(
        value: ctrl.selectedStatus.value,
        items: ctrl.allowedStatus
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) => ctrl.selectedStatus.value = v!,
        decoration: InputDecoration(
          labelText: "Status",
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  // ============================================================
  Widget _actions() {
    return Obx(() {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: ctrl.isProcessing.value ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: ctrl.isProcessing.value
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? "Save Changes" : "Create Admin"),
            ),
          ),
          if (isEdit) ...[
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                ctrl.deleteAdmin(widget.admin!.docId);
                Get.back();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Delete"),
            ),
          ],
        ],
      );
    });
  }

  // ============================================================
  Widget _subscription(AdminModel a) {
    final l = a.subscriptionLimits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ======================================================
        // PLAN INFO
        // ======================================================
        _info("Plan", a.planName ?? "No Plan"),

        _info(
          "Expiry",
          a.planExpiry != null
              ? a.planExpiry!.toLocal().toString().split(" ").first
              : "N/A",
        ),

        const SizedBox(height: 14),

        // ======================================================
        // LIMITS GRID (PRO UI)
        // ======================================================
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _limitChip("Admins", l.maxAdmins),
            _limitChip("Trainers", l.maxTrainers),
            _limitChip("Clients", l.maxClients),
            _limitChip("Workout Plans", l.maxWorkoutPlans),
            _limitChip("Diet Plans", l.maxDietPlans),
          ],
        ),
      ],
    );
  }

  Widget _limitChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    return Text(text, style: TextStyle(color: Colors.grey.shade600));
  }

  // ============================================================
  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (isEdit) {
      ctrl.updateAdminFromForm(widget.admin!.docId);
    } else {
      ctrl.createAdminFromForm();
    }
  }
}
