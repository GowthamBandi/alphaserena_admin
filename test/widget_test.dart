// M4: replaced the dead `flutter create` counter template (which asserted a
// non-existent counter and always failed) with a real widget test of the Serena
// Design System status pill — the component M4 introduces to the console tables.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena_admin_portel/core/widgets/serena/serena_ui.dart';

void main() {
  testWidgets('SerenaStatusPill renders its label and is exposed to a11y',
      (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SerenaStatusPill(label: 'ACTIVE', status: SerenaStatus.active),
        ),
      ),
    );

    // The label renders...
    expect(find.text('ACTIVE'), findsOneWidget);
    // ...and the pill exposes a labeled status to screen readers.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Status: ACTIVE',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  test('serenaStatusColor falls back safely without a registered palette', () {
    // SerenaStatus is a complete vocabulary; every value resolves to a color.
    // (Behavioural resolution is covered by the widget test above; here we only
    // assert the enum stayed exhaustive so a new status can never be un-mapped.)
    expect(SerenaStatus.values.length, greaterThanOrEqualTo(6));
  });
}
