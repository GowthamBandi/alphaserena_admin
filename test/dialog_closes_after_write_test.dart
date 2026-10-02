// A GETX SNACKBAR IS A ROUTE, SO IT SWALLOWS THE `Get.back()` MEANT FOR THE DIALOG.
//
// 🔴 THE DEFECT THIS GUARDS (observed 2026-09-09 against the emulator, in the
// Superadmin ↔ Trainersarena end-to-end run). `SupportController.respond` raised
// its success snackbar itself, and `_ReplyDialog._submit` then called
// `Get.back()`. `Get.back()` pops the TOP route — which by then was the
// snackbar. Result, all three surfaces verified:
//
//   • the reply COMMITTED (`org_feedback` carried superAdminResponse,
//     respondedBy, respondedAt, status: resolved),
//   • the organization SAW it in Trainersarena ("Resolved · Support reply …"),
//   • and the founder was left staring at an open dialog with their text still
//     in it, no confirmation, and every reason to press the button again.
//
// "Can I tell whether it succeeded?" is the question this console exists to
// answer, and on this screen the answer was no.
//
// THE RULE, which two other controllers already state in prose:
//   `global_exercise_controller.save`  — "the success snackbar is a GetX ROUTE.
//        Pushing it first would make the caller's Get.back() pop the TOAST"
//   `communication_controller.submit`  — "showing it here … made Get.back() pop
//        the snackbar instead of the dialog, so the dialog never closed"
//
// A rule written twice in comments and broken a third time is a rule that needs
// a test. So: a controller mutation that a dialog closes on must NOT raise its
// own SUCCESS snackbar. It returns a result; the CALLER pops, then reports.
// Failure snackbars are fine — the caller keeps the dialog open on failure, so
// nothing is waiting to be popped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Comments are stripped before matching. A previous source guard in this
/// ecosystem stayed red because the FIX's own explanatory comment still
/// contained the banned token.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        if (i < 0) return l;
        // Keep anything before the comment marker so real code on the same
        // line still counts.
        return l.substring(0, i);
      })
      .join('\n');
}

final _snackbar = RegExp(r'(AppSnackbar\.show|Get\.snackbar|Get\.rawSnackbar)\s*\(');
final _methodDecl = RegExp(r'Future<[^>]*>\s+(\w+)\s*\(');

/// Every controller method that raises a snackbar on a path that is NOT inside
/// a `catch`. Keyed `file::method`, valued by the method name alone (call
/// sites do not name the file).
Set<String> _methodsThatSnackbarOnSuccess() {
  final names = <String>{};
  final dir = Directory('lib/controllers');
  if (!dir.existsSync()) return names;

  for (final f in dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final lines = _stripComments(f.readAsStringSync()).split('\n');

    String? current;
    var depth = 0;
    var sawCatch = false;

    for (final raw in lines) {
      final line = raw;
      final decl = _methodDecl.firstMatch(line);
      if (decl != null && depth <= 1) {
        current = decl.group(1);
        sawCatch = false;
      }
      // Everything from the first catch clause onward is a FAILURE path, and a
      // failure snackbar is fine (the caller keeps its dialog open). Must match
      // `} catch (e) {` AND `} on SomeException catch (e) {` — missing the
      // second form made an earlier draft of this guard report every method
      // that merely reports its own errors.
      if (RegExp(r'\bcatch\s*\(|\}\s*on\s+\w').hasMatch(line)) {
        sawCatch = true;
      }
      if (current != null && !sawCatch && _snackbar.hasMatch(line)) {
        names.add(current);
      }
      depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
      if (depth <= 0) {
        current = null;
        sawCatch = false;
      }
    }
  }
  return names;
}

void main() {
  test(
    'a dialog never closes with Get.back() right after awaiting a controller '
    'method that raises its own success snackbar',
    () {
      final risky = _methodsThatSnackbarOnSuccess();
      // The guard is only meaningful if it found something to guard against.
      expect(
        risky,
        isNotEmpty,
        reason: 'the scanner found no snackbar-raising controller methods at '
            'all — it has stopped measuring anything',
      );

      final offenders = <String>[];

      for (final dirName in const ['lib/screens', 'lib/widgets']) {
        final dir = Directory(dirName);
        if (!dir.existsSync()) continue;
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final lines = _stripComments(f.readAsStringSync()).split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (!RegExp(r'\bGet\.back\s*\(').hasMatch(lines[i])) continue;
            // Walk back over the statements that led here. A `return` between
            // the await and the pop means the pop is on a different path.
            for (var j = i - 1; j >= 0 && j >= i - 10; j--) {
              final prev = lines[j];
              if (RegExp(r'\breturn\b').hasMatch(prev)) break;
              final call = RegExp(r'await\s+[\w.]*\.(\w+)\s*\(').firstMatch(prev);
              if (call == null) continue;
              final method = call.group(1)!;
              if (risky.contains(method)) {
                offenders.add(
                  '$dirName/${f.uri.pathSegments.last}:${i + 1}  '
                  'Get.back() after await …$method(…) — $method raises its own '
                  'success snackbar, and Get.back() will pop THAT instead of '
                  'this dialog',
                );
              }
              break;
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these dialogs will not close on success:\n'
            '${offenders.join('\n')}\n\n'
            'Fix by returning a result from the controller and letting the '
            'caller pop first, then report — see SupportController.respond.',
      );
    },
  );

  test(
    'SupportController.respond and setResolved report success to their caller '
    'instead of raising it themselves',
    () {
      final src = _stripComments(
        File('lib/controllers/support_controller.dart').readAsStringSync(),
      );

      // They must hand a result back, or the dialog cannot know whether to
      // close and whether to keep the operator's typed reply.
      expect(src, contains('Future<bool> respond('));
      expect(src, contains('Future<bool> setResolved('));

      // And the screen must pop before it reports.
      final screen = _stripComments(
        File('lib/screens/support_screen.dart').readAsStringSync(),
      );
      final back = screen.indexOf('Get.back();');
      final toast = screen.indexOf('AppSnackbar.show(');
      expect(back, greaterThan(-1));
      expect(toast, greaterThan(-1));
      expect(
        back,
        lessThan(toast),
        reason: 'the first Get.back() must come before the first success '
            'snackbar in support_screen.dart',
      );
    },
  );
}
