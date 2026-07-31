// lib/screens/communication_screen.dart
//
// DOMAIN 7 — COMMUNICATION CENTER. Founder authors platform announcements /
// broadcasts: compose → target an audience → pick channels → save draft or send
// now, and track real delivery outcomes in a status history. Delivery is
// performed by the `fanoutAnnouncement` Cloud Function (trainershq-backend,
// functions/src/platform_announcements.ts), which resolves the audience and
// hands each recipient to the shared notify() writer. This screen is the
// authoring + monitoring surface and never delivers anything itself.
//
// The delivery counters shown here are WORKER-OWNED and rules-protected: this
// console cannot write them, so a number on this screen is always a real
// outcome. No scheduling control exists because no scheduler exists.

import 'dart:async';

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/communication_controller.dart';
import '../core/services/content_service.dart';
import '../core/services/targeting_service.dart';
import '../models/platform_announcement_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/content_preview_panel.dart';
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
    case AnnouncementStatus.ready:
      return _cScheduled;
    case AnnouncementStatus.queued:
    case AnnouncementStatus.publishing:
      return _cQueued;
    case AnnouncementStatus.published:
    case AnnouncementStatus.completed:
      return _cSent;
    case AnnouncementStatus.archived:
      return _cCancelled;
    case AnnouncementStatus.failed:
      return _cFailed;
    case AnnouncementStatus.cancelled:
      return _cCancelled;
  }
}

