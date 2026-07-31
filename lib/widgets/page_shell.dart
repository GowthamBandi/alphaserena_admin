import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';

/// Standard page frame: a themed title header + a scrollable content area.
class PageShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const PageShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context),
        const SizedBox(height: 20),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: child,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Below this width the title and the action cluster cannot share one line.
  /// They used to be forced to: both were unconstrained children of a [Row], so
  /// the title could not ellipsize and a [Wrap] of actions never wrapped —
  /// the row simply overflowed and pushed the right-most actions off-screen,
  /// where they could not be tapped at all.
  static const double _stackBelow = 720;

  Widget _header(BuildContext context) {
    final p = context.palette;

    final iconBox = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        borderRadius: AppRadii.smR,
      ),
      child: Icon(icon, color: p.accent),
    );
    // Always ellipsize: a long page title must yield space rather than overflow.
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.title(size: 26).copyWith(color: p.textPrimary),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (trailing != null && box.maxWidth < _stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                iconBox,
                const SizedBox(width: 14),
                Expanded(child: titleText),
              ]),
              const SizedBox(height: 12),
              // Full width so a Wrap of actions has a bounded box to break in.
              SizedBox(width: double.infinity, child: trailing!),
            ],
          );
        }
        return Row(
          children: [
            iconBox,
            const SizedBox(width: 14),
            // Loose: the title keeps its natural width when it fits and only
            // gives way (with an ellipsis) once the actions need the room.
            Flexible(child: titleText),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              // Takes the leftover space and pins the actions to the right,
              // preserving the original Spacer look while bounding the Wrap.
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: trailing!),
              ),
            ],
          ],
        );
      },
    );
  }
}
