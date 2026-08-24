// Drift guard for this repo's twin of the canonical policy registry.
//
// The registry is byte-identical across three repositories BY CONVENTION, and
// convention is exactly what failed. alphaserena carries the canonical suite
// and received three material corrections (2026-08-17 → 08-19); this repo
// received none of them, and the guard that existed here actively PINNED THE
// WRONG VALUE — it asserted `company == 'AlphaSerena'`, so the copy that
// contradicted every published page passed its own drift test. A guard that
// pins the stale value is worse than no guard: it certifies the defect.
//
// What this repo was shipping until 2026-08-21, verified against the LIVE
// documents at https://trainershq-f5ded.web.app/legal/privacy:
//
//   published page          this repo's registry
//   ─────────────────────   ────────────────────
//   "AlphaSarena"           "AlphaSerena" throughout   ← wrong operator name
//   "Emergency contact"     absent entirely            ← third-party data
//   "goal weight"           absent                     ← under-disclosure
//   "Height"                absent                     ← under-disclosure
//   email+password AND      "signs you in with
//   Google Sign-In          Google Sign-In" only       ← undisclosed method
//
// Under-disclosure is the direction that harms users and the direction a Play
// Data Safety review compares against, so this is not cosmetic drift.
//
// WHY CONTENT ASSERTIONS AND NOT A CROSS-REPO HASH. A test cannot read a
// sibling repository, and a hash pinned in a comment rots silently. These
// assert the SUBSTANCE that drifted — what a reader of the policy actually
// relies on — so a future re-copy that loses a disclosure fails here. They
// deliberately mirror `policy_registry_parity_test.dart` in trainersHQ so the
// twins fail the same way.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/core/legal/policy_registry.dart';

String _allProse() {
  final b = StringBuffer();
  for (final doc in PolicyRegistry.all) {
    b.writeln(doc.title);
    b.writeln(doc.summary);
    for (final s in doc.sections) {
      b.writeln(s.heading);
      b.writeln(s.body);
    }
  }
  return b.toString();
}

/// Every retired spelling of either product name. The platform has shipped six
/// names for two products, and a guard that knows only the first one it was
/// taught cannot see the next rename. Case-sensitive on purpose — see the note
/// in "the source file itself carries no retired spelling".
const _retiredSpellings = <String>[
  'AlphaSerena',
  'AlphaSarena',
  'TrainerHQ',
  'TrainersHQ',
  'TrainerArena',
  'TrainersArena',
];

void main() {
  test('the published contract values match the platform decision record', () {
    expect(PolicyRegistry.version, '1.0');
    expect(PolicyRegistry.status, 'Published');
    expect(PolicyRegistry.effectiveDate, '10 August 2026');
    expect(PolicyRegistry.contact, 'frameingos@gmail.com');
    expect(
      PolicyRegistry.publicBaseUrl,
      'https://trainershq-f5ded.web.app/legal',
    );
  });

  test('the operator is named as the PUBLISHED documents name it', () {
    expect(
      PolicyRegistry.company,
      'Alphasarena',
      reason: 'every live legal page says AlphaSarena; the console must not '
          'name a different operating entity than the documents it links to. '
          'This assertion previously pinned the retired spelling.',
    );
  });

  test('no retired "AlphaSerena" spelling survives anywhere in the prose', () {
    // Deliberately checks the whole suite, not just the identity constant:
    // the spelling appeared in dozens of sentences, not only in `company`.
    final prose = _allProse();
    final offenders =
        _retiredSpellings.fold<int>(0, (n, b) => n + RegExp(b).allMatches(prose).length);
    expect(
      offenders,
      0,
      reason: 'the prose still spells the operator the retired way',
    );
  });

  test('the source file itself carries no retired spelling', () {
    // Case-sensitive, matching the trainersHQ twin. The file's own header
    // line reads "THE CANONICAL ALPHASERENA POLICY REGISTRY." in capitals;
    // tightening this to case-insensitive here would fail all three repos and
    // break byte-identity with the canonical, so it stays a canonical-side fix.
    final src = File('lib/core/legal/policy_registry.dart').readAsStringSync();
    expect(
      _retiredSpellings.any(src.contains),
      isFalse,
      reason: 'including comments — a stale comment here is how the next '
          'person concludes the old spelling was intentional',
    );
  });

  group('the disclosures this repo was missing are present', () {
    test('the emergency contact is disclosed as third-party data', () {
      final prose = _allProse();
      expect(prose.contains('Emergency contact'), isTrue);
      expect(
        prose.toLowerCase(),
        contains('another person'),
        reason: 'the point of the section is that the number belongs to '
            'someone who never agreed to anything',
      );
    });

    test('height and goal weight are disclosed', () {
      final prose = _allProse().toLowerCase();
      expect(prose.contains('height'), isTrue);
      expect(
        prose.contains('goal weight'),
        isTrue,
        reason: 'the profile editor collects both; omitting them from the '
            'collected-data list is under-disclosure',
      );
    });

    test('the sign-in section names email+password AND Google Sign-In', () {
      // ⚠️ THIS ASSERTION IS DELIBERATELY BOUND TO "The member app", NOT to the
      // two method names in isolation. The trainersHQ twin checks only that
      // 'email address and password' and 'Google Sign-In' each appear SOMEWHERE
      // in the suite — and the stale prose SATISFIED that while still being
      // wrong, because it read "The member app signs you in with Google
      // Sign-In. TrainerHQ and AlphaSarena Admin use an email address and
      // password." Both strings present, describing DIFFERENT APPS. Verified by
      // running this suite against the pre-fix file on 2026-08-21: every other
      // substance assertion went red and this one stayed green.
      final prose = _allProse();
      expect(
        prose.contains(
          'The member app signs you in with an email address and password',
        ),
        isTrue,
        reason: 'email+password is the MEMBER app\'s primary method since '
            '2026-08-19; a sentence that names it only for the coach and '
            'console apps leaves members signing in by an undisclosed method',
      );
      expect(
        prose.contains('or with Google Sign-In'),
        isTrue,
        reason: 'the member app offers both; naming only one means members '
            'sign in by a method their own policy does not disclose',
      );
    });
  });

  test('the four stable slugs and their URLs are intact', () {
    expect(PolicyId.values.map((e) => e.slug).toList(), [
      'privacy',
      'terms',
      'refund',
      'health-disclaimer',
    ]);
    for (final id in PolicyId.values) {
      expect(
        PolicyRegistry.urlOf(id),
        'https://trainershq-f5ded.web.app/legal/${id.slug}',
      );
    }
  });

  test('no unresolved legal markers survive in the shipped prose', () {
    final prose = _allProse().toLowerCase();
    expect(prose, isNot(contains('[legal review required]')));
    expect(prose, isNot(contains('still to be confirmed')));
    expect(prose, isNot(contains('still to be settled')));
  });
}
