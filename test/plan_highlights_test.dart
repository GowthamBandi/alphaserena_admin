import 'package:alphaserena_admin_portel/core/services/plan_highlights.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins the highlight contract: the rendered `points` list TrainerHQ buyers read
// is EXACTLY the founder's hand-written lines — sanitized, never generated.
// Capacity is carried by the plan card's capacity chips, not by bullets.

void main() {
  group('sanitize', () {
    test('keeps the founder\'s lines in order, verbatim', () {
      expect(
        PlanHighlights.sanitize(['Priority support', 'Free onboarding call']),
        ['Priority support', 'Free onboarding call'],
      );
    });

    test('nothing is generated — an empty list stays empty', () {
      expect(PlanHighlights.sanitize(const []), isEmpty);
    });

    test('blank lines are dropped and whitespace trimmed', () {
      expect(PlanHighlights.sanitize(['  ', '', '  Real point  ']),
          ['Real point']);
    });

    test('case-insensitive duplicates collapse; the first spelling wins', () {
      expect(
        PlanHighlights.sanitize(
            ['Priority support', 'priority SUPPORT', ' Priority support ']),
        ['Priority support'],
      );
    });

    test('a capacity-shaped line is kept if the founder typed it — their call',
        () {
      expect(PlanHighlights.sanitize(['Up to 100 active clients']),
          ['Up to 100 active clients']);
    });
  });

  group('isDuplicate', () {
    test('matches ignoring case and surrounding whitespace', () {
      const existing = ['Priority support'];
      expect(PlanHighlights.isDuplicate(existing, 'priority support'), isTrue);
      expect(PlanHighlights.isDuplicate(existing, '  PRIORITY SUPPORT  '),
          isTrue);
      expect(PlanHighlights.isDuplicate(existing, 'Priority onboarding'),
          isFalse);
      expect(PlanHighlights.isDuplicate(const [], 'anything'), isFalse);
    });
  });
}
