// THE CONSOLE MUST KEEP POINTING AT THE DOCUMENT THAT CHARGES MONEY.
//
// 🔴 THE DEFECT THIS GUARDS. The "Billing & taxes" editor wrote
// `platform_billing/config`. The billing engine has only ever priced from
// `platform_config/commerce` (`subscriptions.ts:loadTaxRules`). Two paths that
// never met — so the feature could not save (the collection is declared in no
// ruleset, and there is no wildcard fallback), and would not have applied any
// tax even if it could.
//
// A unit test on the model cannot catch a relapse here, because repointing the
// controller at a new collection keeps every arithmetic test green while
// silently detaching the editor from the money path again. So this asserts the
// wiring itself.
//
// ⚠️ WHY THE COMMENTS ARE STRIPPED FIRST. The controller's own documentation
// names `platform_billing` several times — explaining what went wrong is the
// reason that text exists. A naive substring search over the raw file would
// fail on the very comment that prevents the mistake, which is how a guard
// gets deleted for crying wolf. Only CODE is inspected.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Removes `//` line comments, `/* */` block comments and string literals.
///
/// String literals go too: the collection names appear inside them, and this
/// guard's whole job is to distinguish the constant the controller USES from
/// the prose around it. What remains is identifiers and structure.
String codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final rest = source.substring(i);
    if (rest.startsWith('//')) {
      final nl = source.indexOf('\n', i);
      i = nl == -1 ? source.length : nl;
      continue;
    }
    if (rest.startsWith('/*')) {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
      continue;
    }
    i++;
    out.write(source[i - 1]);
  }
  return out.toString();
}

/// The string literals in [source], with comments already removed.
List<String> literals(String code) {
  final out = <String>[];
  final re = RegExp(r"'([^'\\\n]*)'");
  for (final m in re.allMatches(code)) {
    out.add(m.group(1)!);
  }
  return out;
}

void main() {
  final controller = File(
    'lib/controllers/billing_config_controller.dart',
  ).readAsStringSync();
  final code = codeOnly(controller);
  final strings = literals(code);

  test('the comment stripper actually strips — this guard is self-checked', () {
    // If this breaks, every assertion below becomes vacuous.
    expect(
      controller,
      contains('platform_billing'),
      reason: 'the explanatory comments should still be there',
    );
    // The newline that terminated the comment survives, which is intended —
    // stripping it would join adjacent statements.
    expect(codeOnly('// x\nkeep;').trim(), 'keep;');
    expect(codeOnly('/* x */keep;'), 'keep;');
    expect(literals(codeOnly("// 'ghost'\nvar a = 'real';")), ['real']);
  });

  test('the controller reads the document the billing engine prices from', () {
    // subscriptions.ts: db.collection("platform_config").doc("commerce")
    expect(strings, contains('platform_config'));
    expect(strings, contains('commerce'));
  });

  test('the orphaned platform_billing path is gone from the CODE', () {
    expect(
      strings,
      isNot(contains('platform_billing')),
      reason: 'the editor is detached from the money path again',
    );
    expect(
      strings,
      isNot(contains('config')),
      reason: 'platform_billing/config doc id should be gone too',
    );
  });

  test('the save goes through the privileged callable, not a client write', () {
    expect(strings, contains('setCommerceConfig'));
    expect(code, contains('httpsCallable'));
    // `platform_config` is `allow write: if false`. A direct write cannot
    // succeed, and if one is ever added it will fail silently at runtime
    // rather than at build time — so pin it here.
    expect(
      code,
      isNot(contains('SetOptions')),
      reason: 'a direct Firestore write to the config document is denied',
    );
    expect(
      code,
      isNot(RegExp(r'\.doc\(_docId\)\s*\.set\(')),
      reason: 'the config document must be written by the server only',
    );
  });

  test('the model documents the canonical path too', () {
    // The header is what the next engineer reads before touching this.
    final model = File(
      'lib/models/billing_config_model.dart',
    ).readAsStringSync();
    expect(model, contains('platform_config/commerce'));
    expect(model, contains('authoredTaxes'));
  });
}
