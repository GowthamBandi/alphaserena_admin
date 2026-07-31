import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks the commercial lifecycle contract: Published/Hidden/Archived map onto
// the isActive + archived fields the backend & TrainerHQ read, and an archived
// plan is NEVER purchasable regardless of the isActive value passed in.

SubscriptionPlanModel _plan({
  bool isActive = true,
  bool archived = false,
  bool featured = false,
}) =>
    SubscriptionPlanModel(
      id: 'p',
      docId: 'p',
      planName: 'Pro',
      sortOrder: 1,
      isActive: isActive,
      archived: archived,
      featured: featured,
      monthlyPrice: 500,
      yearlyPrice: 5000,
      durationMonths: 1,
      limits: {for (final r in PlanResource.values) r: 5},
      capabilities: {for (final s in PlanCapabilities.slugs) s: false},
      points: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('status derives from isActive + archived', () {
    expect(_plan(isActive: true, archived: false).status, PlanStatus.published);
    expect(_plan(isActive: false, archived: false).status, PlanStatus.hidden);
    expect(_plan(isActive: false, archived: true).status, PlanStatus.archived);
    // Archived wins even if isActive somehow slipped true.
    expect(_plan(isActive: true, archived: true).status, PlanStatus.archived);
  });

  test('an archived plan is never written as purchasable (isActive:false)', () {
    final m = _plan(isActive: true, archived: true).toMap();
    expect(m['isActive'], false);
    expect(m['archived'], true);
  });

  test('published plan writes isActive:true', () {
    final m = _plan(isActive: true, archived: false).toMap();
    expect(m['isActive'], true);
    expect(m['archived'], false);
  });

  test('status survives a round-trip', () {
    for (final src in [
      _plan(isActive: true, archived: false),
      _plan(isActive: false, archived: false),
      _plan(isActive: false, archived: true),
    ]) {
      final back = SubscriptionPlanModel.fromMap(src.toMap(), 'p');
      expect(back.status, src.status);
    }
  });

  test('a legacy doc with no archived field reads as hidden/published, never archived', () {
    final published = SubscriptionPlanModel.fromMap(
        {'title': 'X', 'price': 100, 'months': 1, 'isActive': true}, 'x');
    final hidden = SubscriptionPlanModel.fromMap(
        {'title': 'Y', 'price': 100, 'months': 1, 'isActive': false}, 'y');
    expect(published.status, PlanStatus.published);
    expect(hidden.status, PlanStatus.hidden);
  });
}
