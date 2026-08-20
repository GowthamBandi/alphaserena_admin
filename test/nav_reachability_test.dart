// A FINISHED SCREEN THAT NOTHING CAN OPEN IS NOT SHIPPED.
//
// 🔴 THE DEFECT THIS GUARDS. `automation_screen.dart` (412 lines) and
// `engagement_intelligence_screen.dart` (857 lines) were complete, their
// backend callables — `listAutomationTriggers`, `setAutomationEnabled`,
// `getEngagementIntelligence` — were DEPLOYED LIVE to trainershq-f5ded, and
// neither screen had a `case` in `AdminRootController._buildPage` or an entry
// in the sidebar. Zero importers. The founder could not reach either one, and
// nothing in the build, the analyzer or the test suite said so: Dart does not
// warn about a file nobody imports.
//
// Three independent things must agree, and only a test can hold them together:
//   1. every screen file is routed,
//   2. every sidebar entry has a page, and
//   3. `maxIndex` matches both.
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

String _read(String path) => File(path).readAsStringSync();

void main() {
  final controller = _read('lib/controllers/admin_root_controller.dart');
  final shell = _read('lib/screens/admin_root_screen.dart');

  /// The `case N:` labels present in the page factory.
  Set<int> routedIndices() => RegExp(r'^\s*case (\d+):', multiLine: true)
      .allMatches(controller)
      .map((m) => int.parse(m.group(1)!))
      .toSet();

  /// The sidebar labels, in order — index N is the Nth entry.
  List<String> sidebarLabels() =>
      RegExp(r'_MenuItem\("([^"]+)"').allMatches(shell).map((m) => m.group(1)!).toList();

  int maxIndex() => int.parse(
      RegExp(r'final int maxIndex = (\d+);').firstMatch(controller)!.group(1)!);

  test('the extractors find something — otherwise the suite is vacuous', () {
    expect(routedIndices(), isNotEmpty);
    expect(sidebarLabels(), isNotEmpty);
    expect(sidebarLabels().first, 'Dashboard');
  });

  test('every sidebar entry has a page, and every page has a sidebar entry',
      () {
    final labels = sidebarLabels();
    final routed = routedIndices();
    final expected = {for (var i = 0; i < labels.length; i++) i};

    final unreachable = expected.difference(routed);
    expect(unreachable, isEmpty,
        reason: 'sidebar entries with no page: '
            '${unreachable.map((i) => labels[i]).toList()}');

    final orphanPages = routed.difference(expected);
    expect(orphanPages, isEmpty,
        reason: 'page cases nothing in the sidebar can select: $orphanPages');
  });

  test('maxIndex matches the last sidebar entry', () {
    // A maxIndex BELOW the last entry makes changePage() silently refuse the
    // tap; ABOVE it lets currentPage fall through to `default` and render a
    // blank SizedBox. Both look like a dead nav item.
    expect(maxIndex(), sidebarLabels().length - 1);
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

  test('the two screens this defect was found on are reachable', () {
    // Named explicitly so a future refactor cannot regress them quietly by
    // widening the allowlist above.
    expect(controller, contains('screens/automation_screen.dart'));
    expect(controller, contains('screens/engagement_intelligence_screen.dart'));
    expect(sidebarLabels(), contains('Automation'));
    expect(sidebarLabels(), contains('Engagement'));
  });
}
