import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena_admin_portel/models/food_request_model.dart';

// ════════════════════════════════════════════════════════════════════════
// NIP PHASE A — FoodRequestModel, PROVEN against the backend contract.
//
// These pin the parsing discipline before any UI exists: a request document
// from the server must survive the round trip, an unknown status must be
// tolerated (kept, displayed, never acted on), and the triage comparator must
// order the review queue by demand first and patience second.
// ════════════════════════════════════════════════════════════════════════

Map<String, dynamic> fullDoc() => {
  'schemaVersion': 1,
  'type': 'new',
  'requesterUid': 'uid-1',
  'requesterRole': 'trainer',
  'adminId': 'admin-9',
  'status': 'pending',
  'payload': {'name': 'Ragi Dosa', 'calories': 210},
  'normalizedKey': 'ragi dosa',
  'duplicateSuggestions': [
    {'foodId': 'f1', 'name': 'Ragi Dosa (plain)', 'score': 0.93},
    {'foodId': 'f2', 'name': 'Rava Dosa', 'score': 0.61},
  ],
  'demandCount': 7,
  'resolution': null,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 2)),
};

FoodRequestModel req({
  String id = 'r',
  int demand = 0,
  DateTime? createdAt,
  FoodRequestStatus status = FoodRequestStatus.pending,
}) => FoodRequestModel(
  id: id,
  demandCount: demand,
  createdAt: createdAt,
  status: status,
);

