// THE SIDEBAR MUST ACTUALLY RENDER WHAT THE MODEL DECLARES.
//
// `nav_reachability_test.dart` is a SOURCE test — it reads
// console_destinations.dart and admin_root_controller.dart as text and proves
// the ids line up. That catches an unrouted screen, but it cannot catch a
// sidebar that declares seven sections and draws none of them, or a tile that
// renders but does not change the page.
//
// So this file drives the real shell. It is the second half of the pair, and
// the two are deliberately different KINDS of evidence: one reads the model,
// the other watches the widget tree.
//
// 🔴 THE SPECIFIC REGRESSION IT WATCHES FOR. The grouped sidebar flattens
// sections and destinations into ONE list for a single virtualising
// ListView.builder. That flattening is exactly the kind of index arithmetic
// that silently drops the first or last row, or renders a header where a tile
// belongs — and with `itemCount` computed from the flattened length, an
// off-by-one produces no exception, just a missing destination.

import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/navigation/console_destinations.dart';
import 'package:alphaserena_admin_portel/core/theme/app_theme.dart';
import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// The real controller with its auth listener suppressed — everything about
/// navigation is real, only the Firebase binding is not.
class _OfflineRoot extends AdminRootController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// The sidebar footer reads the signed-in email from here. Only `onInit` (the
/// Firebase token listener) is suppressed; the observable state is real.
class _OfflineSession extends SessionController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Pumps the REAL `ConsoleSidebar`, at the width the desktop shell gives it.
///
/// The full `AdminRootScreen` is deliberately NOT used: it builds the selected
/// page, which would drag in every page controller and turn a navigation test
/// into an integration test that fails for unrelated reasons. The sidebar
/// itself is production code, imported, not reconstructed.
Future<_OfflineRoot> _pumpSidebar(WidgetTester tester, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Get.put<SessionController>(_OfflineSession(), permanent: true);
  final ctrl = Get.put<AdminRootController>(_OfflineRoot(), permanent: true);

  await tester.pumpWidget(GetMaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(
      body: SizedBox(width: 260, child: ConsoleSidebar()),
    ),
  ));
  await tester.pumpAndSettle();
  return ctrl as _OfflineRoot;
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  testWidgets('every declared destination is rendered, exactly once',
      (tester) async {
    await _pumpSidebar(tester);

    for (final d in kConsoleDestinations) {
      expect(find.text(d.label), findsOneWidget,
          reason: '"${d.label}" (id ${d.id}) is declared but not rendered — '
              'the section flattening dropped it');
    }
  });

  testWidgets('every section header is rendered', (tester) async {
    await _pumpSidebar(tester);

    for (final s in kConsoleSections) {
      expect(find.text(s.title.toUpperCase()), findsOneWidget,
          reason: 'section "${s.title}" has destinations but no header');
    }
  });

  testWidgets('tapping a destination selects ITS id, not its position',
      (tester) async {
    // The whole point of the refactor. "Access Requests" is the 4th row a
    // founder sees but page 17; a sidebar that still used position would
    // navigate to 3 (Members) and look almost right.
    //
    // `changePage` also CONSTRUCTS the destination page and caches it, and
    // those pages resolve their controllers with `Get.find` — so in this
    // harness, which registers only the navigation controllers, the page build
    // throws after the index has already moved. That is production behaviour
    // (main.dart registers every page controller permanently, pinned by
    // controller_teardown_test.dart), and it is drained deliberately below
    // rather than papered over: what is under test here is the id the tap
    // selects, not whether an unregistered page can be built.
    final ctrl = await _pumpSidebar(tester);
    expect(ctrl.selectedIndex.value, 0);

    Future<void> tapAndExpect(String label, int expectedId) async {
      await tester.tap(find.text(label));
      await tester.pump();
      final thrown = tester.takeException();
      if (thrown != null) {
        expect(thrown.toString(), contains('not found'),
            reason: 'tapping "$label" threw something other than an '
                'unregistered page controller: $thrown');
      }
      expect(ctrl.selectedIndex.value, expectedId,
          reason: 'tapping "$label" must select id $expectedId, not its row '
              'position');
    }

    await tapAndExpect('Access Requests', 17);
    await tapAndExpect('Settlements', 14);
    await tapAndExpect('Organizations', 1);
  });

  testWidgets('changePage refuses an id above maxIndex', (tester) async {
    // clamp() is what stands between a mistyped id and a blank page. Proven
    // here rather than assumed, because the maxIndex invariant moved when ids
    // stopped being positions.
    final ctrl = await _pumpSidebar(tester);
    ctrl.changePage(999);
    await tester.pump();
    expect(ctrl.selectedIndex.value, lessThanOrEqualTo(ctrl.maxIndex));
  });

  testWidgets('every destination is reachable by its accessible label',
      (tester) async {
    // A sighted founder finds a row by reading it; a screen-reader user finds
    // it by its Semantics label. Those are two different strings unless
    // something asserts they are the same one.
    final handle = tester.ensureSemantics();
    await _pumpSidebar(tester);

    for (final d in kConsoleDestinations) {
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(d.label)}\$')),
        findsOneWidget,
        reason: '"${d.label}" has no matching accessible label',
      );
    }
    handle.dispose();
  });

  test('the model itself is coherent', () {
    // Cheap invariants that do not need a widget tree, kept here so the whole
    // navigation contract is readable in one file.
    expect(kConsoleSections, isNotEmpty);
    for (final s in kConsoleSections) {
      expect(s.destinations, isNotEmpty,
          reason: 'section "${s.title}" would render a header over nothing');
      expect(s.title.trim(), isNotEmpty);
    }

    final ids = kConsoleDestinations.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate destination id');

    for (final d in kConsoleDestinations) {
      expect(d.label.trim(), isNotEmpty);
      expect(d.purpose.trim(), isNotEmpty,
          reason: '"${d.label}" has no purpose line to show or announce');
      expect(destinationForId(d.id), same(d),
          reason: 'destinationForId(${d.id}) does not resolve to ${d.label}');
    }

    expect(destinationForId(9999), isNull);
  });
}
