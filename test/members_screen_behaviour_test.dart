// MEMBERS LIST — rendered from an offline controller. Pins: loading, error,
// empty and filtered-empty states; what a row says; that a tile is a real
// button that filters; that Open swaps in the workspace and Back returns; and
// that a soft-deleted record is invisible.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/client_controller.dart';
import 'package:alphaserena_admin_portel/controllers/member_detail_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/core/widgets/console/console_chrome.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/member/member_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

final now = DateTime(2026, 9, 24, 12);

class OfflineDetail extends MemberDetailController {
  OfflineDetail(super.memberId);
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineMembers extends ClientController {
  OfflineMembers() {
    clock = () => now;
    detailFactory = (id) {
      final d = OfflineDetail(id);
      d.member.value = byId(id);
      d.loading.value = false;
      d.notFound.value = byId(id) == null;
      d.lastReceived.value = now;
      return d;
    };
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

late OfflineMembers ctrl;

Future<void> pump(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: ClientsScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
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
    Get.put<TrainerController>(
      _Trainers(),
      permanent: true,
    ).lastReceived.value = now;
    ctrl = OfflineMembers();
    Get.put<ClientController>(ctrl, permanent: true);
  });
  tearDown(Get.reset);

  testWidgets('loading shows skeletons, never an empty state', (tester) async {
    ctrl.isLoading.value = true;
    await pump(tester);
    expect(find.byType(ConsoleSkeletonRow), findsWidgets);
    expect(find.byType(ConsoleEmptyState), findsNothing);
  });

  testWidgets('a failed stream shows the classified error, not "No members"', (
    tester,
  ) async {
    ctrl.loadError.value = const ConsoleError(
      kind: ConsoleErrorKind.permission,
      message: 'denied',
    );
    await pump(tester);
    expect(find.byType(ConsoleErrorState), findsOneWidget);
    expect(find.text('Not authorized'), findsOneWidget);
    expect(find.textContaining('No members'), findsNothing);
  });

  testWidgets('an empty platform says why', (tester) async {
    ctrl.lastReceived.value = now;
    await pump(tester);
    expect(find.text('No members yet'), findsOneWidget);
  });

  testWidgets(
    'rows say who, where, membership, coach; deleted rows are absent',
    (tester) async {
      ctrl.lastReceived.value = now;
      ctrl.clients.value = [
        m('a', {
          'membershipActive': true,
          'membershipExpiry': now
              .add(const Duration(days: 20))
              .toIso8601String(),
          'membership': {'planName': 'Gold'},
          'sharedProfile': {
            'identity': {'displayName': 'Sai Kumar'},
          },
        }),
        m('c', {
          'membershipActive': true,
          'membershipExpiry': now
              .subtract(const Duration(days: 10))
              .toIso8601String(),
        }),
        m('z', {'isDeleted': true}),
      ];
      await pump(tester);

      expect(find.text('Sai Kumar'), findsOneWidget);
      expect(find.text('Gold · ends in 20 days'), findsOneWidget);
      expect(find.text('Iron Temple'), findsWidgets);
      expect(find.text('Coached by the organization owner'), findsWidgets);
      expect(find.text('Member z'), findsNothing);
      // The lagging-flag member is called expired and flagged, not "ACTIVE".
      expect(
        find.text('Still marked active although the term ended'),
        findsOneWidget,
      );
      expect(find.textContaining('Expired 10 days ago'), findsOneWidget);
      // Header summary
      expect(find.textContaining('2 members ·'), findsOneWidget);
    },
  );

  testWidgets('a tile is a pressable button that filters; clearing restores', (
    tester,
  ) async {
    ctrl.lastReceived.value = now;
    ctrl.clients.value = [
      m('a', {
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      }),
      m('d', {'membershipActive': false}),
    ];
    await pump(tester);
    expect(find.text('Member a'), findsOneWidget);
    expect(find.text('Member d'), findsOneWidget);

    final tile = find.bySemanticsLabel(RegExp(r'^Expired or none: 1\.'));
    expect(tile, findsOneWidget);
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(tile);
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'a tile announced as a button must be pressable',
    );
    handle.dispose();

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Member a'), findsNothing);
    expect(find.text('Member d'), findsOneWidget);
    expect(
      find.textContaining('Showing 1 member: Expired or none'),
      findsOneWidget,
    );

    await tester.tap(find.text('Clear filters').first);
    await tester.pumpAndSettle();
    expect(find.text('Member a'), findsOneWidget);
  });

  testWidgets('a filter with no matches explains itself', (tester) async {
    ctrl.lastReceived.value = now;
    ctrl.clients.value = [
      m('a', {'membershipActive': false}),
    ];
    await pump(tester);
    ctrl.selectedFilter.value = 'frozen';
    await tester.pumpAndSettle();
    expect(find.text('No members match'), findsOneWidget);
  });

  testWidgets('Open swaps in the workspace; Back returns to the list', (
    tester,
  ) async {
    ctrl.lastReceived.value = now;
    ctrl.clients.value = [
      m('a', {'membershipActive': false}),
    ];
    await pump(tester);

    await tester.tap(find.bySemanticsLabel('Open member: Member a'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberWorkspace), findsOneWidget);
    expect(find.text('No membership on record'), findsWidgets);

    await tester.tap(find.text('All members'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberWorkspace), findsNothing);
    expect(find.text('Member a'), findsOneWidget);
  });

  testWidgets('phone width: the row stacks and nothing overflows', (
    tester,
  ) async {
    ctrl.lastReceived.value = now;
    ctrl.clients.value = [
      m('a', {
        'email': 'a.very.long.email.address.for.overflow@example-domain.in',
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      }),
    ];
    await pump(tester, width: 390);
    expect(tester.takeException(), isNull);
    expect(find.text('Member a'), findsOneWidget);
  });
}
