import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A TAPPABLE MUST NEVER BE PUBLISHED WITHOUT ITS ACTION.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE DEFECT CLASS
// ─────────────────────────────────────────────────────────────────────────────
// Five controls in this console shipped as
//   Semantics(button: true, label: …, child: ExcludeSemantics(child: <tappable>))
// Excluding the subtree strips the tappable's ACTION and its FOCUSABILITY out of
// the semantics tree, and the outer `Semantics` re-declared neither — so each
// was announced as a button that could not be pressed and could not be reached
// by keyboard. It was root-caused and fixed in exactly ONE of six places and
// left in the other five, including `ConsoleChip`, THE filter control across
// Subscriptions, Support, Settlements and both content consoles.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS GUARD IS STRUCTURAL AND NOT A BANNED STRING
// ─────────────────────────────────────────────────────────────────────────────
// The first version banned the literal `ExcludeSemantics` anywhere in lib/.
// That is wrong in BOTH directions, and each direction cost a real defect:
//
//   FALSE NEGATIVE. It never saw `excludeSemantics: true`, the PARAMETER form —
//   which is the form the sidebar tile used. `_SidebarTile` announced eighteen
//   rows as buttons while exposing no tap action at all, and a pointer-tap
//   widget test stayed green throughout because a pointer tap does not go
//   through the semantics tree. Caught by `console_sidebar_test.dart`, which
//   asserts SemanticsAction.tap is PRESENT.
//
//   FALSE POSITIVE. It forbids the legitimate use. `SerenaStatusPill`
//   (`core/widgets/serena/serena_ui.dart`) has no InkWell, no GestureDetector
//   and no onTap — its subtree is a decorative dot and a Text that merely
//   repeats the label. Excluding it removes a DOUBLE ANNOUNCEMENT ("Paused
//   Paused") and loses nothing. The member app's twin already does this.
//
// So the string is not the defect. The rule is:
//
//   A `Semantics` that excludes its subtree must not contain a tappable in that
//   subtree — UNLESS it re-declares the action itself.
//
// That last clause is what makes the correct fix expressible. The sidebar tile
// is now `excludeSemantics: true` + `onTap: onTap` on the same Semantics: one
// clean node carrying label, hint, button role, selected state AND the action.
//
// Comments are stripped before matching, so the explanatory comments a fix
// leaves behind — which necessarily NAME the widget — can neither satisfy nor
// trip the guard. The stripper is self-checked below.

/// Anything that makes a subtree activatable.
const _tappables = <String>[
  'onTap:',
  'onPressed:',
  'onLongPress:',
  'InkWell(',
  'GestureDetector(',
  'TextButton(',
  'ElevatedButton(',
  'OutlinedButton(',
  'IconButton(',
];

/// Actions a `Semantics` can declare to REPLACE what it excluded.
const _declaredActions = <String>['onTap:', 'onLongPress:', 'onIncrease:'];

