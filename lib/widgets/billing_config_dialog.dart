// lib/widgets/billing_config_dialog.dart
//
// Tax & currency configuration for the whole platform.
//
// Design rule: a founder must never have to imagine the outcome. Every edit
// re-prices a worked example in real rupees using the SAME arithmetic the
// backend applies, and the dialog states plainly whether tax is live. Getting
// this wrong changes what every organization pays.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/billing_config_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/console/console_chrome.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_text.dart';
import '../models/billing_config_model.dart';

class BillingConfigDialog extends StatelessWidget {
  const BillingConfigDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ctrl = Get.put(BillingConfigController());
    final fmt = NumberFormat.decimalPattern('en_IN');

    String money(int minor) {
      final major = minor / 100;
      final whole = major == major.roundToDouble();
      return '${fmt.format(whole ? major.round() : major)}'
          '${whole ? '' : ''}';
    }

    return Dialog(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Obx(() {
          if (ctrl.isLoading.value) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            );
          }
          // 🔴 A FAILED READ IS NOT AN UNTAXED PLATFORM.
          //
          // Rendering the editor here would show the master switch OFF with no
          // rules — indistinguishable from a platform that has never charged
          // tax — over a document this dialog never read. Its Save button
          // republishes `taxes` and `authoredTaxes` as whole arrays, so one
          // click would wipe the live table. The error state replaces the
          // whole body, which is what removes the destructive control rather
          // than merely discouraging it.
          final err = ctrl.loadError.value;
          if (err != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: ConsoleErrorState(
                    error: err,
                    onRetry: ctrl.retryLoad,
                  ),
                ),
              ],
            );
          }
          final cfg = ctrl.draft;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _masterSwitch(context, ctrl),
                      const SizedBox(height: 16),
                      _currencyField(context, ctrl),
                      const SizedBox(height: 20),
                      _taxesSection(context, ctrl),
                      const SizedBox(height: 20),
                      _workedExample(context, ctrl, cfg, money),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              _footer(context, ctrl),
            ],
          );
        }),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, size: 20, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Billing & taxes',
                    style:
                        AppText.title(size: 17).copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Applies to every subscription order across the platform.',
                  style:
                      AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: Get.back,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _masterSwitch(BuildContext context, BillingConfigController ctrl) {
    final p = context.palette;
    final on = ctrl.enabled.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charge tax',
                    style: AppText.label(size: 13)
                        .copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  on
                      ? 'Live rules below are applied to every new order.'
                      : 'Off — buyers are charged exactly the plan price.',
                  style: AppText.body(size: 11.5)
                      .copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) => ctrl.enabled.value = v,
          ),
        ],
      ),
    );
  }

  Widget _currencyField(BuildContext context, BillingConfigController ctrl) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔴 READ-ONLY, and the copy beside it now says why.
        //
        // This was an editable field whose helper text read "the order is
        // created in it". It is not. `subscriptions.ts:createRazorpayOrder`
        // hardcodes `currency: "INR"`, and `pricing.ts:priceQuote` takes an
        // optional `currency` that NO caller ever passes, so every quote
        // defaults to INR too. The stored value reached nothing except this
        // dialog's own preview symbol — which is worse than a dead control,
        // because the preview appeared to respond to it.
        //
        // Disabled rather than deleted: `setCommerceConfig` validates a
        // 3-letter code, the document keeps the field, and supporting a second
        // currency is a backend change (Razorpay account settings, the order
        // call, the quote) that a text box cannot stand in for. Same rule as
        // SA-08 — a control that cannot do what it appears to do is removed
        // rather than re-stubbed.
        SizedBox(
          width: 140,
          child: TextFormField(
            key: const Key('billing-currency'),
            initialValue: ctrl.currency.value,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Currency',
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'Every order is created in INR. Selling in another currency needs '
              'backend work (the Razorpay order call and the price quote both '
              'hardcode INR), so this is shown rather than offered.',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _taxesSection(BuildContext context, BillingConfigController ctrl) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Taxes',
                  style: AppText.label(size: 13)
                      .copyWith(color: p.textPrimary)),
            ),
            TextButton.icon(
              onPressed: ctrl.addTax,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add tax'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (ctrl.taxes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: AppRadii.smR,
            ),
            child: Text(
              'No taxes configured. Add GST, VAT, a sales tax — anything: a '
              'tax is just a name, a rate and whether it is already included '
              'in the plan price.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          )
        else
          for (var i = 0; i < ctrl.taxes.length; i++)
            _taxRow(context, ctrl, i, ctrl.taxes[i]),
      ],
    );
  }

  Widget _taxRow(
    BuildContext context,
    BillingConfigController ctrl,
    int index,
    TaxRule rule,
  ) {
    final p = context.palette;
    final dead = !rule.isLive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.smR,
        border: Border.all(
          color: dead ? p.border : p.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: rule.name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'GST',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctrl.updateTax(index, rule.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue:
                      rule.percent == 0 ? '' : rule.percent.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Rate %',
                    hintText: '18',
                    isDense: true,
                  ),
                  onChanged: (v) => ctrl.updateTax(
                    index,
                    rule.copyWith(percent: double.tryParse(v) ?? 0),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => ctrl.removeTax(index),
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: rule.label,
                  decoration: InputDecoration(
                    labelText: 'Buyer-facing label',
                    hintText: rule.displayLabel,
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctrl.updateTax(index, rule.copyWith(label: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<bool>(
                  initialValue: rule.inclusive,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Applied',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Added on top'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('Already in price'),
                    ),
                  ],
                  onChanged: (v) => ctrl.updateTax(
                    index,
                    rule.copyWith(inclusive: v ?? false),
                  ),
                ),
              ),
            ],
          ),
          if (dead)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: const Color(0xFFB06A00)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Not applied — a tax needs a name and a rate above 0.',
                      style: AppText.body(size: 11)
                          .copyWith(color: const Color(0xFFB06A00)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The founder's confidence screen: the exact rupees a buyer pays, computed
  /// the same way the server computes them.
  Widget _workedExample(
    BuildContext context,
    BillingConfigController ctrl,
    BillingConfigModel cfg,
    String Function(int) money,
  ) {
    final p = context.palette;
    final base = (ctrl.samplePrice.value * 100).round();
    final exclusive = ctrl.exclusiveTaxMinor;
    final inclusive = ctrl.inclusiveTaxMinor;
    final total = ctrl.grandTotalMinor;
    final symbol = cfg.currency == 'INR' ? '₹' : '${cfg.currency} ';

    Widget line(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: (strong ? AppText.label(size: 13) : AppText.body(size: 12.5))
                        .copyWith(
                            color: strong ? p.textPrimary : p.textMuted)),
              ),
              Text(value,
                  style: (strong
                          ? AppText.label(size: 14)
                          : AppText.body(size: 12.5))
                      .copyWith(color: p.textPrimary)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('What a buyer pays',
                    style: AppText.label(size: 13)
                        .copyWith(color: p.textPrimary)),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: ctrl.samplePrice.value.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Plan price',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctrl.samplePrice.value = double.tryParse(v) ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          line('Plan price', '$symbol${money(base)}'),
          for (final t in cfg.liveTaxes.where((t) => !t.inclusive))
            line(t.displayLabel,
                '+$symbol${money(((base * t.percent) / 100).round())}'),
          const Divider(height: 18),
          line('Total charged', '$symbol${money(total)}', strong: true),
          if (inclusive > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Includes $symbol${money(inclusive)} tax already contained in '
                'the plan price.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
          if (exclusive == 0 && inclusive == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No tax is applied — this is exactly the plan price.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, BillingConfigController ctrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: ctrl.isSaving.value ? null : ctrl.save,
            icon: ctrl.isSaving.value
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(ctrl.isSaving.value ? 'Saving…' : 'Save settings'),
          ),
        ],
      ),
    );
  }
}
