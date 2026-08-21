// A FINISHED SCREEN THAT NOTHING CAN OPEN IS NOT SHIPPED.
//
// 🔴 THE ORIGINAL DEFECT. `automation_screen.dart` (412 lines) and
// `engagement_intelligence_screen.dart` (857 lines) were complete, their
// backend callables — `listAutomationTriggers`, `setAutomationEnabled`,
// `getEngagementIntelligence` — were DEPLOYED LIVE to trainershq-f5ded, and
// neither screen had a `case` in `AdminRootController._buildPage` or an entry
// in the sidebar. Zero importers. The founder could not reach either one, and
// nothing in the build, the analyzer or the test suite said so: Dart does not
// warn about a file nobody imports.
//
// 🔴 THE SECOND DEFECT, WHICH THIS FILE NOW ALSO GUARDS. The sidebar used to BE
// the navigation model — a flat `_MenuItem` list whose POSITION was the page
// index. That coupled three unrelated things into one integer: what the founder
// sees, the order they see it in, and which page opens. It is why the sidebar
// was ordered by when each screen was built rather than by how a founder works,
// and why fixing the order was considered too dangerous to attempt: other
// controllers jump to LITERAL indices (`OperationsController._navAdmins = 1`,
// the dashboard's `opsNavIndex = 10`), so renumbering would have silently
// repointed alerts at the wrong screen — no compile error, no visible symptom.
//
// The model now lives in `lib/core/navigation/console_destinations.dart`, where
// `ConsoleDestination.id` is a stable identity and `kConsoleSections` decides
// display order and grouping independently. That is strictly safer, but only if
// the two are held together by a test. Four things must agree:
//
//   1. every destination id has a page,
//   2. every page case has a destination,
//   3. `maxIndex` covers the highest id (clamp() must not strand one),
//   4. every cross-screen jump literal still lands on the screen it names.
//
// (4) is new, and it is the specific hazard the refactor introduced. It is
// asserted by NAME, not by number, so a future reorder cannot quietly satisfy
// it.
//
// If a screen is deliberately unrouted, add it to [_notInTheSidebar] with the
// reason. That is the point — it makes "unreachable" a decision somebody wrote
// down, not an accident nobody noticed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens that legitimately have no sidebar entry.
const _notInTheSidebar = <String, String>{
  'admin_root_screen.dart': 'the shell that HOSTS the sidebar',
  'top_nav_bar.dart': 'chrome, not a page',
  'auth/admin_login_screen.dart': 'pre-session; RootGate shows it',
  'auth/forgot_password_dialog.dart': 'a dialog raised from the login screen',
  'legal/legal_screen.dart': 'opened from the profile menu, not the sidebar',
};

/// Cross-screen jump targets: the constant, and the destination label it is
/// documented to open. Asserted by LABEL so a reorder cannot satisfy it by
/// coincidence.
const _jumpTargets = <String, String>{
  '_navAdmins': 'Organizations',
  '_navPayments': 'Revenue',
  '_navSupport': 'Support',
  '_navCommunication': 'Announcements',
  'opsNavIndex': 'Operations Center',
};

String _read(String path) => File(path).readAsStringSync();

