// Drift guard for this repo's twin of the canonical policy registry.
//
// The registry is byte-identical across three repositories by convention, and
// alphaserena carries the full content suite — but a copy that drifts HERE
// would tell the operator's own console a different agreement from the one
// the apps publish, and this repo previously had no guard at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/core/legal/policy_registry.dart';

void main() {
  test('the published contract values match the platform decision record', () {
    expect(PolicyRegistry.version, '1.0');
    expect(PolicyRegistry.status, 'Published');
    expect(PolicyRegistry.effectiveDate, '10 August 2026');
    expect(PolicyRegistry.company, 'AlphaSerena');
    expect(PolicyRegistry.contact, 'frameingos@gmail.com');
    expect(
      PolicyRegistry.publicBaseUrl,
      'https://trainershq-f5ded.web.app/legal',
    );
  });

  test('the four stable slugs and their URLs are intact', () {
    expect(
      PolicyId.values.map((e) => e.slug).toList(),
      ['privacy', 'terms', 'refund', 'health-disclaimer'],
    );
    for (final id in PolicyId.values) {
      expect(
        PolicyRegistry.urlOf(id),
        'https://trainershq-f5ded.web.app/legal/${id.slug}',
      );
    }
  });

  test('no unresolved legal markers survive in the shipped prose', () {
    final all = StringBuffer();
    for (final doc in PolicyRegistry.all) {
      for (final s in doc.sections) {
        all.writeln(s.body);
      }
    }
    final prose = all.toString().toLowerCase();
    expect(prose, isNot(contains('[legal review required]')));
    expect(prose, isNot(contains('still to be confirmed')));
    expect(prose, isNot(contains('still to be settled')));
  });
}
