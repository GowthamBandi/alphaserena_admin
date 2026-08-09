// ============================================================================
// TRANSFER DIALOG — the V1 manual settlement confirmation (Phase 4F/4G/4H).
//
// This is the single most consequential dialog in the console: what it submits
// becomes a terminal financial state. Its design rules:
//
//   • The button never says "Mark Paid". It says "Confirm ₹X transfer",
//     because the founder is attesting that money ALREADY MOVED — approval
//     happened earlier, and conflating the two is how a queue gets paid twice.
//   • The amount is prefilled with the settlement's net but must be explicitly
//     confirmed; the backend refuses anything that is not EXACTLY the current
//     net, so a stale screen fails loudly rather than settling a wrong number.
//   • The proof is uploaded to settlement_proofs/{THIS settlement}/… — the
//     dialog cannot express any other folder (the controller builds the path).
//   • The private note is labelled as private and travels to audit_logs only.
//   • Nothing renders optimistically: the dialog closes on the BACKEND's
//     confirmation, and the row updates from the Firestore stream.
//
// DI-friendly on purpose: everything external arrives as a callback, so widget
// tests exercise the gating logic without GetX, Firestore or Storage.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/settlement_model.dart';

/// What the founder attested. Handed to the controller verbatim.
typedef TransferSubmission = ({
  String utr,
  DateTime transferredAt,
  String method,
  int amountMinor,
  String notes,
  String internalNote,
  String? proofStoragePath,
});

typedef UploadProof = Future<String> Function({
  required Uint8List bytes,
  required String fileName,
  required String contentType,
});

typedef SubmitTransfer = Future<({bool ok, String message})> Function(
  TransferSubmission submission,
);

class TransferDialog extends StatefulWidget {
  final SettlementModel settlement;
  final bool proofRequired;
  final UploadProof onUploadProof;
  final SubmitTransfer onSubmit;
  final VoidCallback? onCancelUpload;

  /// 0..1 while uploading, -1 idle. A plain listenable so tests can drive it.
  final ValueListenable<double>? uploadProgress;