void main() {
  final controller = _read('lib/controllers/admin_root_controller.dart');
  final destinations = _read('lib/core/navigation/console_destinations.dart');
  final operations = _read('lib/controllers/operations_controller.dart');
  final dashboard = _read('lib/screens/dash_board_responsive_screen.dart');

  /// The `case N:` labels present in the page factory.
  Set<int> routedIndices() => RegExp(r'^\s*case (\d+):', multiLine: true)
      .allMatches(controller)
      .map((m) => int.parse(m.group(1)!))
      .toSet();

  /// Every declared destination, as (id, label), in sidebar order.
  List<({int id, String label})> declaredDestinations() =>
      RegExp(r'id:\s*(\d+),\s*\n\s*label:\s*'"'"'([^'"'"']+)'"'"'')
          .allMatches(destinations)
          .map((m) => (id: int.parse(m.group(1)!), label: m.group(2)!))
          .toList();

  /// Section titles, in order.
  List<String> sectionTitles() =>
      RegExp(r"title:\s*'([^']+)',\s*\n\s*destinations:")
          .allMatches(destinations)
          .map((m) => m.group(1)!)
          .toList();

  int maxIndex() => int.parse(
      RegExp(r'final int maxIndex = (\d+);').firstMatch(controller)!.group(1)!);

  test('the extractors find something — otherwise the suite is vacuous', () {
    expect(routedIndices(), isNotEmpty);
    expect(declaredDestinations(), isNotEmpty);
    expect(sectionTitles(), isNotEmpty);
    // The first thing a founder sees must still be the Dashboard.
    expect(declaredDestinations().first.label, 'Dashboard');
    expect(sectionTitles().first, 'Command Center');
  });

  test('every destination has a page, and every page has a destination', () {
    final declared = {for (final d in declaredDestinations()) d.id};
    final routed = routedIndices();

    final unreachable = declared.difference(routed);
    expect(unreachable, isEmpty,
        reason: 'sidebar destinations with no page case: $unreachable');

    final orphanPages = routed.difference(declared);
    expect(orphanPages, isEmpty,
        reason: 'page cases nothing in the sidebar can select: $orphanPages');
  });

  test('destination ids are unique', () {
    // Two destinations sharing an id renders two sidebar rows that open the
    // same page — and both would light up as selected together.
    final ids = declaredDestinations().map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: 'duplicate destination ids in kConsoleSections: $ids');
  });

  test('maxIndex covers the highest destination id', () {
    // changePage() clamps to maxIndex. BELOW the highest id, that destination
    // silently opens a different page; ABOVE it, currentPage falls through to
    // `default` and renders a blank SizedBox. Both look like a dead nav item.
    //
    // Note this is deliberately NOT `== length - 1` any more: ids are identity,
    // not position, so the highest id is what clamp() must reach.
    final highest =
        declaredDestinations().map((d) => d.id).reduce((a, b) => a > b ? a : b);
    expect(maxIndex(), greaterThanOrEqualTo(highest));
  });

  test('every screen file is routed, or documented as deliberately not', () {
    final files = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceFirst('lib/screens/', ''))
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();

    // A file counts as routed if the page factory imports it.
    final unrouted = files
        .where((p) => !controller.contains('screens/$p'))
        .where((p) => !_notInTheSidebar.containsKey(p))
        .toList();

    expect(unrouted, isEmpty,
        reason: 'built but unreachable — route them, or add them to '
            '_notInTheSidebar with the reason: $unrouted');
  });

  test('cross-screen jump literals still land on the screen they name', () {
    // THE HAZARD THE GROUPED SIDEBAR INTRODUCED. These constants are raw ints
    // in other files. If someone renumbers a destination id to reorder the
    // sidebar — the exact thing the new model exists to make unnecessary — an
    // alert about a lapsed subscription would open Coupons, and nothing would
    // fail to compile.
    final byLabel = {for (final d in declaredDestinations()) d.label: d.id};

    for (final entry in _jumpTargets.entries) {
      final constant = entry.key;
      final expectedLabel = entry.value;

      final source = constant == 'opsNavIndex' ? dashboard : operations;
      final match =
          RegExp('$constant\\s*=\\s*(\\d+)').firstMatch(source);
      expect(match, isNotNull,
          reason: '$constant no longer exists — if the jump was removed, '
              'remove it from _jumpTargets too');

      final value = int.parse(match!.group(1)!);
      expect(byLabel.containsKey(expectedLabel), isTrue,
          reason: 'the destination "$expectedLabel" that $constant targets no '
              'longer exists; retarget the jump, do not delete this assertion');
      expect(value, byLabel[expectedLabel],
          reason: '$constant = $value, but "$expectedLabel" is id '
              '${byLabel[expectedLabel]}. A founder following this alert would '
              'land on the wrong screen.');
    }
  });

  test('the two screens this defect was found on are reachable', () {
    // Named explicitly so a future refactor cannot regress them quietly by
    // widening the allowlist above.
    expect(controller, contains('screens/automation_screen.dart'));
    expect(controller, contains('screens/engagement_intelligence_screen.dart'));
    final labels = declaredDestinations().map((d) => d.label).toSet();
    expect(labels, contains('Automation'));
    expect(labels, contains('Intelligence'));
  });

  test('every destination carries a purpose line', () {
    // The purpose is the sidebar tooltip AND the screen-reader hint. A blank
    // one leaves a screen reader announcing a bare noun with no way to tell
    // "Revenue" (our income) from "Settlements" (somebody else's money).
    final purposes = RegExp(r"purpose:\s*'([^']*)'")
        .allMatches(destinations)
        .map((m) => m.group(1)!)
        .toList();

    expect(purposes.length, declaredDestinations().length,
        reason: 'a destination is missing its purpose: line');
    for (final p in purposes) {
      expect(p.trim(), isNotEmpty);
    }
  });
}
