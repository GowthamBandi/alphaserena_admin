// THE TILE MUST SHOW THE ROWS IT COUNTS.
//
// Same contract the Trainers screen pins: every count on a tile equals the
// length of the list that tile opens, a soft-deleted record is in neither, and
// the total agrees with the Dashboard's headcount rule (total − isDeleted).
// A number is easy to keep right in isolation; that is how they drift apart.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/client_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/services/member_language.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

final now = DateTime(2026, 9, 24, 12);

class _Members extends ClientController {
  _Members() {
    clock = () => now;
  }
  @override
  // ignore: must_call_super
  void onInit() {
    wireFilters();
  }
}

class _Orgs extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Trainers extends TrainerController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

ClientModel m(String id, Map<String, dynamic> doc) => ClientModel.fromMap({
  'adminId': 'org1',
  'authUid': 'u-$id',
  'name': 'Member $id',
  'email': '$id@m.in',
  'createdAt': now.subtract(const Duration(days: 40)),
  ...doc,
}, id);

void main() {
  late _Members c;

  setUp(() {
    Get.reset();
    final orgs = Get.put<AdminController>(_Orgs(), permanent: true);
    orgs.admins.value = [
      AdminModel.fromMap({
        'organizationName': 'Iron Temple',
        'name': 'Arjun',
        'status': 'active',
        'isSubscriptionActive': true,
      }, 'org1'),
    ];
    orgs.lastReceived.value = now;
    final trainers = Get.put<TrainerController>(_Trainers(), permanent: true);
    trainers.trainers.value = [
      TrainerModel.fromMap({
        'name': 'Priya',
        'status': 'active',
        'assignedBy': 'org1',
      }, 't1'),
      TrainerModel.fromMap({
        'name': 'Gone',
        'status': 'removed',
        'isDeleted': true,
        'assignedBy': 'org1',
      }, 't2'),
    ];
    trainers.lastReceived.value = now;

    c = _Members();
    Get.put<ClientController>(c, permanent: true);
    final future = now.add(const Duration(days: 30)).toIso8601String();
    final soon = now.add(const Duration(days: 3)).toIso8601String();
    final past = now.subtract(const Duration(days: 10)).toIso8601String();
    c.clients.value = [
      m('a', {
        'membershipActive': true,
        'membershipExpiry': future,
        'trainerId': 't1',
        'lastActivityAt': now.subtract(const Duration(days: 1)),
      }),
      m('b', {'membershipActive': true, 'membershipExpiry': soon}),
      m('c', {'membershipActive': true, 'membershipExpiry': past}), // flag lags
      m('d', {'membershipActive': false}), // no membership, owner-coached
      m('e', {
        'membershipActive': true,
        'membershipFrozen': true,
        'membershipExpiry': future,
      }),
      m('f', {
        'membershipActive': true,
        'membershipExpiry': future,
        'trainerId': 't2',
      }), // removed coach
      m('g', {
        'membershipActive': true,
        'membershipExpiry': future,
        'lastActivityAt': now.subtract(const Duration(days: 60)),
      }), // dormant
      m('h', {'authUid': '', 'membershipActive': false}), // never claimed
      m('i', {
        'createdAt': now.subtract(const Duration(days: 2)),
        'membershipActive': true,
        'membershipExpiry': future,
      }), // recent
      m('z', {
        'isDeleted': true,
        'membershipActive': true,
        'membershipExpiry': future,
      }),
    ];
  });

  tearDown(Get.reset);

  test('every tile count equals the rows its filter shows', () {
    for (final key in MemberLanguage.filterKeys) {
      c.selectedFilter.value = key;
      expect(c.filteredClients.length, c.countFor(key), reason: key);
    }
  });

  test('the total excludes soft-deleted rows, as the Dashboard does', () {
    expect(c.clients.length, 10);
    expect(c.totalCount, 9);
    expect(c.countFor('all'), 9);
    c.selectedFilter.value = 'all';
    expect(c.filteredClients.any((x) => x.docId == 'z'), isFalse);
  });

  test('the specific queues contain who they promise', () {
    Set<String> ids(String key) {
      c.selectedFilter.value = key;
      return c.filteredClients.map((x) => x.docId).toSet();
    }

    expect(ids('current'), {'a', 'b', 'f', 'g', 'i'});
    expect(ids('expiring'), {'b'});
    expect(ids('lapsed'), {'c', 'd', 'h'});
    expect(ids('frozen'), {'e'});
    expect(ids('ownerCoached'), {'b', 'c', 'd', 'e', 'g', 'h', 'i'});
    expect(ids('dormant'), {'g'});
    expect(ids('unlinked'), {'h'});
    expect(ids('recent'), {'i'});
    // c: flag lags · f: removed coach · g: dormant
    expect(ids('attention'), containsAll({'c', 'f', 'g'}));
    expect(ids('attention'), isNot(contains('a')));
  });

  test('the organization filter and search narrow the same list', () {
    c.orgFilter.value = 'org1';
    expect(c.filteredClients.length, 9);
    c.orgFilter.value = 'other';
    expect(c.filteredClients, isEmpty);
    c.orgFilter.value = 'all';
    c.search.value = 'Member a';
    expect(c.filteredClients.map((x) => x.docId), ['a']);
    c.search.value = 'iron';
    expect(c.filteredClients.length, 9);
    c.search.value = 'priya';
    expect(c.filteredClients.map((x) => x.docId), ['a']);
  });

  test('changing a filter resets paging and closes an open member', () {
    c.detailFactory = (id) => throw UnimplementedError();
    c.visibleCount.value = 150;
    c.selectedFilter.value = 'current';
    expect(c.visibleCount.value, ClientController.pageSize);
  });

  test(
    'a failed organization or trainer list is said, not shown as missing',
    () {
      final orgs = Get.find<AdminController>();
      orgs.loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.permission,
        message: 'denied',
      );
      expect(
        c.orgName(m('x', {'adminId': 'nope'})),
        'Organization unavailable',
      );
      final trainers = Get.find<TrainerController>();
      trainers.loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.permission,
        message: 'denied',
      );
      expect(
        c.coachLine(m('y', {'trainerId': 'ghost'})),
        'Coach unavailable (trainer list failed)',
      );
    },
  );

  test('org join words are honest about what is known', () {
    expect(c.orgName(c.byId('a')!), 'Iron Temple');
    final foreign = m('x', {'adminId': 'nope'});
    expect(c.orgName(foreign), 'Organization missing');
    expect(c.orgName(m('y', {'adminId': ''})), 'No organization');
    expect(c.coachLine(c.byId('a')!), 'Coach Priya');
    expect(c.coachLine(c.byId('f')!), 'Coach Gone (removed)');
    expect(c.coachLine(c.byId('d')!), 'Coached by the organization owner');
  });
}
