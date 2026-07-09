// lib/screens/communication_screen.dart
//
// DOMAIN 7 — COMMUNICATION CENTER. Founder authors platform announcements /
// broadcasts: compose → target an audience → pick channels → send now / schedule
// / save draft, and track them in a status history. Delivery is performed by the
// `fanoutAnnouncement` Cloud Function (foundation — see CLAUDE.md); this screen
// is the authoring + monitoring surface.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/admin_controller.dart';
import '../controllers/communication_controller.dart';
import '../models/platform_announcement_model.dart';
import '../widgets/page_shell.dart';

const _cDraft = Color(0xFF6A6F7A);
const _cScheduled = Color(0xFF3B6FD4);
const _cQueued = Color(0xFFB06A00);
const _cSent = Color(0xFF1A7F5A);
const _cFailed = Color(0xFFD4341F);
const _cCancelled = Color(0xFF9AA0A6);

Color _statusColor(AnnouncementStatus s) {
  switch (s) {
    case AnnouncementStatus.draft:
      return _cDraft;
    case AnnouncementStatus.scheduled:
      return _cScheduled;
    case AnnouncementStatus.queued:
      return _cQueued;
    case AnnouncementStatus.sent:
      return _cSent;
    case AnnouncementStatus.failed:
      return _cFailed;
    case AnnouncementStatus.cancelled:
      return _cCancelled;
  }
}

String _when(DateTime? d) {
  if (d == null) return '—';
  return DateFormat('d MMM yyyy, h:mm a').format(d);
}

class CommunicationScreen extends StatelessWidget {
  CommunicationScreen({super.key});

