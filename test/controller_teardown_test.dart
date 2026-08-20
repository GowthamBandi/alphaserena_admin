// A CONSOLE CONTROLLER MUST NOT OUTLIVE THE SESSION THAT CREATED IT.
//
// 🔴 THE DEFECT THIS GUARDS. `MasterAdminBootstrap.dispose` tears the console
// down on logout, and says why:
//
//     "Tear down every console controller so streams close and a later
//      sign-in boots from clean state instead of inheriting cached data."
//
// `_teardownConsoleControllers` deletes twelve. But four controllers are
// registered by SCREENS rather than by the bootstrap — `Get.put(...)` in
// `payments_screen`, `global_food_screen`, `global_exercise_screen` and
// `billing_config_dialog` — and none of those four is in the teardown list.
//
// The worst is `PaymentsController`: it holds a `StreamSubscription` on
// `admin_payments_history` (every subscription payment the platform has ever
// taken) and cancels it in `onClose`. `onClose` runs on `Get.delete`. Nothing
// deletes it, so the listener stays open across sign-out, and the next sign-in
// re-uses the same instance with the previous session's rows already in it —
// the exact "inheriting cached data" the contract above exists to prevent.
//
// This guard reads the source rather than the runtime because that is where
// the mismatch lives: the registration and the teardown are two lists that
// have to agree, and nothing else makes them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Controllers that deliberately OUTLIVE the console subtree, with the reason.
/// They are registered outside `MasterAdminBootstrap` and are what the login
/// gate itself runs on — deleting them on logout would tear down the screen
/// doing the logging out.
const _deliberatelyPermanent = <String, String>{
  'SessionController': 'the auth gate itself; it is what OBSERVES the logout',
  'AdminLoginController': 'pre-session; owned by the login screen, not the console',
};

void main() {
  final main = File('lib/main.dart').readAsStringSync();

  Set<String> registeredInBootstrap() => RegExp(r'_safePut\((\w+)\(\)\)')
      .allMatches(main)
      .map((m) => m.group(1)!)
      .toSet();

  Set<String> tornDown() => RegExp(r'_safeDelete<(\w+)>\(\)')
      .allMatches(main)
      .map((m) => m.group(1)!)
      // `_safeDelete<T>()` is the generic's own declaration, not a call.
      .where((t) => t != 'T')
      .toSet();

  /// Every controller anything registers — the bootstrap's `_safePut` and the
  /// screens' direct `Get.put` alike. Both create an instance GetX keeps.
  Set<String> registeredAnywhere() {
    final out = <String>{...registeredInBootstrap()};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m
          in RegExp(r'Get\.put(?:<\w+>)?\((\w+)\(\)').allMatches(f.readAsStringSync())) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  test('the extractors find something — otherwise the suite is vacuous', () {
    expect(registeredInBootstrap(), isNotEmpty);
    expect(tornDown(), isNotEmpty);
    expect(registeredAnywhere(), contains('PaymentsController'));
  });

  test('every controller the console registers is also torn down', () {
    final leaked = registeredAnywhere()
        .where((c) => c.endsWith('Controller'))
        .where((c) => !_deliberatelyPermanent.containsKey(c))
        .where((c) => !tornDown().contains(c))
        .toList()
      ..sort();

    expect(leaked, isEmpty,
        reason: 'these survive logout, keeping their Firestore listeners open '
            'and their previous session\'s rows in memory. Add a '
            '_safeDelete<T>() to _teardownConsoleControllers, or add them to '
            '_deliberatelyPermanent with the reason: $leaked');
  });

  test('the teardown list has no entry for a controller nothing registers', () {
    // The other direction: a stale _safeDelete is harmless at runtime but means
    // the two lists have already drifted once.
    final orphans = tornDown().difference(registeredAnywhere()).toList()..sort();
    expect(orphans, isEmpty,
        reason: 'torn down but never registered: $orphans');
  });
}
