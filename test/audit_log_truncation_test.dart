// SA-01 regression — the audit log must never answer "none" when it means
// "none in the part I loaded".
//
// The audit view streams the newest `pageSize` entries and filters that window
// CLIENT-SIDE. Before the fix it had a hard 300-row cap, no pagination and no
// disclosure, so a founder searching for a moderation action that happened
// more than 300 privileged actions ago (there are 67 writeAudit call sites in
// the backend, so that is weeks, not years) landed on the "No audit entries"
// empty state. In the one surface whose job is to answer "did this happen",
// a false negative is worse than an error.
//
// These tests drive the controller's pure query surface — the same getters the
// screen renders — with a synthetic window.

import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/controllers/audit_controller.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';

AuditLogModel entry({
  required String action,
  String actorUid = 'founder_1',
  String actorName = 'Gowtham',
  String targetId = 'org_A',
  String targetType = 'admin',
}) {
  return AuditLogModel(
    id: '$action-$targetId',
    action: action,
    actorUid: actorUid,
    actorName: actorName,
    targetId: targetId,
    targetType: targetType,
    createdAt: DateTime(2026, 8, 12),
    details: const {},
  );
}

/// A window of [n] filler rows that match none of the searches below.
List<AuditLogModel> filler(int n) => List.generate(
      n,
      (i) => entry(action: 'food_export', targetId: 'noise_$i'),
    );

void main() {
  group('SA-01 — a capped window must not be reported as the whole trail', () {
    test('a full window is recognised as capped', () {
      final c = AuditController();
      c.logs.value = filler(AuditController.pageSize);
      expect(c.atCap, isTrue);
    });

    test('a partial window is NOT capped — the trail is fully loaded', () {
      final c = AuditController();
      c.logs.value = filler(12);
      expect(c.atCap, isFalse);
    });

    test(
        'searching a capped window for something absent reports '
        '"not in the loaded window", never "no entries"', () {
      final c = AuditController();
      c.logs.value = filler(AuditController.pageSize);
      c.search.value = 'set_admin_status';

      expect(c.filtered, isEmpty);
      // THE REGRESSION: this used to be indistinguishable from an empty
      // collection, so the screen rendered "No audit entries".
      expect(c.emptyReason, AuditEmptyReason.noMatchInLoadedWindow);
      expect(c.emptyReason, isNot(AuditEmptyReason.noEntriesAtAll));
    });

    test(
        'the same search over a NOT-capped window may honestly answer '
        '"no such entry"', () {
      final c = AuditController();
      c.logs.value = filler(12);
      c.search.value = 'set_admin_status';

      expect(c.filtered, isEmpty);
      expect(c.emptyReason, AuditEmptyReason.noMatchAnywhere);
    });

    test('an action filter is narrowing too, not just the search box', () {
      final c = AuditController();
      c.logs.value = filler(AuditController.pageSize);
      c.actionFilter.value = 'set_admin_status';

      expect(c.isNarrowed, isTrue);
      expect(c.emptyReason, AuditEmptyReason.noMatchInLoadedWindow);
    });

    test('a genuinely empty collection still reports no entries at all', () {
      final c = AuditController();
      c.logs.value = <AuditLogModel>[];
      c.search.value = 'anything';

      expect(c.emptyReason, AuditEmptyReason.noEntriesAtAll);
    });

    test('an unfiltered full window is not an "empty" state at all', () {
      final c = AuditController();
      c.logs.value = filler(AuditController.pageSize);

      expect(c.isNarrowed, isFalse);
      expect(c.filtered, isNotEmpty);
    });
  });

  group('SA-01 — the operator can widen the window', () {
    test('loadMore extends the window by a page when capped', () {
      final c = AuditController();
      c.logs.value = filler(AuditController.pageSize);
      expect(c.windowSize.value, AuditController.pageSize);

      c.loadMore();
      expect(c.windowSize.value, AuditController.pageSize * 2);
    });

    test('loadMore is a no-op when everything is already loaded', () {
      final c = AuditController();
      c.logs.value = filler(10);

      c.loadMore();
      expect(
        c.windowSize.value,
        AuditController.pageSize,
        reason: 'widening a window that is not full would query nothing new',
      );
    });
  });

  group('SA-01 — search still works over what IS loaded', () {
    test('a match inside the window is found', () {
      final c = AuditController();
      c.logs.value = [
        ...filler(20),
        entry(action: 'set_admin_status', targetId: 'org_ACME'),
      ];
      c.search.value = 'org_acme';

      expect(c.filtered.length, 1);
      expect(c.filtered.single.targetId, 'org_ACME');
    });

    test('search matches actor, action, target and target type', () {
      final c = AuditController();
      c.logs.value = [
        entry(action: 'refund_payment', actorName: 'Gowtham'),
      ];
      for (final q in ['refund', 'gowtham', 'founder_1', 'org_a', 'admin']) {
        c.search.value = q;
        expect(c.filtered, hasLength(1), reason: 'query "$q" should match');
      }
    });
  });
}