/// The timezone a new campaign starts in.
///
/// Deliberately UTC rather than a guess. Dart exposes only an ABBREVIATION
/// ("IST"), which is ambiguous — IST is both India and Ireland — while the
/// backend needs an IANA zone to get DST right. Silently guessing would put a
/// campaign an hour or several off with no visible cause, so the composer
/// shows the zone as an explicit field and the backend rejects one it cannot
/// resolve.
const String kDefaultCampaignTimezone = 'UTC';

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
                  // The campaign lifecycle, in the order a founder works
                  // through it. 'In flight' groups queued + publishing: from
                  // the founder's side both mean "the queue has it".
                  _chip(context, 'All', 'all', ctrl.announcements.length),
                  _chip(context, 'Drafts', 'draft',
                      ctrl.countByStatus('draft')),
                  _chip(context, 'Ready', 'ready', ctrl.countByStatus('ready')),
                  _chip(context, 'Scheduled', 'scheduled',
                      ctrl.countByStatus('scheduled')),
                  _chip(context, 'In flight', 'inflight',
                      ctrl.countByStatus('inflight')),
                  _chip(context, 'Published', 'sent',
                      ctrl.countByStatus('sent')),
                  if (ctrl.countByStatus('failed') > 0)
                    _chip(context, 'Failed', 'failed',
                        ctrl.countByStatus('failed')),
                  if (ctrl.countByStatus('archived') > 0)
                    _chip(context, 'Archived', 'archived',
                        ctrl.countByStatus('archived')),
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
              // The delivery record exists only after the worker has run, so
              // an undelivered announcement shows nothing here rather than a
              // fabricated "0 sent · 0 failed".
              if (a.hasDeliveryRecord)
                Text(a.deliverySummary,
                    style: AppText.body(size: 12).copyWith(
                        color: a.failedCount > 0 ? _cFailed : _cSent)),
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
        // Legacy only — the composer can no longer author this status and no
        // scheduler exists. Say so plainly instead of implying a pending send.
        return 'Legacy scheduled draft · will not send — edit and resend';
      case AnnouncementStatus.ready:
        return 'Ready · ${a.schedule.summary}';
      case AnnouncementStatus.queued:
        return 'Queued ${_when(a.queuedAt)} · awaiting publisher';
      case AnnouncementStatus.publishing:
        return 'Publishing now'
            '${a.requeuedCount > 0 ? ' · recovered ${a.requeuedCount}x' : ''}';
      case AnnouncementStatus.published:
        return 'Published ${_when(a.sentAt)}';
      case AnnouncementStatus.completed:
        return 'Completed after ${a.occurrenceCount} run'
            '${a.occurrenceCount == 1 ? '' : 's'}';
      case AnnouncementStatus.archived:
        return 'Archived';
      case AnnouncementStatus.failed:
        return 'Failed${a.lastError != null ? ' · ${a.lastError}' : ''}';
      case AnnouncementStatus.cancelled:
        return 'Cancelled';
    }
  }

  Widget _actions(BuildContext context, PlatformAnnouncementModel a) {
    final p = context.palette;
    final items = <PopupMenuEntry<String>>[];
    // A campaign the queue owns offers NOTHING but a read-only view: the rules
    // reject every write, and some recipients may already hold the message.
    if (!a.statusEnum.isInFlight) {
      if (a.isEditable) {
        items.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
      }
      if (a.isDraft ||
          a.statusEnum == AnnouncementStatus.ready ||
          a.isScheduled ||
          a.isCancelled ||
          a.statusEnum == AnnouncementStatus.failed ||
          a.statusEnum == AnnouncementStatus.published) {
        items.add(const PopupMenuItem(
            value: 'send', child: Text('Publish now')));
      }
      // Cancelling only makes sense before the queue takes it.
      if (a.isScheduled || a.statusEnum == AnnouncementStatus.ready) {
        items.add(const PopupMenuItem(value: 'cancel', child: Text('Cancel')));
      }
      if (!a.isArchived && (a.isSent || a.isCancelled ||
          a.statusEnum == AnnouncementStatus.failed)) {
        items.add(const PopupMenuItem(
            value: 'archive', child: Text('Archive')));
      }
      if (a.isDraft || a.isCancelled || a.isArchived) {
        items.add(const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: _cFailed))));
      }
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
      case 'archive':
        ctrl.archive(a.id);
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
    Get.dialog(_ComposeDialog(ctrl: ctrl, existing: a), barrierDismissible: false);
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
// NOTE: the client-side template list that used to live here has been
// REMOVED (EP-3). It hardcoded copy in the console with `{date}`-style
// placeholders that nothing ever substituted, so choosing that template
// and sending would have delivered a literal `{date}` to every recipient.
// Templates now come from the backend catalog (lib/content.ts) and are
// rendered server-side, which is also what makes the preview truthful.

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
  late final Set<String> _selectedIds = {...?widget.existing?.targetIds};
  late AnnouncementChannels _channels =
      widget.existing?.channels ?? const AnnouncementChannels();

  // Scheduling and recurrence state is gone: this backend has no scheduler, so
  // offering either would promise a delivery that never happens. Delivery is
  // "save draft" or "send now" — both of which the worker honours immediately.

  // ── EP-2 targeting state ─────────────────────────────────────────────
  final TargetingService _targeting = TargetingService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<TargetCandidate> _candidates = const [];
  bool _candidatesTruncated = false;
  bool _loadingCandidates = false;

  AudiencePreview? _preview;
  bool _previewLoading = false;
  String? _previewError;

  /// Guards against a slow response overwriting a newer one: only the most
  /// recent request may publish its result. Without this, clicking through
  /// audiences quickly could leave the count of a PREVIOUS audience on screen
  /// next to the current one — the console lying about who receives.
  int _previewSeq = 0;
  int _candidateSeq = 0;

  Timer? _previewDebounce;
  Timer? _searchDebounce;

  /// Per-dialog memo of resolved counts, keyed by audience + selection.
  final Map<String, AudiencePreview> _previewCache = {};

  // ── EP-3 content state ───────────────────────────────────────────────
  final ContentService _content = ContentService();
  late final TextEditingController _imageUrl =
      TextEditingController(text: widget.existing?.imageUrl ?? '');

  List<ContentTemplate> _templates = const [];
  ContentTemplate? _template;

  /// One controller per variable the selected template declares.
  final Map<String, TextEditingController> _varCtrls = {};

  /// EP-4 campaign rule. Defaults to the founder's own timezone so a schedule
  /// means what they expect without touching a picker.
  late CampaignSchedule _schedule = widget.existing?.schedule ??
      const CampaignSchedule(timezone: kDefaultCampaignTimezone);

  ContentPreview? _contentPv;
  bool _contentLoading = false;
  String? _contentError;
  int _contentSeq = 0;
  Timer? _contentDebounce;

  @override
  void initState() {
    super.initState();
    _refreshPreview();
    if (_audience.needsSelection) _loadCandidates();
    _loadTemplates();
    _refreshContent();
    _title.addListener(_refreshContent);
    _body.addListener(_refreshContent);
    _imageUrl.addListener(_refreshContent);
  }

  Future<void> _loadTemplates() async {
    try {
      final list = await _content.templates();
      if (!mounted) return;
      setState(() {
        _templates = list;
        final existingId = widget.existing?.templateId ?? '';
        if (existingId.isNotEmpty) {
          _template = list.where((t) => t.id == existingId).firstOrNull;
          if (_template != null) _syncVarCtrls(_template!);
        }
      });
      _refreshContent();
    } catch (_) {
      // The composer still works as free text if the catalog can't load.
    }
  }

  /// Keeps one controller per declared variable, seeded from the draft.
  void _syncVarCtrls(ContentTemplate t) {
    final saved = widget.existing?.variables ?? const <String, String>{};
    for (final v in t.variables) {
      _varCtrls.putIfAbsent(v, () {
        final c = TextEditingController(text: saved[v] ?? '');
        c.addListener(_refreshContent);
        return c;
      });
    }
  }

  Map<String, String> _variableValues() {
    final out = <String, String>{};
    final t = _template;
    if (t == null) return out;
    for (final v in t.variables) {
      final s = _varCtrls[v]?.text.trim() ?? '';
      if (s.isNotEmpty) out[v] = s;
    }
    return out;
  }

  /// Renders the content on the SERVER and shows the result. Debounced because
  /// it fires on every keystroke across the title, body, image and every
  /// variable field.
  void _refreshContent() {
    _contentDebounce?.cancel();
    _contentDebounce = Timer(const Duration(milliseconds: 350), _runContent);
  }

  Future<void> _runContent() async {
    final seq = ++_contentSeq;
    if (mounted) setState(() => _contentLoading = true);
    try {
      final pv = await _content.preview(
        templateId: _template?.id,
        title: _template == null ? _title.text : null,
        body: _template == null ? _body.text : null,
        imageUrl: _imageUrl.text.trim(),
        variables: _variableValues(),
      );
      if (!mounted || seq != _contentSeq) return;
      setState(() {
        _contentPv = pv;
        _contentError = null;
        _contentLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _contentSeq) return;
      setState(() {
        _contentError = 'Could not reach the content service.';
        _contentLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _searchDebounce?.cancel();
    _contentDebounce?.cancel();
    _imageUrl.dispose();
    for (final c in _varCtrls.values) {
      c.dispose();
    }
    _title.dispose();
    _body.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Asks the BACKEND resolver how many recipients this audience reaches.
  /// The console never counts recipients itself.
  ///
  /// DEBOUNCED and CACHED deliberately. Resolving `allPlatform` reads every
  /// owner, trainer and member document; firing that on each dropdown change
  /// or each keystroke in the picker would make browsing audiences cost a
  /// full-platform scan per interaction. The debounce collapses a burst into
  /// one request, and the cache makes flipping back to an audience free for
  /// the life of the dialog.
  void _refreshPreview() {
    _previewDebounce?.cancel();
    if (_audience.needsSelection && _selectedIds.isEmpty) {
      setState(() {
        _preview = null;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }
    final key = _previewKey();
    final cached = _previewCache[key];
    if (cached != null) {
      setState(() {
        _preview = cached;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    _previewDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runPreview(key),
    );
  }

  /// Cache key — the audience plus its selection, which is exactly what the
  /// backend resolves against.
  String _previewKey() {
    final ids = _audience.needsSelection
        ? (_selectedIds.toList()..sort()).join(',')
        : '';
    return '${_audience.id}|$ids';
  }

  Future<void> _runPreview(String key) async {
    final seq = ++_previewSeq;
    try {
      final pv = await _targeting.preview(_audience, _selectedIds.toList());
      if (!mounted || seq != _previewSeq) return;
      _previewCache[key] = pv;
      setState(() {
        _preview = pv;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _previewError = 'Could not reach the targeting service.';
        _previewLoading = false;
      });
    }
  }

  /// Debounced for the same reason as the preview: `searchTargets` performs a
  /// bounded collection scan (no substring index exists in Firestore), so
  /// issuing one per keystroke would scan thousands of documents per word
  /// typed.
  void _loadCandidates() {
    _searchDebounce?.cancel();
    if (_audience.idKind == null) return;
    setState(() => _loadingCandidates = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), _runCandidateSearch);
  }

  Future<void> _runCandidateSearch() async {
    final kind = _audience.idKind;
    if (kind == null) return;
    final seq = ++_candidateSeq;
    try {
      final r = await _targeting.search(kind, query: _searchCtrl.text);
      if (!mounted || seq != _candidateSeq) return;
      setState(() {
        _candidates = r.results;
        _candidatesTruncated = r.truncated;
        _loadingCandidates = false;
      });
    } catch (e) {
      if (!mounted || seq != _candidateSeq) return;
      setState(() {
        _candidates = const [];
        _candidatesTruncated = false;
        _loadingCandidates = false;
      });
    }
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
                    _label('TEMPLATE'),
                    const SizedBox(height: 8),
                    _templatePicker(context),
                    if (_template != null) ...[
                      const SizedBox(height: 10),
                      _variableFields(context),
                    ],
                    if (_template == null) ...[
                      const SizedBox(height: 16),
                      _label('TITLE'),
                      const SizedBox(height: 8),
                      _field(context, _title, 'Announcement title'),
                      const SizedBox(height: 16),
                      _label('MESSAGE'),
                      const SizedBox(height: 8),
                      _field(context, _body, 'What do you want to say?',
                          maxLines: 4, minLines: 3),
                    ],
                    const SizedBox(height: 16),
                    _label('IMAGE (OPTIONAL)'),
                    const SizedBox(height: 8),
                    _field(context, _imageUrl, 'https://… (optional)'),
                    const SizedBox(height: 18),
                    _label('PREVIEW — WHAT RECIPIENTS SEE'),
                    const SizedBox(height: 8),
                    _contentPreview(context),
                    const SizedBox(height: 18),
                    _label('AUDIENCE'),
                    const SizedBox(height: 8),
                    _audiencePicker(context),
                    if (_audience.needsSelection) ...[
                      const SizedBox(height: 10),
                      _targetSelector(context),
                    ],
                    const SizedBox(height: 10),
                    _recipientPreview(context),
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

  /// Template picker. Templates come from the BACKEND catalog, so the console
  /// can only offer copy the server can actually render.
  Widget _templatePicker(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: p.inputFill,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _template?.id ?? '',
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: '',
              child: Text('Free text (write your own)',
                  style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
            ),
            for (final t in _templates)
              DropdownMenuItem(
                value: t.id,
                child: Text('${t.label}  ·  v${t.version}',
                    style:
                        AppText.body(size: 13).copyWith(color: p.textPrimary)),
              ),
          ],
          onChanged: (v) {
            setState(() {
              _template = (v == null || v.isEmpty)
                  ? null
                  : _templates.where((t) => t.id == v).firstOrNull;
              if (_template != null) _syncVarCtrls(_template!);
            });
            _refreshContent();
          },
        ),
      ),
    );
  }

  /// One input per variable the selected template declares — no more, no less.
  Widget _variableFields(BuildContext context) {
    final p = context.palette;
    final t = _template!;
    if (t.variables.isEmpty) {
      return Text('This template takes no variables.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final v in t.variables) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: Text('{{$v}}',
                      style: AppText.body(size: 12)
                          .copyWith(color: p.textSecondary)),
                ),
                Expanded(
                  child: _field(context, _varCtrls[v]!, 'Value for $v'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The rendered preview — server-produced, both apps, light and dark.
  Widget _contentPreview(BuildContext context) {
    final p = context.palette;
    if (_contentError != null) {
      return Text(_contentError!,
          style: AppText.body(size: 12).copyWith(color: _cFailed));
    }
    final pv = _contentPv;
    if (pv == null) {
      return SizedBox(
        height: 60,
        child: Center(
          child: _contentLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2))
              : Text('Start typing to see the preview.',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted)),
        ),
      );
    }
    return Opacity(
      // Dim while a newer render is in flight so a stale preview is never
      // mistaken for the current content.
      opacity: _contentLoading ? 0.55 : 1,
      child: ContentPreviewPanel(preview: pv),
    );
  }

  /// Audience picker, grouped platform → organizations → trainers → members.
  ///
  /// Every entry here has a resolver in the backend catalog
  /// (`functions/src/lib/targeting.ts`). The console cannot offer a segment
  /// the server does not resolve, so no option on this menu is decorative.
  Widget _audiencePicker(BuildContext context) {
    final p = context.palette;
    const groupTitles = {
      AudienceGroup.platform: 'PLATFORM',
      AudienceGroup.organizations: 'ORGANIZATIONS',
      AudienceGroup.trainers: 'TRAINERS',
      AudienceGroup.members: 'MEMBERS',
    };
    final items = <DropdownMenuItem<AnnouncementAudience>>[];
    for (final g in AudienceGroup.values) {
      final inGroup =
          AnnouncementAudience.values.where((a) => a.group == g).toList();
      if (inGroup.isEmpty) continue;
      // A disabled header row gives the founder the hierarchy without needing
      // a nested menu widget.
      items.add(DropdownMenuItem(
        enabled: false,
        child: Text(groupTitles[g]!,
            style: AppText.label(size: 10).copyWith(color: p.textMuted)),
      ));
      for (final a in inGroup) {
        items.add(DropdownMenuItem(
          value: a,
          child: Text(a.label,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
        ));
      }
    }
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
          // Every row collapses to the SELECTED audience's label, so the
          // closed dropdown always states who receives — including when the
          // highlighted row is a disabled group header.
          selectedItemBuilder: (_) => [
            for (var i = 0; i < items.length; i++)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_audience.label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.body(size: 13).copyWith(color: p.textPrimary)),
              ),
          ],
          items: items,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _audience = v;
              // Changing audience invalidates any prior selection: ids of one
              // kind are meaningless for another, and the backend rejects a
              // selection left on a broad audience.
              _selectedIds.clear();
              _candidates = const [];
              _searchCtrl.clear();
            });
            _refreshPreview();
            if (v.needsSelection) _loadCandidates();
          },
        ),
      ),
    );
  }

  /// Selection picker for the audiences that need one. Candidates come from
  /// the backend `searchTargets` callable — the console lists identities to
  /// display, it does not enumerate recipients.
  Widget _targetSelector(BuildContext context) {
    final p = context.palette;
    final kind = _audience.idKind;
    if (kind == null) return const SizedBox.shrink();
    final noun = switch (kind) {
      TargetIdKind.org => 'organizations',
      TargetIdKind.trainer => 'trainers',
      TargetIdKind.member => 'members',
      TargetIdKind.plan => 'plans',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => _loadCandidates(),
          decoration: InputDecoration(
            hintText: 'Search $noun',
            prefixIcon: Icon(Icons.search, size: 18, color: p.textMuted),
            filled: true,
            fillColor: p.inputFill,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.accent)),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 190),
          decoration: BoxDecoration(
            color: p.inputFill,
            borderRadius: AppRadii.smR,
            border: Border.all(color: p.border),
          ),
          child: _loadingCandidates
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.2))))
              : _candidates.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('No $noun found.',
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                    )
                  : Scrollbar(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final c in _candidates)
                            CheckboxListTile(
                              dense: true,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              value: _selectedIds.contains(c.id),
                              activeColor: p.accent,
                              title: Text(c.title,
                                  style: AppText.body(size: 13)
                                      .copyWith(color: p.textPrimary)),
                              subtitle: c.subtitle.isEmpty
                                  ? null
                                  : Text(c.subtitle,
                                      style: AppText.body(size: 11)
                                          .copyWith(color: p.textMuted)),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedIds.add(c.id);
                                  } else {
                                    _selectedIds.remove(c.id);
                                  }
                                });
                                _refreshPreview();
                              },
                            ),
                        ],
                      ),
                    ),
        ),
        if (_candidatesTruncated) ...[
          const SizedBox(height: 6),
          Text(
            'Showing the first matches only — refine your search to see more.',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
        ],
        const SizedBox(height: 6),
        Text('${_selectedIds.length} selected',
            style: AppText.body(size: 12).copyWith(color: p.textSecondary)),
      ],
    );
  }

  /// The recipient preview — the answer to "who receives this".
  ///
  /// The number is computed by the BACKEND resolver, the same one the fan-out
  /// runs, so it is the delivery count rather than an estimate. A selection
  /// that resolves to fewer recipients than ids picked (a deleted entity, a
  /// removed trainer, a member whose profile is gone) is stated explicitly
  /// instead of quietly shrinking the total.
  Widget _recipientPreview(BuildContext context) {
    final p = context.palette;
    final needs = _audience.needsSelection;
    if (needs && _selectedIds.isEmpty) {
      return _previewShell(
        context,
        icon: Icons.groups_outlined,
        color: p.textMuted,
        title: 'Select at least one target',
        detail: 'The recipient count appears once you choose.',
      );
    }
    if (_previewLoading) {
      return _previewShell(
        context,
        icon: Icons.groups_outlined,
        color: p.textMuted,
        title: 'Counting recipients…',
        detail: 'Resolving this audience on the server.',
      );
    }
    if (_previewError != null) {
      return _previewShell(
        context,
        icon: Icons.error_outline,
        color: _cFailed,
        title: 'Could not count recipients',
        detail: _previewError!,
      );
    }
    final pv = _preview;
    if (pv == null) {
      return _previewShell(
        context,
        icon: Icons.groups_outlined,
        color: p.textMuted,
        title: 'Recipient count unavailable',
        detail: 'Reopen the audience to retry.',
      );
    }
    final zero = pv.total == 0;
    return _previewShell(
      context,
      icon: zero ? Icons.warning_amber_outlined : Icons.groups_outlined,
      color: zero ? _cQueued : _cSent,
      title: zero
          ? 'No recipients match this audience'
          : '${pv.total} recipient${pv.total == 1 ? '' : 's'}',
      detail: [
        pv.breakdown,
        if (pv.skipped > 0)
          '${pv.skipped} selected target${pv.skipped == 1 ? '' : 's'} '
              'skipped (removed or no account)',
      ].join(' · '),
    );
  }

  Widget _previewShell(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
  }) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: AppRadii.smR,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.label(size: 13).copyWith(color: color)),
                const SizedBox(height: 2),
                Text(detail,
                    style: AppText.body(size: 12)
                        .copyWith(color: p.textSecondary)),
              ],
            ),
          ),
        ],
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

  /// SEND MODE (EP-4). Immediate, one-off, or recurring — all executed by the
  /// backend queue. The console never computes a run instant: it states the
  /// rule and the scheduler resolves it, timezone- and DST-correct.
  Widget _deliveryPicker(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: p.inputFill,
            borderRadius: AppRadii.smR,
            border: Border.all(color: p.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CampaignSendMode>(
              value: _schedule.mode,
              isExpanded: true,
              items: [
                for (final m in CampaignSendMode.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m.label,
                        style: AppText.body(size: 13)
                            .copyWith(color: p.textPrimary)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  final now = DateTime.now();
                  _schedule = _schedule.copyWith(
                    mode: v,
                    // Seed sensible defaults so a newly chosen mode is already
                    // valid — the backend rejects an unresolvable rule, and
                    // making the founder discover that is poor UX.
                    year: _schedule.year ?? now.year,
                    month: _schedule.month ?? now.month,
                    day: _schedule.day ?? now.day,
                    weekday: _schedule.weekday ?? now.weekday % 7,
                    dayOfMonth: _schedule.dayOfMonth ?? now.day,
                  );
                });
              },
            ),
          ),
        ),
        if (_schedule.mode.needsSchedule) ...[
          const SizedBox(height: 10),
          _scheduleFields(context),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: p.inputFill,
            borderRadius: AppRadii.smR,
            border: Border.all(color: p.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_repeat_outlined, size: 18, color: p.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _schedule.summary,
                  style: AppText.body(size: 12)
                      .copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scheduleFields(BuildContext context) {
    final p = context.palette;
    Widget num(String label, int value, int lo, int hi,
        ValueChanged<int> onChanged) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style: AppText.body(size: 12).copyWith(color: p.textSecondary)),
          DropdownButton<int>(
            value: value.clamp(lo, hi),
            items: [
              for (var i = lo; i <= hi; i++)
                DropdownMenuItem(
                    value: i,
                    child: Text(i.toString().padLeft(2, '0'),
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textPrimary))),
            ],
            onChanged: (v) => onChanged(v ?? value),
          ),
        ],
      );
    }

    const weekdays = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday'
    ];
    final now = DateTime.now();
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        num('Hour', _schedule.hour, 0, 23,
            (v) => setState(() => _schedule = _schedule.copyWith(hour: v))),
        num('Minute', _schedule.minute, 0, 59,
            (v) => setState(() => _schedule = _schedule.copyWith(minute: v))),
        if (_schedule.mode == CampaignSendMode.once) ...[
          num('Day', _schedule.day ?? now.day, 1, 31,
              (v) => setState(() => _schedule = _schedule.copyWith(day: v))),
          num('Month', _schedule.month ?? now.month, 1, 12,
              (v) => setState(() => _schedule = _schedule.copyWith(month: v))),
          num('Year', _schedule.year ?? now.year, now.year, now.year + 3,
              (v) => setState(() => _schedule = _schedule.copyWith(year: v))),
        ],
        if (_schedule.mode == CampaignSendMode.weekly)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('On ',
                  style:
                      AppText.body(size: 12).copyWith(color: p.textSecondary)),
              DropdownButton<int>(
                value: (_schedule.weekday ?? 1) % 7,
                items: [
                  for (var i = 0; i < 7; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text(weekdays[i],
                            style: AppText.body(size: 12)
                                .copyWith(color: p.textPrimary))),
                ],
                onChanged: (v) => setState(
                    () => _schedule = _schedule.copyWith(weekday: v ?? 1)),
              ),
            ],
          ),
        if (_schedule.mode == CampaignSendMode.monthly)
          num('Day of month', _schedule.dayOfMonth ?? 1, 1, 31,
              (v) => setState(
                  () => _schedule = _schedule.copyWith(dayOfMonth: v))),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Timezone ',
                style: AppText.body(size: 12).copyWith(color: p.textSecondary)),
            SizedBox(
              width: 190,
              child: TextFormField(
                initialValue: _schedule.timezone,
                style: AppText.body(size: 12).copyWith(color: p.textPrimary),
                decoration: const InputDecoration(
                    isDense: true, hintText: 'e.g. Asia/Kolkata'),
                onChanged: (v) => setState(
                    () => _schedule = _schedule.copyWith(timezone: v.trim())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    // A queued / sent / failed announcement is read-only: the rules reject any
    // write to it, so offering "Save draft" and "Send now" would present
    // buttons that can only ever fail. Show a plain Close instead.
    final existing = widget.existing;
    if (existing != null && !existing.isEditable) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                existing.hasDeliveryRecord
                    ? existing.deliverySummary
                    : 'Delivering — this announcement can no longer be edited.',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => Get.back(),
              child: Text('Close', style: TextStyle(color: p.textSecondary)),
            ),
          ],
        ),
      );
    }
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
                  : () => _submit(_schedule.mode.needsSchedule
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
                  : Text(_schedule.mode.needsSchedule
                      ? 'Schedule'
                      : 'Send now'),
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
      targetIds: _selectedIds.toList(),
      channels: _channels,
      intent: intent,
      schedule: _schedule,
      templateId: _template?.id ?? '',
      variables: _variableValues(),
      imageUrl: _imageUrl.text.trim(),
    );
    if (!ok) return;
    // Close the dialog BEFORE the confirmation snackbar. AppSnackbar uses
    // Get.rawSnackbar (a GetX navigator entry); showing it first made the
    // following Get.back() pop the snackbar instead of this dialog, so the
    // dialog never closed. Close first, then confirm (also the correct UX order).
    Get.back();
    AppSnackbar.show(
      title: 'Saved',
      message: switch (intent) {
        AnnouncementIntent.draft => 'Draft saved',
        AnnouncementIntent.ready => 'Marked ready',
        AnnouncementIntent.schedule => 'Scheduled — ${_schedule.summary}',
        AnnouncementIntent.sendNow => 'Queued — delivering now',
      },
      background: Colors.green.shade700,
    );
  }
}
