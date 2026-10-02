// lib/screens/payments/payments_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/admin_controller.dart';
import '../../controllers/payments_controller.dart';
import '../../models/subscription_model.dart';
import '../../core/services/action_outcomes.dart';
import '../../core/services/organization_language.dart';
import '../../core/widgets/console/console_chrome.dart';

class PaymentsScreen extends StatelessWidget {
  PaymentsScreen({super.key});

  final ctrl = Get.put(PaymentsController());

  /// Names the organization behind a payment record. Falls back to an honest
  /// "Unknown organization (…)" rather than a bare uid — see
  /// `OrganizationLanguage.labelForUid`. Reads the organization list that the
  /// console already streams; if it is not registered (a widget test that only
  /// builds this screen) the uid is left as-is rather than crashing.
  String _orgLabel(String uid) {
    if (!Get.isRegistered<AdminController>()) return uid;
    return OrganizationLanguage.labelForUid(
      uid,
      Get.find<AdminController>().admins,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fa),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Obx(() {
          // The whole body, not just the table. Every KPI below is a SUM over
          // a list that a failed stream leaves empty, so rendering them during
          // a failure reported "₹0 total revenue" — a number the platform
          // never earned. On a money screen that is worse than showing nothing.
          final err = ctrl.loadError.value;
          if (err != null) {
            return Column(
              children: [
                _header(),
                const SizedBox(height: 20),
                Expanded(
                  child: ConsoleErrorState(error: err, onRetry: ctrl.retryLoad),
                ),
              ],
            );
          }
          return Column(
            children: [
              _header(),
              const SizedBox(height: 20),

              _kpiSection(),
              const SizedBox(height: 20),

              _middleSection(),
              const SizedBox(height: 20),

              _filters(),
              const SizedBox(height: 12),

              Expanded(child: _table()),
            ],
          );
        }),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _header() {
    return Row(
      children: const [
        Text(
          "Payments Intelligence",
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  // ============================================================
  // KPI CARDS (🔥 CORE)
  // ============================================================
  Widget _kpiSection() {
    return Obx(() {
      return Row(
        children: [
          _kpi(
            "Total Revenue",
            ctrl.totalRevenue.value,
            ctrl.monthlyGrowth.value,
          ),

          _kpi("This Month", ctrl.monthRevenue.value, ctrl.monthlyGrowth.value),

          _kpi("Today", ctrl.todayRevenue.value, ctrl.dailyGrowth.value),

          _kpiCount("Transactions", ctrl.totalTransactions.value),
        ],
      );
    });
  }

  Widget _kpi(String title, double value, double growth) {
    final isUp = growth >= 0;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _label()),
            const SizedBox(height: 8),

            Text(
              OrganizationLanguage.rupees(value),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                Icon(
                  isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isUp ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  "${growth.toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: isUp ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCount(String title, int value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _label()),
            const SizedBox(height: 8),
            Text(
              "$value",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MIDDLE SECTION (TOP ADMINS + PLAN BREAKDOWN)
  // ============================================================
  Widget _middleSection() {
    return Row(
      children: [
        Expanded(child: _topAdmins()),
        const SizedBox(width: 16),
        Expanded(child: _topPlans()),
      ],
    );
  }

  // ============================================================
  // TOP ADMINS
  // ============================================================
  Widget _topAdmins() {
    return Obx(() {
      final list = ctrl.topAdmins;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Top Paying Admins",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            ...list.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(_orgLabel(e.key))),
                    Text(
                      OrganizationLanguage.rupees(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ============================================================
  // PLAN BREAKDOWN
  // ============================================================
  Widget _topPlans() {
    return Obx(() {
      final list = ctrl.topPlans;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Revenue by Plan",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            ...list.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(OrganizationLanguage.rupees(e.value)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ============================================================
  // FILTERS
  // ============================================================
  Widget _filters() {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: InputDecoration(
              hintText: "Search...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (v) => ctrl.searchQuery.value = v,
          ),
        ),
        const SizedBox(width: 12),

        Obx(() {
          return DropdownButton<String>(
            value: ctrl.selectedPlan.value,
            items: ctrl.availablePlans
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => ctrl.selectedPlan.value = v!,
          );
        }),
      ],
    );
  }

  // ============================================================
  // TABLE
  // ============================================================
  Widget _table() {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final list = ctrl.filteredList;

      if (list.isEmpty) {
        return const Center(child: Text("No payments found"));
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => _row(list[i]),
        ),
      );
    });
  }

  Widget _row(SubscriptionModel s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(s.planName)),
          Expanded(
            child: Text(
              s.refundMinor > 0
                  ? '${OrganizationLanguage.rupees(s.amountPaid)} · '
                        '${OrganizationLanguage.rupees(s.refundAmount)} refunded'
                  : OrganizationLanguage.rupees(s.amountPaid),
            ),
          ),
          Expanded(child: Text(_orgLabel(s.adminUid))),
          Expanded(
            child: Text(
              (s.reference ?? '').isNotEmpty && s.razorpayPaymentId.isEmpty
                  ? 'ref ${s.reference}'
                  : s.paymentId,
            ),
          ),
          Expanded(child: Text(_fmt(s.createdAt))),
          SizedBox(width: 48, child: _refundAction(s)),
        ],
      ),
    );
  }

  // ============================================================
  // FOUNDER REFUND ACTION
  // ============================================================
  Widget _refundAction(SubscriptionModel s) {
    // Fully refunded — nothing left to give back.
    if (s.isFullyRefunded) {
      return const Center(
        child: Text(
          "Refunded",
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }

    // No gateway payment id on the receipt — the backend can't refund it.
    final canRefund = s.razorpayPaymentId.isNotEmpty;

    return Center(
      child: IconButton(
        tooltip: canRefund
            ? "Refund…"
            : "No gateway payment id — cannot refund",
        icon: const Icon(Icons.currency_rupee, size: 18),
        color: Colors.grey.shade700,
        onPressed: canRefund ? () => _openRefundDialog(s) : null,
      ),
    );
  }

  void _openRefundDialog(SubscriptionModel s) {
    // The dialog owns its text controllers and disposes them in
    // State.dispose (REF-13): disposing them in `Get.dialog(...).then` —
    // when the route's future completes, while the exit animation is still
    // rebuilding the fields — is this codebase's recorded dialog crash.
    Get.dialog(
      PaymentsRefundDialog(
        ctrl: ctrl,
        receiptId: s.id,
        initial: s,
        orgLabel: _orgLabel(s.adminUid),
      ),
      barrierDismissible: false,
    );
  }

  static Widget refundInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(blurRadius: 10, color: Colors.black.withValues(alpha: .05)),
      ],
    );
  }

  TextStyle _label() => const TextStyle(color: Colors.grey, fontSize: 13);

  String _fmt(DateTime d) => "${d.day}/${d.month}/${d.year}";
}

/// The Revenue screen's refund dialog. A StatefulWidget that OWNS its field
/// controllers (disposed in [State.dispose]) and its refund INTENT: one id per
/// opening, reused on every retry from this dialog (C2), so a repeated press
/// of the same decision is answered with the stored outcome instead of
/// reaching the gateway twice.
///
/// The refundable maximum is computed ONCE, from the LIVE receipt, when the
/// dialog opens. The dialog closes on every answer except a definite "no":
/// after a refund, an in-flight refund or an UNKNOWN outcome the same form
/// must not be one press away from a second refund — the next opening
/// recomputes the maximum from the receipt as it then stands.
class PaymentsRefundDialog extends StatefulWidget {
  const PaymentsRefundDialog({
    super.key,
    required this.ctrl,
    required this.receiptId,
    required this.initial,
    required this.orgLabel,
  });

  final PaymentsController ctrl;
  final String receiptId;
  final SubscriptionModel initial;
  final String orgLabel;

  @override
  State<PaymentsRefundDialog> createState() => _PaymentsRefundDialogState();
}

class _PaymentsRefundDialogState extends State<PaymentsRefundDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  late final String _intentId = ActionOutcomes.newRefundIntentId();
  late final SubscriptionModel _receipt =
      widget.ctrl.receiptById(widget.receiptId) ?? widget.initial;
  bool _partial = false;
  bool _revoke = false;

  /// A definite "not refunded" answer, shown in the dialog (which stays open
  /// so the founder can correct and retry with the same intent).
  RefundOutcome? _refusal;

  static final RegExp _wholeRupees = RegExp(r'^\d{1,9}$');

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _max => OrganizationLanguage.maxPartialRefundRupees(_receipt);

  int? get _partialValue {
    final t = _amount.text.trim();
    return _wholeRupees.hasMatch(t) ? int.parse(t) : null;
  }

  bool get _valid {
    if (_reason.text.trim().isEmpty) return false;
    if (!_partial) return _receipt.netMinor > 0;
    final v = _partialValue;
    return v != null && v >= 1 && v <= _max;
  }

  Future<void> _submit() async {
    final outcome = await widget.ctrl.refundPayment(
      _receipt,
      amount: _partial ? _partialValue : null,
      reason: _reason.text.trim(),
      revokeAccess: _revoke,
      intentId: _intentId,
    );
    if (!mounted) return;
    if (!outcome.closesDialog) {
      setState(() => _refusal = outcome);
      return;
    }
    // Pop FIRST, then report: a GetX snackbar is a route and would swallow
    // the pop meant for this dialog.
    Get.back();
    Get.snackbar(
      outcome.title,
      outcome.message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 10),
      backgroundColor: outcome.verdict == RefundVerdict.refunded
          ? null
          : Colors.orange.shade100,
      colorText: outcome.verdict == RefundVerdict.refunded
          ? null
          : Colors.orange.shade900,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _receipt;
    const row = PaymentsScreen.refundInfoRow;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Refund Payment",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              row("Organization", widget.orgLabel),
              row("Plan", s.planName),
              row("Paid", OrganizationLanguage.rupees(s.amountPaid)),
              if (s.refundMinor > 0)
                row(
                  "Already refunded",
                  OrganizationLanguage.rupees(s.refundAmount),
                ),
              row("Refundable", OrganizationLanguage.rupees(s.netAmount)),
              for (final x in s.refunds)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Refund: ${OrganizationLanguage.refundLine(x)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(
                      "Full refund · ${OrganizationLanguage.rupees(s.netAmount)}",
                    ),
                    selected: !_partial,
                    onSelected: (_) => setState(() => _partial = false),
                  ),
                  ChoiceChip(
                    label: const Text("Partial"),
                    selected: _partial,
                    onSelected: (_) => setState(() => _partial = true),
                  ),
                ],
              ),
              if (_partial) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Amount (whole ₹, 1–$_max)",
                    errorText:
                        _amount.text.trim().isEmpty ||
                            (_partialValue != null &&
                                _partialValue! >= 1 &&
                                _partialValue! <= _max)
                        ? null
                        : "Enter a whole amount between 1 and $_max",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: "Reason (required)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _revoke,
                onChanged: (v) => setState(() => _revoke = v ?? false),
                title: const Text(
                  "Also deactivate subscription",
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  "Ends the org's access now. The backend REJECTS the "
                  "whole refund if this is not the org's current "
                  "subscription payment — uncheck to refund an older "
                  "payment.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (_refusal != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_refusal!.title}. ${_refusal!.message}',
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                ),
              ],
              const SizedBox(height: 16),
              Obx(() {
                final busy = widget.ctrl.isRefunding.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      // Not while the call is in flight: closing now would
                      // lose the answer to a money-moving request.
                      onPressed: busy ? null : () => Get.back(),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: busy || !_valid ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Refund"),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
