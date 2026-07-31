import 'package:flutter/material.dart';

import '../core/services/content_service.dart';

/// CONTENT PREVIEW (EP-3 Phase 4).
///
/// Shows the founder exactly what a recipient receives, in both apps and in
/// both themes, before anything is sent.
///
/// Every string rendered here comes from the BACKEND `previewContent`
/// callable — the same function the fan-out uses to render the delivered
/// payload. This widget performs no substitution and holds no copy of its own,
/// so a preview cannot disagree with the message. That is the same guarantee
/// EP-2 gave recipient counts, applied to content.
///
/// The two app columns mirror the real surfaces:
///   - the notification-center ROW, which shows the summary when one exists
///     and truncates (2 lines in TrainerHQ, 3 in AlphaSerena);
///   - the READER, which never truncates.
class ContentPreviewPanel extends StatelessWidget {
  const ContentPreviewPanel({super.key, required this.preview});

  final ContentPreview preview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Below ~760px the two device columns would each be too narrow to
        // represent a real phone row, so they stack instead of squeezing.
        final stacked = c.maxWidth < 760;
        final cards = [
          _DevicePreview(
            appName: 'TrainerHQ',
            bodyMaxLines: 2,
            preview: preview,
          ),
          _DevicePreview(
            appName: 'AlphaSerena',
            bodyMaxLines: 3,
            preview: preview,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!preview.valid) _invalidBanner(context),
            if (preview.sampled.isNotEmpty) _sampledBanner(context),
            if (preview.missing.isNotEmpty) _missingBanner(context),
            const SizedBox(height: 10),
            if (stacked)
              Column(
                children: [
                  cards[0],
                  const SizedBox(height: 12),
                  cards[1],
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _invalidBanner(BuildContext context) => _banner(
        context,
        Icons.error_outline,
        const Color(0xFFD4341F),
        'This content will not send',
        _reasonText(preview.reason),
      );

  Widget _sampledBanner(BuildContext context) => _banner(
        context,
        Icons.science_outlined,
        const Color(0xFF3B6FD4),
        'Preview uses sample values',
        // Naming them matters: a founder must never mistake demo copy for the
        // real message.
        '${preview.sampled.join(', ')} — supply real values before sending.',
      );

  Widget _missingBanner(BuildContext context) => _banner(
        context,
        Icons.warning_amber_outlined,
        const Color(0xFFB06A00),
        'Unfilled variables',
        '${preview.missing.join(', ')} — these render as empty text.',
      );

  static String _reasonText(String? r) {
    switch (r) {
      case 'missingTitle':
        return 'The title is empty.';
      case 'missingBody':
        return 'The message is empty.';
      case 'titleTooLong':
        return 'The title is longer than 140 characters.';
      case 'bodyTooLong':
        return 'The message is longer than 4000 characters.';
      case 'summaryTooLong':
        return 'The summary is longer than 200 characters.';
      case 'ctaLabelTooLong':
        return 'The button label is longer than 40 characters.';
      case 'unsafeImageUrl':
        return 'The image must be an absolute https:// URL.';
      case 'unresolvedVariable':
        return 'The content still contains an unfilled {{variable}}.';
      case 'dataTooLarge':
        return 'The payload exceeds the push size limit.';
      default:
        return 'The content failed validation.';
    }
  }

  Widget _banner(BuildContext context, IconData icon, Color color,
      String title, String detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
                Text(detail,
                    style: const TextStyle(fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One app's preview, rendered in light and dark side by side.
class _DevicePreview extends StatelessWidget {
  const _DevicePreview({
    required this.appName,
    required this.bodyMaxLines,
    required this.preview,
  });

  final String appName;

  /// Mirrors that app's real notification-center truncation.
  final int bodyMaxLines;
  final ContentPreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appName,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7)),
        const SizedBox(height: 6),
        _themed(dark: false),
        const SizedBox(height: 8),
        _themed(dark: true),
      ],
    );
  }

  Widget _themed({required bool dark}) {
    final bg = dark ? const Color(0xFF121417) : Colors.white;
    final border = dark ? const Color(0xFF2A2F36) : const Color(0xFFE3E6EA);
    final primary = dark ? const Color(0xFFF2F4F7) : const Color(0xFF12151A);
    final secondary = dark ? const Color(0xFFA8B0BA) : const Color(0xFF5B636E);
    final accent = dark ? const Color(0xFF7AA7F0) : const Color(0xFF2E6BD6);

    // The row shows the summary when one exists — exactly what both apps do.
    final rowText = (preview.summary?.isNotEmpty ?? false)
        ? preview.summary!
        : preview.body;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dark ? 'DARK' : 'LIGHT',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: secondary)),
          const SizedBox(height: 8),

          // ── notification-center row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.campaign_rounded, size: 16, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.title.isEmpty ? '(no title)' : preview.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: primary),
                    ),
                    if (rowText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        rowText,
                        maxLines: bodyMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, height: 1.35, color: secondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          Divider(color: border, height: 20),

          // ── reader ──
          Text('READER',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: secondary)),
          const SizedBox(height: 6),
          Text(
            preview.title.isEmpty ? '(no title)' : preview.title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: primary),
          ),
          const SizedBox(height: 8),
          if (preview.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                preview.imageUrl!,
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                // A broken image in the PREVIEW must be visible as broken —
                // silently hiding it would let a founder ship a message whose
                // image never loads on a device.
                errorBuilder: (_, _, _) => Container(
                  height: 90,
                  alignment: Alignment.center,
                  color: border,
                  child: Text('Image failed to load',
                      style: TextStyle(fontSize: 11, color: secondary)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // The reader never truncates — no maxLines here, by design.
          Text(
            preview.body.isEmpty ? '(no message)' : preview.body,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: secondary),
          ),
          if (preview.ctaLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(preview.ctaLabel!,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}
