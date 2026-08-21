import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A TAPPABLE MUST NEVER BE PUBLISHED WITHOUT ITS ACTION.
//
// Five controls in this console shipped as
//   Semantics(button: true, label: …, child: ExcludeSemantics(child: <tappable>))
// `ExcludeSemantics` strips the tappable's ACTION and its FOCUSABILITY out of
// the semantics tree, and the outer `Semantics` re-declared neither — so each
// was announced as a button that could not be pressed and could not be reached
// by keyboard. It was root-caused and fixed in exactly ONE of the six places
// (the Exercise Library tabs) and left in the other five, including
// `ConsoleChip`, which is THE filter control across Subscriptions, Support,
// Settlements and both content consoles.
//
// This is the sweep, kept as a test — the reported sites were fixed once
// before and the class came back. Comments are stripped before matching, so
// the explanatory comments the fix left behind (which necessarily NAME the
// widget) cannot satisfy or trip the guard.

String _stripComments(String source) {
  final noBlock = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

void main() {
  test('no ExcludeSemantics anywhere in lib/ (it strips tap + focus)', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = _stripComments(entity.readAsStringSync());
      if (!code.contains('ExcludeSemantics')) continue;

      final lines = code.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('ExcludeSemantics')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ExcludeSemantics removes the child subtree from the semantics tree, '
          'including a tappable\'s action and focusability. If you need a '
          'curated label, put it on the tappable itself (InkWell merges its '
          'child Text) rather than excluding the subtree and re-declaring a '
          'label with no action.\nOffending sites:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('CONTROL: the guard actually fires on the pattern it bans', () {
    const sample = '''
      Widget build(BuildContext c) {
        return Semantics(
          button: true,
          child: ExcludeSemantics(child: InkWell(onTap: f, child: t)),
        );
      }
    ''';
    expect(_stripComments(sample).contains('ExcludeSemantics'), isTrue);
  });

  test('CONTROL: a comment naming the widget does NOT trip the guard', () {
    const commented = '''
      // This used to be ExcludeSemantics(...) and was fixed.
      /* ExcludeSemantics in a block comment too */
      Widget build(BuildContext c) => InkWell(onTap: f, child: t);
    ''';
    expect(_stripComments(commented).contains('ExcludeSemantics'), isFalse);
  });
}