void main() {
  group('FoodRequestModel.fromMap', () {
    test('parses a full pending document', () {
      final m = FoodRequestModel.fromMap(fullDoc(), 'req-1');

      expect(m.id, 'req-1');
      expect(m.schemaVersion, 1);
      expect(m.type, FoodRequestType.newFood);
      expect(m.requesterUid, 'uid-1');
      expect(m.requesterRole, 'trainer');
      expect(m.adminId, 'admin-9');
      expect(m.status, FoodRequestStatus.pending);
      expect(m.isOpen, isTrue);
      expect(m.isResolved, isFalse);
      expect(m.payload['name'], 'Ragi Dosa');
      expect(m.proposedName, 'Ragi Dosa');
      expect(m.normalizedKey, 'ragi dosa');
      expect(m.demandCount, 7);
      expect(m.resolution, isNull);
      expect(m.duplicateSuggestions, hasLength(2));
      expect(m.duplicateSuggestions.first.isStrong, isTrue);
      expect(m.duplicateSuggestions.last.isStrong, isFalse);
      // Timestamp.toDate() yields local time; compare in UTC.
      expect(m.createdAt!.toUtc(), DateTime.utc(2026, 7, 1));
    });

    test('parses a resolved promote request', () {
      final doc = fullDoc()
        ..['type'] = 'promote'
        ..['status'] = 'approved'
        ..['payload'] = {'foodId': 'org-food-5'}
        ..['resolution'] = {
          'by': 'master-1',
          'at': Timestamp.fromDate(DateTime.utc(2026, 7, 3)),
          'action': 'approved',
          'reason': '',
          'resultFoodId': 'global-food-8',
        };
      final m = FoodRequestModel.fromMap(doc, 'req-2');

      expect(m.type, FoodRequestType.promote);
      expect(m.status, FoodRequestStatus.approved);
      expect(m.isOpen, isFalse);
      expect(m.isResolved, isTrue);
      expect(m.targetFoodId, 'org-food-5');
      expect(m.resolution, isNotNull);
      expect(m.resolution!.by, 'master-1');
      expect(m.resolution!.action, 'approved');
      expect(m.resolution!.resultFoodId, 'global-food-8');
      expect(m.resolution!.at!.toUtc(), DateTime.utc(2026, 7, 3));
    });

    test('an empty document parses to safe defaults, never throws', () {
      final m = FoodRequestModel.fromMap(const {}, 'bare');

      expect(m.id, 'bare');
      expect(m.schemaVersion, 1);
      expect(m.type, FoodRequestType.unknown);
      expect(m.status, FoodRequestStatus.unknown);
      expect(m.payload, isEmpty);
      expect(m.duplicateSuggestions, isEmpty);
      expect(m.demandCount, 0);
      expect(m.resolution, isNull);
      expect(m.createdAt, isNull);
      expect(m.targetFoodId, '');
      expect(m.proposedName, '');
    });

    test('malformed fields are tolerated, not fatal', () {
      final m = FoodRequestModel.fromMap({
        'schemaVersion': 'two', // not a number
        'demandCount': '9', // string, not num — defaults, no crash
        'payload': 'not-a-map',
        'duplicateSuggestions': [
          'not-a-map',
          {'name': 'no foodId — dropped'},
          {'foodId': 'ok', 'score': 'bad'},
        ],
        'resolution': 'not-a-map',
        'createdAt': 12345, // neither Timestamp nor String
      }, 'weird');

      expect(m.schemaVersion, 1);
      expect(m.demandCount, 0);
      expect(m.payload, isEmpty);
      expect(m.duplicateSuggestions, hasLength(1));
      expect(m.duplicateSuggestions.single.foodId, 'ok');
      expect(m.duplicateSuggestions.single.score, 0);
      expect(m.resolution, isNull);
      expect(m.createdAt, isNull);
    });
  });

  group('unknown-status tolerance', () {
    test('a future status is kept raw and treated as CLOSED', () {
      final m = FoodRequestModel.fromMap(
        fullDoc()..['status'] = 'escalated_v3',
        'r',
      );

      expect(m.status, FoodRequestStatus.unknown);
      expect(m.rawStatus, 'escalated_v3'); // still displayable, truthfully
      // Never open: an old console must not offer resolution actions on a
      // state it cannot name.
      expect(m.isOpen, isFalse);
      // But also never "resolved": we do not know what happened.
      expect(m.isResolved, isFalse);
    });

    test('a future type is kept raw', () {
      final m = FoodRequestModel.fromMap(fullDoc()..['type'] = 'recipe', 'r');
      expect(m.type, FoodRequestType.unknown);
      expect(m.rawType, 'recipe');
    });

    test('unknown status/type round-trip their raw wire spelling', () {
      final m = FoodRequestModel.fromMap(
        fullDoc()
          ..['status'] = 'escalated_v3'
          ..['type'] = 'recipe',
        'r',
      );
      final out = m.toMap();
      // toMap must not launder an unknown value into '' or a known one.
      expect(out['status'], 'escalated_v3');
      expect(out['type'], 'recipe');
    });

    test('unknown enum values have no wire name', () {
      expect(FoodRequestModel.statusWireName(FoodRequestStatus.unknown), isNull);
      expect(FoodRequestModel.typeWireName(FoodRequestType.unknown), isNull);
    });
  });

  group('status and type wire vocabulary', () {
    test('every contract status parses to its enum and back', () {
      const wire = {
        'pending': FoodRequestStatus.pending,
        'in_review': FoodRequestStatus.inReview,
        'approved': FoodRequestStatus.approved,
        'rejected': FoodRequestStatus.rejected,
        'merged_duplicate': FoodRequestStatus.mergedDuplicate,
      };
      wire.forEach((raw, status) {
        expect(FoodRequestModel.parseStatus(raw), status);
        expect(FoodRequestModel.statusWireName(status), raw);
      });
    });

    test('every contract type parses to its enum and back', () {
      const wire = {
        'new': FoodRequestType.newFood,
        'promote': FoodRequestType.promote,
        'correction': FoodRequestType.correction,
      };
      wire.forEach((raw, type) {
        expect(FoodRequestModel.parseType(raw), type);
        expect(FoodRequestModel.typeWireName(type), raw);
      });
    });

    test('isOpen is exactly pending or in_review', () {
      expect(req(status: FoodRequestStatus.pending).isOpen, isTrue);
      expect(req(status: FoodRequestStatus.inReview).isOpen, isTrue);
      expect(req(status: FoodRequestStatus.approved).isOpen, isFalse);
      expect(req(status: FoodRequestStatus.rejected).isOpen, isFalse);
      expect(req(status: FoodRequestStatus.mergedDuplicate).isOpen, isFalse);
      expect(req(status: FoodRequestStatus.unknown).isOpen, isFalse);
    });
  });

  group('toMap round trip', () {
    test('fromMap(toMap(x)) preserves every contract field', () {
      final original = FoodRequestModel.fromMap(fullDoc(), 'req-1');
      final round = FoodRequestModel.fromMap(original.toMap(), 'req-1');

      expect(round.schemaVersion, original.schemaVersion);
      expect(round.type, original.type);
      expect(round.requesterUid, original.requesterUid);
      expect(round.requesterRole, original.requesterRole);
      expect(round.adminId, original.adminId);
      expect(round.status, original.status);
      expect(round.payload, original.payload);
      expect(round.normalizedKey, original.normalizedKey);
      expect(round.demandCount, original.demandCount);
      expect(round.duplicateSuggestions.length,
          original.duplicateSuggestions.length);
      expect(round.duplicateSuggestions.first.foodId,
          original.duplicateSuggestions.first.foodId);
      expect(round.duplicateSuggestions.first.score,
          original.duplicateSuggestions.first.score);
      expect(round.createdAt, original.createdAt);
      expect(round.updatedAt, original.updatedAt);
      expect(round.resolution, isNull);
    });

    test('a resolution block survives the round trip', () {
      final doc = fullDoc()
        ..['status'] = 'rejected'
        ..['resolution'] = {
          'by': 'master-1',
          'at': Timestamp.fromDate(DateTime.utc(2026, 7, 4)),
          'action': 'rejected',
          'reason': 'Duplicate of an existing verified food.',
          'resultFoodId': '',
        };
      final round =
          FoodRequestModel.fromMap(FoodRequestModel.fromMap(doc, 'r').toMap(), 'r');

      expect(round.status, FoodRequestStatus.rejected);
      expect(round.resolution!.reason,
          'Duplicate of an existing verified food.');
      expect(round.resolution!.at!.toUtc(), DateTime.utc(2026, 7, 4));
    });
  });

  group('compareByDemand', () {
    test('higher demand sorts first', () {
      final list = [
        req(id: 'low', demand: 1, createdAt: DateTime.utc(2026, 1, 1)),
        req(id: 'high', demand: 9, createdAt: DateTime.utc(2026, 6, 1)),
        req(id: 'mid', demand: 4, createdAt: DateTime.utc(2026, 3, 1)),
      ]..sort(FoodRequestModel.compareByDemand);

      expect(list.map((r) => r.id), ['high', 'mid', 'low']);
    });

    test('equal demand breaks the tie by longest wait (oldest first)', () {
      final list = [
        req(id: 'newer', demand: 5, createdAt: DateTime.utc(2026, 7, 20)),
        req(id: 'older', demand: 5, createdAt: DateTime.utc(2026, 7, 1)),
      ]..sort(FoodRequestModel.compareByDemand);

      expect(list.map((r) => r.id), ['older', 'newer']);
    });

    test('missing createdAt sorts last within its demand band', () {
      final list = [
        req(id: 'undated', demand: 5),
        req(id: 'dated', demand: 5, createdAt: DateTime.utc(2026, 7, 1)),
      ]..sort(FoodRequestModel.compareByDemand);

      expect(list.map((r) => r.id), ['dated', 'undated']);
      // And two undated requests are stable equals, not a crash.
      expect(
        FoodRequestModel.compareByDemand(req(demand: 5), req(demand: 5)),
        0,
      );
    });
  });
}