  const TransferDialog({
    super.key,
    required this.settlement,
    required this.onUploadProof,
    required this.onSubmit,
    this.proofRequired = true,
    this.onCancelUpload,
    this.uploadProgress,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final _utr = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _internal = TextEditingController();

  DateTime? _transferredAt = DateTime.now();
  String _method = 'bank_transfer';
  bool _confirmed = false;

  // Proof state.
  String? _proofPath;
  String _proofName = '';
  int _proofSize = 0;
  bool _uploading = false;
  String? _proofError;

  // Submission state.
  bool _submitting = false;
  String? _submitError;
  bool _conflict = false;

  @override
  void initState() {
    super.initState();
    // Prefilled, still editable: typing over it and getting it wrong is a
    // LOUD backend refusal, which is safer than a silent hidden field the
    // founder never compared against their banking app.
    _amount.text = (widget.settlement.netMinor / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _utr.dispose();
    _amount.dispose();
    _notes.dispose();
    _internal.dispose();
    super.dispose();
  }

  int? get _enteredMinor {
    final t = _amount.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    final minor = (v * 100).round();
    // Guard the float→paise conversion: reject anything that does not
    // round-trip exactly (e.g. "4882.005").
    if ((minor / 100 - v).abs() > 1e-9) return null;
    return minor;
  }

  TransferDraft get _draft => TransferDraft(
        expectedNetMinor: widget.settlement.netMinor,
        utr: _utr.text,
        transferredAt: _transferredAt,
        method: _method,
        enteredAmountMinor: _enteredMinor,
        proofStoragePath: _proofPath ?? '',
        proofUploaded: _proofPath != null,
        proofRequired: widget.proofRequired,
        confirmed: _confirmed,
      );

  Future<void> _pickAndUpload() async {
    setState(() => _proofError = null);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      setState(() => _proofError = 'Could not read that file. Try again.');
      return;
    }
    final mime = switch (f.extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
    final problem = proofFileProblem(mime: mime, sizeBytes: bytes.length);
    if (problem != null) {
      setState(() => _proofError = problem);
      return;
    }

    setState(() {
      _uploading = true;
      _proofPath = null; // replacing: the old reference is dropped first
      _proofName = f.name;
      _proofSize = bytes.length;
    });
    try {
      final path = await widget.onUploadProof(
        bytes: bytes,
        fileName: f.name,
        contentType: mime!,
      );
      if (!mounted) return;
      setState(() {
        _proofPath = path;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _proofError = _describeUploadError(e);
      });
    }
  }

  String _describeUploadError(Object e) {
    final s = e.toString();
    if (s.contains('canceled') || s.contains('cancelled')) {
      return 'Upload cancelled.';
    }
    if (s.contains('unauthorized') || s.contains('permission')) {
      return 'Storage refused the upload. If this settlement is already '
          'settled, its proof is frozen; otherwise check that the storage '
          'rules are deployed.';
    }
    if (s.contains('retry-limit') || s.contains('network')) {
      return 'The upload did not complete — the connection dropped. Retry.';
    }
    return s.replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
  }

  Future<void> _submit() async {
    final draft = _draft;
    if (!draft.submittable || _submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final r = await widget.onSubmit((
      utr: _utr.text.trim(),
      transferredAt: _transferredAt!,
      method: _method,
      amountMinor: _enteredMinor!,
      notes: _notes.text.trim(),
      internalNote: _internal.text.trim(),
      proofStoragePath: _proofPath,
    ));
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _submitError = r.message;
      // The one refusal that means "stop, someone else finished this":
      // surfaced differently so the founder does not retry a done settlement.
      _conflict = r.message.toLowerCase().contains('already settled');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.settlement;
    final draft = _draft;

    return Dialog(
      backgroundColor: p.background,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transfer to organization',
                      style: AppText.cardTitle(size: 17)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close, color: p.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _contextBlock(p, s),
                    const SizedBox(height: 16),
                    _field(
                      label: 'Bank reference (UTR) *',
                      controller: _utr,
                      hint: 'From your banking app after the transfer',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dateField(p)),
                        const SizedBox(width: 12),
                        Expanded(child: _methodField(p)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(
                      label: 'Transferred amount (₹) *',
                      controller: _amount,
                      hint: 'Must equal the settlement net exactly',
                      invalid: _enteredMinor != null &&
                          _enteredMinor != s.netMinor,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    if (_enteredMinor != null &&
                        _enteredMinor != s.netMinor) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Does not match the settlement net '
                        '(${formatMinor(s.netMinor)}). The backend will refuse '
                        'a mismatched amount.',
                        style: AppText.body(size: 11)
                            .copyWith(color: BrandColors.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _field(
                      label: 'Notes for the organization (optional)',
                      controller: _notes,
                      hint: 'Visible to the organization on its settlement',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      label: 'Private Super Admin note (optional)',
                      controller: _internal,
                      hint: 'Never shown to the organization — recorded in the '
                          'audit log only',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    _proofSection(p),
                    const SizedBox(height: 16),
                    // The attestation. Money already moved; this dialog only
                    // records that fact — and says so.
                    InkWell(
                      onTap: _submitting
                          ? null
                          : () => setState(() => _confirmed = !_confirmed),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _confirmed,
                            onChanged: _submitting
                                ? null
                                : (v) =>
                                    setState(() => _confirmed = v == true),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'I confirm this transfer was actually made '
                                'from the platform\'s bank account.',
                                style: AppText.body(size: 12.5)
                                    .copyWith(color: p.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_submitError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: (_conflict
                                  ? BrandColors.amber
                                  : BrandColors.error)
                              .withValues(alpha: 0.10),
                          borderRadius: AppRadii.smR,
                        ),
                        child: Text(
                          _conflict
                              ? 'This settlement was already completed by '
                                  'another administrator. Close this dialog — '
                                  'the record below is already up to date.'
                              : _submitError!,
                          style: AppText.body(size: 12).copyWith(
                            color: _conflict
                                ? BrandColors.amber
                                : BrandColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (!draft.submittable && _submitError == null)
                    Expanded(
                      child: Text(
                        draft.firstProblem ?? '',
                        style:
                            AppText.body(size: 11).copyWith(color: p.textMuted),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed:
                        draft.submittable && !_submitting && !_conflict
                            ? _submit
                            : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined, size: 16),
                    label: Text(
                      'Confirm ${formatMinor(s.netMinor)} transfer',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.smR,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextBlock(dynamic p, SettlementModel s) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  k,
                  style: AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12).copyWith(color: p.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatMinor(s.netMinor, currency: s.currency),
            style: AppText.title(size: 26).copyWith(color: p.accent),
          ),
          Text(
            'the amount to transfer',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 10),
          // WHERE THE NUMBER COMES FROM. Without this the operator is asked to
          // move money on a bare total, with no way to sanity-check it against
          // the payment before typing it into a bank — and "is ₹7,323 right?"
          // is exactly the question worth answering before the transfer, not
          // after. Shown as the arithmetic, not as a second total.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.inputFill,
              borderRadius: AppRadii.smR,
            ),
            child: Column(
              children: [
                row('Member paid', formatMinor(s.grossMinor)),
                row(
                  'Less fees',
                  '−${formatMinor(s.totalDeductionsMinor)}',
                ),
                Divider(height: 12, color: p.border),
                row('Net to transfer', formatMinor(s.netMinor)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          row('Organization', s.orgName.isEmpty ? s.adminId : s.orgName),
          row('Member', s.memberName.isEmpty ? '—' : s.memberName),
          if (s.destination != null)
            row(
              s.destination!.isUpi ? 'Send to (UPI)' : 'Send to (account)',
              '${s.destination!.label}'
              '${s.destination!.isUpi ? '' : ' · ${s.destination!.ifsc}'}',
            )
          else
            row('Send to', 'Check the organization\'s bank details'),
          row('Settlement', s.id),
          row('Payment', s.razorpayPaymentId),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    // The brand accent IS red, so a focused field and an invalid field look
    // identical. On the amount field — the one number that decides how much
    // money leaves the bank — that ambiguity is not acceptable, so an invalid
    // value gets a thicker border AND the inline explanation below it.
    bool invalid = false,
  }) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.body(size: 11.5).copyWith(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          enabled: !_submitting,
          onChanged: (_) => setState(() {}),
          style: AppText.body(size: 13).copyWith(color: p.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppText.body(size: 12).copyWith(color: p.textMuted),
            filled: true,
            fillColor: p.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: invalid
                  ? const BorderSide(color: BrandColors.error, width: 2)
                  : BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: invalid
                  ? const BorderSide(color: BrandColors.error, width: 2)
                  : BorderSide(color: p.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateField(dynamic p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transfer date *',
          style: AppText.body(size: 11.5).copyWith(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _submitting
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _transferredAt ?? DateTime.now(),
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 90)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _transferredAt = picked);
                  }
                },
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
                Icon(Icons.event, size: 15, color: p.textMuted),
                const SizedBox(width: 8),
                Text(
                  _transferredAt == null
                      ? 'Pick date'
                      : '${_transferredAt!.day}/${_transferredAt!.month}/'
                          '${_transferredAt!.year}',
                  style:
                      AppText.body(size: 13).copyWith(color: p.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodField(dynamic p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment method *',
          style: AppText.body(size: 11.5).copyWith(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.inputFill,
            borderRadius: AppRadii.smR,
            border: Border.all(color: p.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _method,
              isDense: true,
              isExpanded: true,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary),
              dropdownColor: p.surface,
              // Labels kept SHORT: the field sits in a half-width column and
              // the long form ("Bank transfer (NEFT/IMPS/RTGS)") clipped mid-
              // word at desktop widths, which on a financial form reads as a
              // rendering fault rather than a label.
              items: const [
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Bank transfer', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _method = v ?? 'bank_transfer'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _proofSection(dynamic p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.smR,
        border: Border.all(
          color: widget.proofRequired && _proofPath == null
              ? BrandColors.amber.withValues(alpha: 0.5)
              : p.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file, size: 15, color: p.textMuted),
              const SizedBox(width: 6),
              Text(
                'TRANSFER PROOF${widget.proofRequired ? ' *' : ''}',
                style: AppText.body(size: 10.5).copyWith(
                  color: p.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The bank receipt or transfer screenshot. PDF, JPEG or PNG, up to '
            '10 MB. The backend verifies the uploaded file itself and records '
            'its fingerprint — the document becomes part of the permanent '
            'settlement record and cannot be changed after confirmation.',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 10),
          if (_uploading) ...[
            Row(
              children: [
                Expanded(
                  child: widget.uploadProgress == null
                      ? const LinearProgressIndicator(minHeight: 5)
                      : ValueListenableBuilder<double>(
                          valueListenable: widget.uploadProgress!,
                          builder: (context, v, child) => LinearProgressIndicator(
                            value: v >= 0 ? v : null,
                            minHeight: 5,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    widget.onCancelUpload?.call();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Uploading $_proofName…',
              style: AppText.body(size: 11).copyWith(color: p.textMuted),
            ),
          ] else if (_proofPath != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: BrandColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$_proofName · '
                    '${(_proofSize / 1024).toStringAsFixed(0)} KB — uploaded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 12)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : _pickAndUpload,
                  child: const Text('Replace'),
                ),
              ],
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Choose file & upload'),
            ),
          if (_proofError != null) ...[
            const SizedBox(height: 6),
            Text(
              _proofError!,
              style: AppText.body(size: 11).copyWith(color: BrandColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
