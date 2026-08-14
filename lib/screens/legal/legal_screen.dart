import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/legal/policy_registry.dart';

/// AlphaSerena Admin's Legal & About surface.
///
/// The console had no legal surface of any kind — no policies, no about page,
/// no version. It is a single-operator tool, so it deliberately gets no consent
/// flow: the operator is the publisher, not a party accepting terms. What it
/// does need is the ability to READ the exact documents members and coaches are
/// shown, from the same [PolicyRegistry] the other two apps render, so the
/// operator can never answer a support question from a stale copy.
class AdminLegalScreen extends StatelessWidget {
  const AdminLegalScreen({super.key});

  static Future<void> open() =>
      Get.to<void>(() => const AdminLegalScreen()) ?? Future.value();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Legal & About')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              _MetaCard(theme: theme),
              const SizedBox(height: 20),
              Text(
                'POLICY DOCUMENTS',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.1,
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < PolicyId.values.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(_iconFor(PolicyId.values[i])),
                        title: Text(PolicyId.values[i].title),
                        subtitle: Text(
                          PolicyRegistry.of(PolicyId.values[i]).summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Get.to<void>(
                          () => _AdminPolicyView(id: PolicyId.values[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(PolicyId id) => switch (id) {
    PolicyId.privacy => Icons.privacy_tip_outlined,
    PolicyId.terms => Icons.description_outlined,
    PolicyId.refund => Icons.receipt_long_outlined,
    PolicyId.healthDisclaimer => Icons.health_and_safety_outlined,
  };
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Version and status always render. The effective date renders only when
    // one exists — an empty "Effective:" line would be worse than none, and no
    // publication date has been set.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PolicyRegistry.company, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Policy version ${PolicyRegistry.version}  ·  '
              '${PolicyRegistry.hasEffectiveDate ? 'Effective ${PolicyRegistry.effectiveDate}' : PolicyRegistry.status}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(PolicyRegistry.draftNotice, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            SelectableText(
              'Contact: ${PolicyRegistry.contact}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPolicyView extends StatelessWidget {
  const _AdminPolicyView({required this.id});
  final PolicyId id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = PolicyRegistry.of(id);
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
            children: [
              Text(doc.summary, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                'Version ${PolicyRegistry.version}  ·  ${PolicyRegistry.status}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 28),
              for (final s in doc.sections) ...[
                Text(s.heading, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                SelectableText(s.body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
