// lib/screens/support_screen.dart
//
// JOURNEY 6 — SUPPORT. Founder platform-support surface.
//   • Org feedback  — actionable inbox (respond / resolve).
//   • Member reviews — read-only oversight of member → org ratings.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/support_controller.dart';
import '../models/org_feedback_model.dart';
import '../models/org_review_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

// Category accent colours (org feedback).
const _cBug = Color(0xFFD4341F);
const _cFeature = Color(0xFF3B6FD4);
const _cBilling = Color(0xFFB06A00);
const _cComplaint = Color(0xFFB0295E);
const _cOther = Color(0xFF6A6F7A);
const _cResolved = Color(0xFF1A7F5A);
const _cOpen = Color(0xFFB06A00);
const _cStar = Color(0xFFE8A317);

Color _categoryColor(String id) {
  switch (id) {
    case 'bug':
      return _cBug;
    case 'feature':
      return _cFeature;
    case 'billing':
      return _cBilling;
    case 'complaint':
      return _cComplaint;
    default:
      return _cOther;
  }
}

String _ago(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM yyyy').format(d);
}

class SupportScreen extends StatelessWidget {
  SupportScreen({super.key});

  final SupportController ctrl = Get.find<SupportController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Support',
      icon: Icons.support_agent_outlined,
      trailing: Obx(() => Text(
            ctrl.tab.value == 0
                ? (ctrl.feedbackError.value ? '—' : '${ctrl.openCount} open')
                : (ctrl.reviewsError.value ? '—' : '${ctrl.reviewCount} reviews'),
            style: AppText.body(size: 13)
                .copyWith(color: context.palette.textMuted),
          )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tabs(context),
          const SizedBox(height: 16),
          Obx(() =>
              ctrl.tab.value == 0 ? _feedbackTab(context) : _reviewsTab(context)),
        ],
      ),
    );
  }

  // ── TAB TOGGLE ──────────────────────────────────────────────────────
  Widget _tabs(BuildContext context) {
    final p = context.palette;
    Widget seg(String label, IconData icon, int index) {
      final selected = ctrl.tab.value == index;
      return InkWell(
        onTap: () => ctrl.tab.value = index,
        borderRadius: AppRadii.smR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.12) : p.surface,
            borderRadius: AppRadii.smR,
            border: Border.all(color: selected ? p.accent : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: selected ? p.accent : p.textMuted),
              const SizedBox(width: 8),
              Text(label,
                  style: AppText.label(size: 13).copyWith(
                      color: selected ? p.accent : p.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Obx(() => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            seg('Org feedback', Icons.forum_outlined, 0),
            seg('Member reviews', Icons.star_border_rounded, 1),
          ],
        ));
  }

  // ══════════════════════════════════════════════════════════════════
  // ORG FEEDBACK
  // ══════════════════════════════════════════════════════════════════
  Widget _feedbackTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: _searchDecoration(context, 'Search feedback, orgs…'),
        ),
        const SizedBox(height: 14),
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statusChip(context, 'All', 'all', ctrl.feedback.length),
                _statusChip(context, 'Open', 'open', ctrl.openCount),
                _statusChip(
                    context, 'Resolved', 'resolved', ctrl.resolvedCount),
              ],
            )),
        const SizedBox(height: 10),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _catChip(context, 'All', 'all'),
                for (final c in OrgFeedbackCategory.values)
                  _catChip(context, c.label, c.id),
              ],
            )),
        const SizedBox(height: 16),
        Obx(() {
          if (ctrl.feedbackError.value) {
            return _error(context, ctrl.retry);
          }
          if (ctrl.feedbackLoading.value && ctrl.feedback.isEmpty) {
            return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
          }
          final list = ctrl.filteredFeedback;
          if (list.isEmpty) {
            return _empty(context, Icons.forum_outlined, 'No feedback here',
                'Issues orgs raise from trainersHQ show up here to answer.');
          }
          return Column(
            children: [
              for (final f in list) ...[
                _feedbackCard(context, f),
                const SizedBox(height: 10),
              ],
            ],
          );
        }),
      ],
    );
  }

  Widget _feedbackCard(BuildContext context, OrgFeedbackModel f) {
    final p = context.palette;
    final cat = _categoryColor(f.category.toLowerCase());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: () => _respondDialog(context, f),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill(f.categoryEnum.label, cat),
                  const SizedBox(width: 8),
                  _statusPill(f.isResolved),
                  const Spacer(),
                  Text(_ago(f.createdAt),
                      style: AppText.body(size: 11)
                          .copyWith(color: p.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                f.subject.isEmpty ? '(no subject)' : f.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 14).copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                f.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 13).copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.business_outlined, size: 14, color: p.textMuted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(f.displayOrg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                  ),
                  if (f.hasResponse) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.reply, size: 14, color: _cResolved),
                    const SizedBox(width: 4),
                    Text('replied',
                        style: AppText.body(size: 12)
                            .copyWith(color: _cResolved)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _respondDialog(BuildContext context, OrgFeedbackModel f) {
    Get.dialog(_RespondDialog(feedback: f, ctrl: ctrl), barrierDismissible: false);
  }

  // ══════════════════════════════════════════════════════════════════
  // MEMBER REVIEWS (read-only)
  // ══════════════════════════════════════════════════════════════════
  Widget _reviewsTab(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => Row(
              children: [
                _summary(context, 'Average',
                    ctrl.reviewCount == 0
                        ? '—'
                        : ctrl.averageRating.toStringAsFixed(1),
                    _cStar),
                const SizedBox(width: 12),
                _summary(context, 'Reviews', '${ctrl.reviewCount}', p.accent),
                const SizedBox(width: 12),
                _summary(
                    context, 'Critical', '${ctrl.criticalReviewCount}', _cBug),
              ],
            )),
        const SizedBox(height: 16),
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ratingChip(context, 'All', 'all', ctrl.reviewCount),
                _ratingChip(context, 'Positive ★4+', 'positive',
                    ctrl.reviews.where((r) => r.isPositive).length),
                _ratingChip(context, 'Critical ★1–2', 'critical',
                    ctrl.criticalReviewCount),
              ],
            )),
        const SizedBox(height: 16),
        Obx(() {
          if (ctrl.reviewsError.value) {
            return _error(context, ctrl.retry);
          }
          if (ctrl.reviewsLoading.value && ctrl.reviews.isEmpty) {
            return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
          }
          final list = ctrl.filteredReviews;
          if (list.isEmpty) {
            return _empty(context, Icons.star_border_rounded, 'No reviews yet',
                'Member ratings of their gyms appear here as they come in.');
          }
          return Column(
            children: [
              for (final r in list) ...[
                _reviewCard(context, r),
                const SizedBox(height: 10),
              ],
            ],
          );
        }),
      ],
    );
  }

  Widget _reviewCard(BuildContext context, OrgReviewModel r) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stars(r.rating),
              const SizedBox(width: 8),
              Text(r.rating > 0 ? '${r.rating}.0' : '—',
                  style:
                      AppText.label(size: 13).copyWith(color: p.textSecondary)),
              const Spacer(),
              Text(_ago(r.lastActivity),
                  style: AppText.body(size: 11).copyWith(color: p.textMuted)),
            ],
          ),
          if (r.hasComment) ...[
            const SizedBox(height: 8),
            Text(r.comment,
                style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: p.textMuted),
              const SizedBox(width: 5),
              Text(r.displayMember,
                  style: AppText.body(size: 12).copyWith(color: p.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18, color: _cStar),
      ],
    );
  }

  Widget _summary(BuildContext context, String label, String value, Color c) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.border),
          boxShadow: AppShadows.card(p.isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: AppText.title(size: 22).copyWith(color: c)),
            const SizedBox(height: 2),
            Text(label,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ],
        ),
      ),
    );
  }

  // ── SHARED CHIPS / STATES ───────────────────────────────────────────
  InputDecoration _searchDecoration(BuildContext context, String hint) {
    final p = context.palette;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(Icons.search, color: p.textMuted),
      filled: true,
      fillColor: p.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.smR,
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.smR,
        borderSide: BorderSide(color: p.accent),
      ),
    );
  }

  Widget _statusChip(
      BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.statusFilter.value == value;
    final accent = value == 'resolved'
        ? _cResolved
        : value == 'open'
            ? _cOpen
            : p.accent;
    return _countChip(context, label, count, selected, accent,
        () => ctrl.statusFilter.value = value);
  }

  Widget _ratingChip(
      BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.ratingFilter.value == value;
    final accent = value == 'critical'
        ? _cBug
        : value == 'positive'
            ? _cResolved
            : p.accent;
    return _countChip(context, label, count, selected, accent,
        () => ctrl.ratingFilter.value = value);
  }

  Widget _countChip(BuildContext context, String label, int count,
      bool selected, Color accent, VoidCallback onTap) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: AppRadii.smR,
          border: Border.all(color: selected ? accent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.label(size: 13)
                    .copyWith(color: selected ? accent : p.textSecondary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? accent.withValues(alpha: 0.18) : p.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count',
                  style: AppText.label(size: 11)
                      .copyWith(color: selected ? accent : p.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catChip(BuildContext context, String label, String value) {
    final p = context.palette;
    final selected = ctrl.categoryFilter.value == value;
    final accent = value == 'all' ? p.accent : _categoryColor(value);
    return InkWell(
      onTap: () => ctrl.categoryFilter.value = value,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? accent : p.border),
        ),
        child: Text(label,
            style: AppText.body(size: 12)
                .copyWith(color: selected ? accent : p.textMuted)),
      ),
    );
  }

  Widget _pill(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: AppText.label(size: 11).copyWith(color: c)),
    );
  }

  Widget _statusPill(bool resolved) {
    final c = resolved ? _cResolved : _cOpen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(resolved ? 'Resolved' : 'Open',
              style: AppText.label(size: 11).copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String subtitle) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, size: 40, color: p.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(title,
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _error(BuildContext context, VoidCallback onRetry) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 38, color: p.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('Could not load',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('Check your connection and try again.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              side: BorderSide(color: p.accent),
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// RESPOND DIALOG (stateful — owns the reply field + busy state)
// ══════════════════════════════════════════════════════════════════════
class _RespondDialog extends StatefulWidget {
  final OrgFeedbackModel feedback;
  final SupportController ctrl;
  const _RespondDialog({required this.feedback, required this.ctrl});

  @override
  State<_RespondDialog> createState() => _RespondDialogState();
}

class _RespondDialogState extends State<_RespondDialog> {
  late final TextEditingController _reply =
      TextEditingController(text: widget.feedback.superAdminResponse ?? '');

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = widget.feedback;
    final cat = _categoryColor(f.category.toLowerCase());

    return Dialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: cat.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(f.categoryEnum.label,
                        style: AppText.label(size: 11).copyWith(color: cat)),
                  ),
                  const Spacer(),
                  Text(f.createdAt != null
                      ? DateFormat('d MMM yyyy, h:mm a').format(f.createdAt!)
                      : '',
                      style: AppText.body(size: 11)
                          .copyWith(color: p.textMuted)),
                ],
              ),
              const SizedBox(height: 14),
              Text(f.subject.isEmpty ? '(no subject)' : f.subject,
                  style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.business_outlined, size: 14, color: p.textMuted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(f.displayOrg,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: AppRadii.smR,
                ),
                child: SelectableText(f.message,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textSecondary)),
              ),
              const SizedBox(height: 18),
              Text('YOUR REPLY',
                  style: AppText.label(size: 11).copyWith(color: p.textMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _reply,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Write a reply to this organization…',
                  filled: true,
                  fillColor: p.inputFill,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadii.smR,
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadii.smR,
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Obx(() {
                final busy = widget.ctrl.isProcessing.value;
                return Row(
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => Get.back(),
                      child: Text('Cancel',
                          style: TextStyle(color: p.textMuted)),
                    ),
                    const Spacer(),
                    if (f.isResolved)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                // Pop FIRST, then report: the snackbar is a
                                // GetX route and would swallow this Get.back().
                                final ok = await widget.ctrl
                                    .setResolved(f.id, false);
                                if (!ok) return;
                                Get.back();
                                AppSnackbar.show(
                                  title: 'Reopened',
                                  message: 'The request is open again.',
                                  background: Colors.green.shade700,
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cOpen,
                          side: const BorderSide(color: _cOpen),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadii.mdR),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        child: const Text('Reopen'),
                      )
                    else
                      OutlinedButton(
                        onPressed: busy ? null : () => _submit(resolve: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.accent,
                          side: BorderSide(color: p.accent),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadii.mdR),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        child: const Text('Save reply'),
                      ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: busy ? null : () => _submit(resolve: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cResolved,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.mdR),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(f.hasResponse && f.isResolved
                              ? 'Update & keep resolved'
                              : 'Reply & resolve'),
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

  Future<void> _submit({required bool resolve}) async {
    final text = _reply.text.trim();
    if (text.isEmpty) {
      Get.snackbar('Reply needed', 'Write a reply before sending.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final ok = await widget.ctrl
        .respond(widget.feedback.id, response: text, resolve: resolve);
    // Keep the dialog — and the operator's typed reply — when the write failed.
    // `respond` has already said why.
    if (!ok) return;
    // CLOSE BEFORE REPORTING. `AppSnackbar` raises a GetX snackbar, which is a
    // ROUTE: raising it first makes this Get.back() pop the snackbar and leave
    // the dialog open over a row that has already changed.
    Get.back();
    AppSnackbar.show(
      title: 'Sent',
      message: resolve ? 'Reply sent · marked resolved' : 'Reply sent',
      background: Colors.green.shade700,
    );
  }
}
