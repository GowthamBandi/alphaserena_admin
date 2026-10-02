// MEMBERS IS READ-ONLY, AND THREE SAFEGUARDS ARE STRUCTURAL.
//
// The rules deny the founder every write to `clients` and to all member
// activity collections (trainershq-backend/firestore.rules, verified
// 2026-09-24). The previous Members code nonetheless carried create / update /
// delete methods that the rules refused — dead code that would have returned
// permission-denied in production and was one careless revert from being
// wired to a button again. These source guards make the invariants fail
// loudly if they are reintroduced. Comments are stripped before matching so an
// explanatory comment can neither satisfy nor trip a guard.
//
//   1. No Firestore write API is reachable from the Members controllers.
//   2. The Members screens offer no create / edit / delete affordance.
//   3. `client_progress` is queried WITH the shared-visibility constraint the
//      rules require — the founder may not read private entries, and a broad
//      query relying on UI filtering would be denied outright.
//   4. Soft-deleted records match no filter, so they inflate no count.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String source) {
  final noBlock = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

String _read(String p) => _strip(File(p).readAsStringSync());

const _controllers = [
  'lib/controllers/client_controller.dart',
  'lib/controllers/member_detail_controller.dart',
];

const _screens = [
  'lib/screens/clients_screen.dart',
  'lib/screens/member/member_workspace.dart',
];

/// Firestore write surface, as regexes so a plain `List.add(...)` or
/// `Get.delete<T>(...)` cannot trip the guard.
final _writeApis = <RegExp>[
  RegExp(r'\.update\('),
  RegExp(r'\.set\('),
  RegExp(r'\.delete\(\)'),
  RegExp(r'\.add\(\{'),
  RegExp(r'FieldValue\.'),
  RegExp(r'WriteBatch'),
  RegExp(r'runTransaction'),
  RegExp(r'httpsCallable'),
];

void main() {
  test('the Members controllers reach no Firestore write API', () {
    for (final p in _controllers) {
      final s = _read(p);
      for (final api in _writeApis) {
        expect(api.hasMatch(s), isFalse, reason: '$p matches $api');
      }
    }
  });

  test('the Members screens offer no create / edit / delete affordance', () {
    for (final p in _screens) {
      final s = _read(p);
      for (final word in const [
        'createClient',
        'updateClient',
        'deleteClient',
        'toggleActive',
        'toggleVerified',
        "'Delete'",
        "'Edit member'",
        "'New member'",
        "'Add member'",
        'FloatingActionButton',
      ]) {
        expect(s.contains(word), isFalse, reason: '$p contains $word');
      }
    }
  });

  test('client_progress is queried with the shared-visibility constraint', () {
    final s = _read('lib/controllers/member_detail_controller.dart');
    final i = s.indexOf("collection('client_progress')");
    expect(i, greaterThan(-1), reason: 'the progress feed must exist');
    // The constraint must be on the SAME query, before it is executed.
    final query = s.substring(i, s.indexOf('.get()', i));
    expect(
      query.contains(".where('visibility', isEqualTo: 'shared')"),
      isTrue,
      reason: 'a broad client_progress read is denied by the rules',
    );
  });

  test('soft-deleted records are excluded before any filter is evaluated', () {
    final s = _read('lib/core/services/member_language.dart');
    final i = s.indexOf('static bool matchesFilter(');
    expect(i, greaterThan(-1));
    final body = s.substring(
      i,
      s.indexOf('static const List<String> sortKeys'),
    );
    expect(body.contains('if (m.isDeleted) return false;'), isTrue);
  });

  test(
    'the directory never streams with an orderBy (it would drop undated rows)',
    () {
      final s = _read('lib/controllers/client_controller.dart');
      expect(s.contains('.orderBy('), isFalse);
    },
  );

  test('CONTROL: the stripper removes comments', () {
    expect(
      _strip('a // .update(\n/* .delete( */ b'),
      isNot(contains('.update(')),
    );
    expect(
      _strip('a // .update(\n/* .delete( */ b'),
      isNot(contains('.delete(')),
    );
  });
}
