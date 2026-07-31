// lib/screens/payments_screen.dart
//
// Founder revenue ledger (READ-ONLY) from admin_payments_history.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/payments_controller.dart';
import '../models/subscription_model.dart';
import '../widgets/page_shell.dart';

final _inr = NumberFormat.decimalPattern('en_IN');
String _money(num v) => '₹${_inr.format(v.round())}';
const _cActive = Color(0xFF1A7F5A);

class PaymentsScreen extends StatelessWidget {
  PaymentsScreen({super.key});

  final PaymentsController ctrl = Get.find<PaymentsController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Payments",
      icon: Icons.payments_outlined,
      trailing: Obx(() => Text("${ctrl.totalTransactions.value} transactions",
          style: AppText.body(size: 13)
              .copyWith(color: context.palette.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() => Wrap(spacing: 14, runSpacing: 14, children: [
                _kpi(context, "Total revenue", _money(ctrl.totalRevenue.value),
                    Icons.account_balance_wallet_outlined,
                    const Color(0xFFB06A00)),
                _kpi(context, "This month", _money(ctrl.monthRevenue.value),
                    Icons.calendar_month_outlined, _cActive,
                    trend: ctrl.monthlyGrowth.value),
                _kpi(context, "This week", _money(ctrl.weekRevenue.value),
                    Icons.date_range_outlined, const Color(0xFF3B6FD4)),
                _kpi(context, "Today", _money(ctrl.todayRevenue.value),
                    Icons.today_outlined, const Color(0xFF6C5CE7)),
              ])),
          const SizedBox(height: 22),
          _toolbar(context),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.isLoading.value && ctrl.subscriptions.isEmpty) {
              return const SizedBox(
                  height: 220,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final list = ctrl.filteredList;
            if (list.isEmpty) return _empty(context);
            return Column(children: [
              for (final s in list) ...[
                _row(context, s),
                const SizedBox(height: 10),
              ],
            ]);
          }),
        ],
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, IconData icon,
      Color accent,
      {double? trend}) {
    final p = context.palette;
    return Container(
      width: 230,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: AppRadii.smR),
              child: Icon(icon, color: accent, size: 20),
            ),
            const Spacer(),
            if (trend != null)
              Row(children: [
                Icon(trend >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: trend >= 0 ? _cActive : const Color(0xFFD4341F)),
                Text("${trend.abs().toStringAsFixed(0)}%",
                    style: AppText.label(size: 12).copyWith(
                        color:
                            trend >= 0 ? _cActive : const Color(0xFFD4341F))),
              ]),
          ]),
          const SizedBox(height: 14),
          Text(value,
              style: AppText.title(size: 24).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text(label,
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
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
          onChanged: (v) => ctrl.searchQuery.value = v,
          decoration: InputDecoration(
            hintText: "Search by plan, payment id, or org…",
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
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ctrl.availablePlans.map((plan) {
                final selected = ctrl.selectedPlan.value == plan;
                return InkWell(
                  onTap: () => ctrl.selectedPlan.value = plan,
                  borderRadius: AppRadii.smR,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? p.accent.withValues(alpha: 0.12)
                          : p.surface,
                      borderRadius: AppRadii.smR,
                      border:
                          Border.all(color: selected ? p.accent : p.border),
                    ),
                    child: Text(plan,
                        style: AppText.label(size: 13).copyWith(
                            color:
                                selected ? p.accent : p.textSecondary)),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }

  Widget _row(BuildContext context, SubscriptionModel s) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: _cActive.withValues(alpha: 0.12),
              borderRadius: AppRadii.smR),
          child: const Icon(Icons.south_west, color: _cActive, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(s.planName.isEmpty ? "Subscription" : s.planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(size: 14)
                          .copyWith(color: p.textPrimary)),
                ),
                if (s.couponApplied) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(s.couponCode ?? "Coupon",
                        style:
                            AppText.label(size: 10).copyWith(color: p.accent)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Text(
                "${DateFormat('d MMM yyyy, h:mm a').format(s.createdAt)}  ·  ${s.paymentId.isEmpty ? 'no id' : s.paymentId}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(s.amountPaid),
                style:
                    AppText.label(size: 15).copyWith(color: p.textPrimary)),
            if (s.discountAmount > 0)
              Text("-${_money(s.discountAmount)}",
                  style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          ],
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: p.textMuted, size: 20),
          position: PopupMenuPosition.under,
          onSelected: (v) {
            if (v == 'refund') _refundDialog(context, s);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'refund', child: Text('Refund payment')),
          ],
        ),
      ]),
    );
  }

  void _refundDialog(BuildContext context, SubscriptionModel s) {
    final p = context.palette;
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: p.inputFill,
          enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.border)),
        );
    Get.dialog(Dialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Refund payment",
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text(
                "${s.planName.isEmpty ? 'Subscription' : s.planName} · ${_money(s.amountPaid)}",
                style: AppText.body(size: 13).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: dec("Amount in ₹ (blank = full refund)")),
              const SizedBox(height: 12),
              TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: dec("Reason (optional)")),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Get.back(),
                      child:
                          Text("Cancel", style: TextStyle(color: p.textMuted))),
                  const SizedBox(width: 8),
                  Obx(() => ElevatedButton(
                        onPressed: ctrl.isRefunding.value
                            ? null
                            : () async {
                                final amt =
                                    int.tryParse(amountCtrl.text.trim()) ?? 0;
                                final ok = await ctrl.refundPayment(
                                  paymentId: s.paymentId,
                                  historyDocId: s.id,
                                  amount: amt,
                                  reason: reasonCtrl.text.trim(),
                                );
                                if (ok) Get.back();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4341F),
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadii.mdR),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: ctrl.isRefunding.value
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text("Refund"),
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
<<<<<<< HEAD
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(s.planName)),
          Expanded(child: Text("₹${s.amountPaid}")),
          Expanded(child: Text(s.adminUid)),
          Expanded(child: Text(s.paymentId)),
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
    final maxRefundable = s.netAmount.floor();
    bool isPartial = false;
    bool revokeAccess = false;
    String? amountError;
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          bool isValid() {
            if (reasonCtrl.text.trim().isEmpty) return false;
            if (!isPartial) return true;
            final v = int.tryParse(amountCtrl.text.trim());
            return v != null && v >= 1 && v <= maxRefundable;
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Refund Payment",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),

                  // Context — org / plan / amounts
                  _refundInfoRow("Organization", s.adminUid),
                  _refundInfoRow("Plan", s.planName),
                  _refundInfoRow("Paid", "₹${s.amountPaid}"),
                  if (s.refundAmount > 0)
                    _refundInfoRow(
                      "Already refunded",
                      "₹${s.refundAmount.toInt()}",
                    ),
                  _refundInfoRow("Refundable", "₹$maxRefundable"),
                  const SizedBox(height: 16),

                  // Full vs partial
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text("Full refund"),
                        selected: !isPartial,
                        onSelected: (_) => setState(() {
                          isPartial = false;
                          amountError = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("Partial"),
                        selected: isPartial,
                        onSelected: (_) => setState(() => isPartial = true),
                      ),
                    ],
                  ),

                  if (isPartial) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Amount (₹, 1–$maxRefundable)",
                        errorText: amountError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        final n = int.tryParse(v.trim());
                        amountError =
                            (v.trim().isEmpty ||
                                (n != null && n >= 1 && n <= maxRefundable))
                            ? null
                            : "Enter a whole amount between 1 and $maxRefundable";
                      }),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
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
                    value: revokeAccess,
                    onChanged: (v) =>
                        setState(() => revokeAccess = v ?? false),
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

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      Obx(() {
                        final busy = ctrl.isRefunding.value;
                        return ElevatedButton(
                          onPressed: busy || !isValid()
                              ? null
                              : () async {
                                  final ok = await ctrl.refundPayment(
                                    s,
                                    amount: isPartial
                                        ? int.parse(amountCtrl.text.trim())
                                        : null,
                                    reason: reasonCtrl.text.trim(),
                                    revokeAccess: revokeAccess,
                                  );
                                  if (ok) Get.back();
                                },
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Refund"),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    ).then((_) {
      // Dialog closed (save or cancel) — release the field controllers.
      amountCtrl.dispose();
      reasonCtrl.dispose();
    });
  }

  Widget _refundInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: _label())),
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
=======
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(Icons.receipt_long_outlined,
            size: 40, color: p.textMuted.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text("No payments yet",
            style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
        const SizedBox(height: 4),
        Text("Subscription payments will appear here once gyms subscribe.",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      ]),
    );
  }
>>>>>>> origin/main
}