  final CommunicationController ctrl = Get.find<CommunicationController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Communication',
      icon: Icons.campaign_outlined,
      trailing: Obx(() => Text('${ctrl.announcements.length} total',
          style: AppText.body(size: 13).copyWith(color: p.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Send announcements & broadcasts to organizations, trainers and members.',
                  style: AppText.body(size: 13).copyWith(color: p.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openComposer(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New announcement'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  shape:
                      const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(() => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chip(context, 'All', 'all', ctrl.announcements.length),
                  _chip(context, 'Drafts', 'draft',
                      ctrl.countByStatus('draft')),
                  _chip(context, 'Scheduled', 'scheduled',
                      ctrl.countByStatus('scheduled')),
                  _chip(context, 'Queued', 'queued',
                      ctrl.countByStatus('queued')),
                  _chip(context, 'Sent', 'sent', ctrl.countByStatus('sent')),
                ],
              )),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.hasError.value) return _error(context);
            if (ctrl.isLoading.value && ctrl.announcements.isEmpty) {
              return const SizedBox(
                  height: 220,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final list = ctrl.filtered;
            if (list.isEmpty) return _empty(context);
            return Column(
              children: [
                for (final a in list) ...[
                  _card(context, a),
                  const SizedBox(height: 10),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── CARD ────────────────────────────────────────────────────────────
  Widget _card(BuildContext context, PlatformAnnouncementModel a) {
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
              _statusPill(a.statusEnum),
              const SizedBox(width: 8),
              _tag(context, Icons.groups_outlined, a.audienceEnum.shortLabel,
                  p.accent),
              const Spacer(),
              _actions(context, a),
            ],
          ),
          const SizedBox(height: 10),
          Text(a.title.isEmpty ? '(untitled)' : a.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(size: 14).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text(a.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final ch in a.channels.enabledLabels)
                _tag(context, _channelIcon(ch), ch, p.textMuted),
              if (a.recurring)
                _tag(context, Icons.repeat, a.recurrence ?? 'recurring',
                    _cScheduled),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: p.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(_scheduleLine(a),
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ),
              if (a.isSent)
                Text('${a.sentCount} sent · ${a.failedCount} failed',
                    style: AppText.body(size: 12).copyWith(color: _cSent)),
            ],
          ),
        ],
      ),
    );
  }

  String _scheduleLine(PlatformAnnouncementModel a) {
    switch (a.statusEnum) {
      case AnnouncementStatus.draft:
        return 'Draft · updated ${_when(a.updatedAt)}';
      case AnnouncementStatus.scheduled:
        return 'Scheduled for ${_when(a.scheduledAt)}';
      case AnnouncementStatus.queued:
        return 'Queued ${_when(a.queuedAt)} · awaiting delivery worker';
      case AnnouncementStatus.sent:
        return 'Sent ${_when(a.sentAt)}';
      case AnnouncementStatus.failed:
        return 'Failed${a.lastError != null ? ' · ${a.lastError}' : ''}';
      case AnnouncementStatus.cancelled:
        return 'Cancelled';
    }
  }

  Widget _actions(BuildContext context, PlatformAnnouncementModel a) {
    final p = context.palette;
    final items = <PopupMenuEntry<String>>[];
    if (a.isEditable) {
      items.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
    }
    if (a.isDraft || a.isScheduled) {
      items.add(const PopupMenuItem(value: 'send', child: Text('Send now')));
    }
    if (a.isScheduled || a.isQueued) {
      items.add(const PopupMenuItem(value: 'cancel', child: Text('Cancel')));
    }
    if (a.isDraft || a.isCancelled) {
      items.add(const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: _cFailed))));
    }
    if (items.isEmpty) {
      items.add(const PopupMenuItem(value: 'view', child: Text('View')));
    }
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: p.textMuted),
      position: PopupMenuPosition.under,
      onSelected: (v) => _onAction(context, a, v),
      itemBuilder: (_) => items,
    );
  }

  void _onAction(
      BuildContext context, PlatformAnnouncementModel a, String action) {
    switch (action) {
      case 'edit':
      case 'view':
        _openComposer(context, a);
        break;
      case 'send':
        _confirm(context,
            title: 'Send now?',
            message: 'Queue "${a.title}" for immediate delivery.',
            confirmLabel: 'Send now',
            color: _cSent,
            onConfirm: () => ctrl.sendNow(a.id));
        break;
      case 'cancel':
        _confirm(context,
            title: 'Cancel announcement?',
            message: 'This stops it from being delivered.',
            confirmLabel: 'Cancel it',
            color: _cQueued,
            onConfirm: () => ctrl.cancel(a.id));
        break;
      case 'delete':
        _confirm(context,
            title: 'Delete announcement?',
            message: 'This permanently removes the draft.',
            confirmLabel: 'Delete',
            color: _cFailed,
            onConfirm: () => ctrl.remove(a.id));
        break;
    }
  }

  void _openComposer(BuildContext context, PlatformAnnouncementModel? a) {
    Get.dialog(_ComposeDialog(ctrl: ctrl, existing: a));
  }

  // ── SMALL WIDGETS ───────────────────────────────────────────────────
  IconData _channelIcon(String label) {
    switch (label) {
      case 'Push':
        return Icons.notifications_active_outlined;
      case 'In-app':
        return Icons.chat_bubble_outline;
      case 'Email':
        return Icons.mail_outline;
      case 'SMS':
        return Icons.sms_outlined;
      case 'WhatsApp':
        return Icons.chat_outlined;
      default:
        return Icons.send_outlined;
    }
  }

  Widget _tag(BuildContext context, IconData icon, String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: AppText.label(size: 11).copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _statusPill(AnnouncementStatus s) {
    final c = _statusColor(s);
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
          Text(s.label, style: AppText.label(size: 11).copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.statusFilter.value == value;
    final accent = value == 'all' ? p.accent : _statusColor(AnnouncementStatusX.fromId(value));
    return InkWell(
      onTap: () => ctrl.statusFilter.value = value,
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

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.campaign_outlined,
              size: 40, color: p.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('No announcements yet',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('Compose one to reach your organizations, trainers and members.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _error(BuildContext context) {
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
          Text('Could not load announcements',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: ctrl.retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              side: BorderSide(color: p.accent),
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
            ),
          ),
        ],
      ),
    );
  }

  // ── CONFIRM ─────────────────────────────────────────────────────────
  void _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Color color,
    required VoidCallback onConfirm,
  }) {
    final p = context.palette;
    Get.dialog(
      Dialog(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        AppText.title(size: 18).copyWith(color: p.textPrimary)),
                const SizedBox(height: 10),
                Text(message,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textSecondary)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Get.back(),
                        child:
                            Text('Cancel', style: TextStyle(color: p.textMuted))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Get.back();
                        onConfirm();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.mdR),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// COMPOSE DIALOG
// ══════════════════════════════════════════════════════════════════════
class _Template {
  final String title;
  final String body;
  const _Template(this.title, this.body);
}

const _templates = <_Template>[
  _Template('Scheduled maintenance',
      'We have scheduled maintenance on {date}. The apps may be briefly unavailable. Thank you for your patience.'),
  _Template('New feature',
      'We just shipped a new feature to help you run your gym better. Open the app to try it out!'),
  _Template('Renewal reminder',
      'Your subscription is due for renewal soon. Renew now to keep your gym running without interruption.'),
];

class _ComposeDialog extends StatefulWidget {
  final CommunicationController ctrl;
  final PlatformAnnouncementModel? existing;
  const _ComposeDialog({required this.ctrl, this.existing});

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');

  late AnnouncementAudience _audience =
      widget.existing?.audienceEnum ?? AnnouncementAudience.allPlatform;
  late final Set<String> _selectedOrgs =
      {...?widget.existing?.targetIds};
  late AnnouncementChannels _channels =
      widget.existing?.channels ?? const AnnouncementChannels();

  bool _scheduleLater = false;
  DateTime? _scheduledAt;
  late bool _recurring = widget.existing?.recurring ?? false;
  late String _recurrence = widget.existing?.recurrence ?? 'weekly';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null && e.isScheduled) {
      _scheduleLater = true;
      _scheduledAt = e.scheduledAt;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadii.smR,
                    ),
                    child: Icon(Icons.campaign_outlined, color: p.accent),
                  ),
                  const SizedBox(width: 12),
                  Text(isEdit ? 'Edit announcement' : 'New announcement',
                      style: AppText.title(size: 19)
                          .copyWith(color: p.textPrimary)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('TEMPLATES'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _templates)
                          ActionChip(
                            label: Text(t.title,
                                style: AppText.body(size: 12)
                                    .copyWith(color: p.textSecondary)),
                            backgroundColor: p.surfaceAlt,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                                side: BorderSide(color: p.border)),
                            onPressed: () {
                              _title.text = t.title;
                              _body.text = t.body;
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('TITLE'),
                    const SizedBox(height: 8),
                    _field(context, _title, 'Announcement title'),
                    const SizedBox(height: 16),
                    _label('MESSAGE'),
                    const SizedBox(height: 8),
                    _field(context, _body, 'What do you want to say?',
                        maxLines: 4, minLines: 3),
                    const SizedBox(height: 18),
                    _label('AUDIENCE'),
                    const SizedBox(height: 8),
                    _audiencePicker(context),
                    if (_audience.needsSelection) ...[
                      const SizedBox(height: 10),
                      _orgSelector(context),
                    ],
                    const SizedBox(height: 18),
                    _label('CHANNELS'),
                    const SizedBox(height: 8),
                    _channelPicker(context),
                    const SizedBox(height: 18),
                    _label('DELIVERY'),
                    const SizedBox(height: 8),
                    _deliveryPicker(context),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  // ── Field helpers ───────────────────────────────────────────────────
  Widget _label(String t) {
    final p = context.palette;
    return Text(t, style: AppText.label(size: 11).copyWith(color: p.textMuted));
  }

  Widget _field(BuildContext context, TextEditingController c, String hint,
      {int maxLines = 1, int minLines = 1}) {
    final p = context.palette;
    return TextField(
      controller: c,
      maxLines: maxLines,
      minLines: minLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: p.inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.accent)),
      ),
    );
  }

  Widget _audiencePicker(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: p.inputFill,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AnnouncementAudience>(
          value: _audience,
          isExpanded: true,
          items: [
            for (final a in AnnouncementAudience.values)
              DropdownMenuItem(
                value: a,
                child: Text(a.label,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textPrimary)),
              ),
          ],
          onChanged: (v) => setState(() => _audience = v ?? _audience),
        ),
      ),
    );
  }

  Widget _orgSelector(BuildContext context) {
    final p = context.palette;
    final admins = Get.isRegistered<AdminController>()
        ? Get.find<AdminController>().admins.toList()
        : [];
    if (admins.isEmpty) {
      return Text('No organizations available to select.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted));
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: p.inputFill,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Scrollbar(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final a in admins)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                value: _selectedOrgs.contains(a.docId),
                activeColor: p.accent,
                title: Text(
                  a.organizationName.isNotEmpty ? a.organizationName : a.name,
                  style: AppText.body(size: 13).copyWith(color: p.textPrimary),
                ),
                subtitle: Text(a.email,
                    style: AppText.body(size: 11).copyWith(color: p.textMuted)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedOrgs.add(a.docId);
                  } else {
                    _selectedOrgs.remove(a.docId);
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _channelPicker(BuildContext context) {
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged,
        {bool foundation = false}) {
      final p = context.palette;
      return FilterChip(
        label: Text(foundation ? '$label (soon)' : label,
            style: AppText.body(size: 12).copyWith(
                color: value ? p.accent : p.textSecondary)),
        selected: value,
        showCheckmark: false,
        backgroundColor: p.surfaceAlt,
        selectedColor: p.accent.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: value ? p.accent : p.border)),
        onSelected: onChanged,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        toggle('In-app', _channels.inApp,
            (v) => setState(() => _channels = _channels.copyWith(inApp: v))),
        toggle('Push', _channels.push,
            (v) => setState(() => _channels = _channels.copyWith(push: v))),
        toggle('Email', _channels.email,
            (v) => setState(() => _channels = _channels.copyWith(email: v)),
            foundation: true),
        toggle('SMS', _channels.sms,
            (v) => setState(() => _channels = _channels.copyWith(sms: v)),
            foundation: true),
        toggle('WhatsApp', _channels.whatsapp,
            (v) => setState(() => _channels = _channels.copyWith(whatsapp: v)),
            foundation: true),
      ],
    );
  }

  Widget _deliveryPicker(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _radio(context, 'Send now', !_scheduleLater,
                () => setState(() => _scheduleLater = false)),
            const SizedBox(width: 10),
            _radio(context, 'Schedule', _scheduleLater,
                () => setState(() => _scheduleLater = true)),
          ],
        ),
        if (_scheduleLater) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: AppRadii.smR,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: p.inputFill,
                borderRadius: AppRadii.smR,
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, size: 18, color: p.textMuted),
                  const SizedBox(width: 10),
                  Text(
                    _scheduledAt == null
                        ? 'Pick date & time'
                        : _when(_scheduledAt),
                    style: AppText.body(size: 13).copyWith(
                        color: _scheduledAt == null
                            ? p.textMuted
                            : p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _recurring,
                activeColor: p.accent,
                onChanged: (v) => setState(() => _recurring = v ?? false),
              ),
              Text('Repeat',
                  style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
              const SizedBox(width: 10),
              if (_recurring)
                DropdownButton<String>(
                  value: _recurrence,
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) =>
                      setState(() => _recurrence = v ?? _recurrence),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _radio(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: AppRadii.smR,
          border: Border.all(color: selected ? p.accent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16, color: selected ? p.accent : p.textMuted),
            const SizedBox(width: 8),
            Text(label,
                style: AppText.label(size: 13)
                    .copyWith(color: selected ? p.accent : p.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Obx(() {
        final busy = widget.ctrl.isProcessing.value;
        return Row(
          children: [
            TextButton(
              onPressed: busy ? null : () => Get.back(),
              child: Text('Cancel', style: TextStyle(color: p.textMuted)),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: busy ? null : () => _submit(AnnouncementIntent.draft),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.textSecondary,
                side: BorderSide(color: p.border),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Save draft'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () => _submit(_scheduleLater
                      ? AnnouncementIntent.schedule
                      : AnnouncementIntent.sendNow),
              style: ElevatedButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_scheduleLater ? 'Schedule' : 'Send now'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _submit(AnnouncementIntent intent) async {
    final ok = await widget.ctrl.submit(
      id: widget.existing?.id,
      title: _title.text,
      body: _body.text,
      audience: _audience,
      targetIds: _selectedOrgs.toList(),
      channels: _channels,
      intent: intent,
      scheduledAt: _scheduledAt,
      recurring: _recurring,
      recurrence: _recurrence,
    );
    if (ok) Get.back();
  }
}