String stripComments(String source) {
  final noBlock = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

/// The balanced `(...)` block starting at the `(` that follows [openIdx].
/// Returns null if unbalanced (a partial file, or a paren inside a string we
/// did not model) — an unparseable block is skipped rather than guessed at.
String? _balancedBlock(String code, int openIdx) {
  final start = code.indexOf('(', openIdx);
  if (start == -1) return null;
  var depth = 0;
  for (var i = start; i < code.length; i++) {
    if (code[i] == '(') depth++;
    if (code[i] == ')') {
      depth--;
      if (depth == 0) return code.substring(start, i + 1);
    }
  }
  return null;
}

/// Argument names at depth 1 of a balanced block — i.e. the widget's OWN
/// parameters, not those of anything nested inside it.
Set<String> _topLevelArgs(String block) {
  final args = <String>{};
  var depth = 0;
  final buf = StringBuffer();
  for (var i = 0; i < block.length; i++) {
    final ch = block[i];
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') depth--;
    if (depth == 1) {
      if (ch == ':') {
        final name = buf.toString().trim().split(RegExp(r'[\s,(]')).last;
        if (name.isNotEmpty) args.add('$name:');
        buf.clear();
      } else if (ch == ',') {
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
  }
  return args;
}

/// Every site that removes its subtree from the semantics tree, as
/// (description, the block it governs).
List<({String where, String block, bool declaresAction})> _exclusionSites(
  String path,
  String code,
) {
  final sites = <({String where, String block, bool declaresAction})>[];

  // FORM 1 — the widget. It cannot declare a replacement action at all.
  for (final m in RegExp(r'ExcludeSemantics\s*\(').allMatches(code)) {
    final block = _balancedBlock(code, m.start);
    if (block == null) continue;
    final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
    sites.add((
      where: '$path:$line (ExcludeSemantics widget)',
      block: block,
      declaresAction: false,
    ));
  }

  // FORM 2 — the parameter. Governed by its enclosing `Semantics(`, which MAY
  // declare a replacement action.
  for (final m
      in RegExp(r'excludeSemantics\s*:\s*true').allMatches(code)) {
    final semIdx = code.lastIndexOf(RegExp(r'Semantics\s*\('), m.start);
    if (semIdx == -1) continue;
    final block = _balancedBlock(code, semIdx);
    if (block == null) continue;
    final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
    final args = _topLevelArgs(block);
    sites.add((
      where: '$path:$line (excludeSemantics: true)',
      block: block,
      declaresAction: _declaredActions.any(args.contains),
    ));
  }

  return sites;
}

List<String> offendersIn(String path, String rawSource) {
  final code = stripComments(rawSource);
  final offenders = <String>[];

  for (final site in _exclusionSites(path, code)) {
    if (site.declaresAction) continue; // action re-declared — correct usage
    final found = _tappables.where(site.block.contains).toList();
    if (found.isNotEmpty) {
      offenders.add('${site.where} → excludes ${found.join(", ")}');
    }
  }
  return offenders;
}

void main() {
  test('the stripper works — otherwise every assertion below is vacuous', () {
    const sample = '''
      // ExcludeSemantics(child: InkWell(onTap: f))
      /* excludeSemantics: true */
      final s = 'ExcludeSemantics in a string';
      Widget w = Text('hi');
    ''';
    final stripped = stripComments(sample);
    expect(stripped, isNot(contains('child: InkWell')));
    expect(stripped, isNot(contains('excludeSemantics: true')));
    expect(stripped, contains("Widget w = Text('hi');"));
  });

  test('no semantics exclusion hides a tappable without re-declaring it', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      offenders.addAll(offendersIn(entity.path, entity.readAsStringSync()));
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Excluding a subtree removes the tappable inside it from the '
          'semantics tree — its ACTION and its FOCUSABILITY go with it, so the '
          'control announces as a button that cannot be pressed and cannot be '
          'reached by keyboard.\n'
          'Either put the label on the tappable itself (InkWell merges its '
          'child Text), or keep the exclusion and re-declare the action on the '
          'same Semantics (onTap:).\nOffending sites:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  // ── CONTROLS. Each pins one direction the string-ban version got wrong. ────

  test('CONTROL: it FIRES on the widget form wrapping a tappable', () {
    const sample = '''
      Semantics(
        button: true,
        child: ExcludeSemantics(child: InkWell(onTap: f, child: t)),
      )
    ''';
    expect(offendersIn('sample.dart', sample), isNotEmpty);
  });

  test('CONTROL: it FIRES on the PARAMETER form — the false negative that '
      'let the sidebar ship eighteen unpressable buttons', () {
    const sample = '''
      Semantics(
        button: true,
        label: 'Dashboard',
        excludeSemantics: true,
        child: InkWell(onTap: onTap, child: Text('Dashboard')),
      )
    ''';
    expect(offendersIn('sample.dart', sample), isNotEmpty);
  });

  test('CONTROL: it ALLOWS an exclusion that re-declares the action', () {
    // The sidebar tile's shape after the fix: one node with the label, the
    // role AND the action.
    const sample = '''
      Semantics(
        button: true,
        label: 'Dashboard',
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(onTap: onTap, child: Text('Dashboard')),
      )
    ''';
    expect(offendersIn('sample.dart', sample), isEmpty);
  });

  test('CONTROL: it ALLOWS excluding a subtree with NO tappable — the false '
      'positive that made the legitimate fix un-shippable', () {
    // SerenaStatusPill: a decorative dot and a Text repeating the label.
    const sample = '''
      Semantics(
        label: 'Status: Paused',
        excludeSemantics: true,
        child: Row(children: [Icon(Icons.circle), Text('Paused')]),
      )
    ''';
    expect(offendersIn('sample.dart', sample), isEmpty);
  });

  test('CONTROL: a comment naming the widget does NOT trip the guard', () {
    const commented = '''
      // This used to be ExcludeSemantics(child: InkWell(onTap: f)) and was fixed.
      /* excludeSemantics: true wrapping GestureDetector( too */
      Widget build(BuildContext c) => InkWell(onTap: f, child: t);
    ''';
    expect(offendersIn('sample.dart', commented), isEmpty);
  });

  test('CONTROL: an onTap nested DEEPER does not count as re-declaration', () {
    // Only the Semantics' OWN arguments may satisfy the exclusion. An onTap
    // belonging to the excluded child is precisely what was lost.
    const sample = '''
      Semantics(
        button: true,
        excludeSemantics: true,
        child: Column(children: [InkWell(onTap: f, child: t)]),
      )
    ''';
    expect(offendersIn('sample.dart', sample), isNotEmpty);
  });
}
