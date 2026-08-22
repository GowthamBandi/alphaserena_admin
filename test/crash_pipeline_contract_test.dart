// test/crash_pipeline_contract_test.dart
//
// THE ERROR-REPORTING CONTRACT.
//
// Production capture for this WEB console is the CrashReporter →
// `console_crash_reports` pipeline (Crashlytics does not exist on Flutter
// web). These tests pin the parts that must never drift:
//  • classification (fatal vs non-fatal) is carried on every document;
//  • sensitive values cannot leave the app (redaction + breadcrumb-name gate);
//  • a crash loop cannot flood the backend (dedup + session cap);
//  • a report before Firebase init is buffered, not lost;
//  • the reporter can never take the app down (throwing writer/sink);
//  • both global handlers share ONE seam (source guard on main.dart);
//  • the crash-test triggers are compiled out of normal builds.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena_admin_portel/core/utils/crash_reporter.dart';
import 'package:alphaserena_admin_portel/core/utils/fatal_reporter.dart';
import 'package:alphaserena_admin_portel/dev/crash_test_panel.dart';

void main() {
  setUp(CrashReporter.resetForTest);
  tearDown(() {
    CrashReporter.resetForTest();
    attachRemoteFatalSink(null);
  });

  List<Map<String, dynamic>> capture() {
    final docs = <Map<String, dynamic>>[];
    CrashReporter.install((d) async => docs.add(d), emulatorMode: false);
    return docs;
  }

  group('privacy — redaction', () {
    test('credential-shaped values never survive', () {
      expect(redact('password=hunter2 ok'), isNot(contains('hunter2')));
      expect(redact('"token": "abc123xyz"'), isNot(contains('abc123xyz')));
      expect(
        redact('Authorization: Bearer eyAbCdEfGh.ijKlMnOpQr.stUvWxYz012'),
        isNot(contains('eyAbCdEfGh')),
      );
      expect(
        redact(
          'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpM',
        ),
        contains('[jwt-redacted]'),
      );
      expect(
        redact('key AIzaSyDGN75XqBCS2gI3adaM1AkZgQbZDxCJyHk'),
        contains('[apikey-redacted]'),
      );
      expect(
        redact('user ehmsystem3@gmail.com not found'),
        isNot(contains('ehmsystem3')),
      );
    });

    test('an error carrying a password reaches the doc redacted', () {
      final docs = capture();
      CrashReporter.reportNonFatal(
        'login',
        StateError('failed with password=supersecret'),
      );
      expect(docs, hasLength(1));
      expect('${docs.single['error']}', isNot(contains('supersecret')));
    });

    test('breadcrumb refuses prose — the name gate IS the privacy story', () {
      expect(
        () => CrashReporter.breadcrumb('user typed hunter2'),
        throwsAssertionError,
      );
      CrashReporter.breadcrumb('LOGIN_STARTED');
      expect(CrashReporter.debugBreadcrumbs.single, endsWith('LOGIN_STARTED'));
    });

    test('every breadcrumb literal in lib/ is a stable event name', () {
      final re = RegExp(r'''CrashReporter\.breadcrumb\(\s*'([^']*)'\s*\)''');
      final name = RegExp(r'^[A-Z][A-Z0-9_]{2,47}$');
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final m in re.allMatches(f.readAsStringSync())) {
          if (!name.hasMatch(m.group(1)!)) {
            offenders.add('${f.path}: "${m.group(1)}"');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'breadcrumbs are names, never payloads');
    });
  });

  group('classification and context', () {
    test('fatal and non-fatal are distinct kinds on the document', () {
      final docs = capture();
      CrashReporter.handleFatal('zone', StateError('a'), StackTrace.current);
      CrashReporter.reportNonFatal('op', StateError('b'));
      expect(docs[0]['kind'], 'fatal');
      expect(docs[1]['kind'], 'nonfatal');
    });

    test('every report carries build identity, env, section and session', () {
      final docs = capture();
      CrashReporter.setUser('uid123');
      CrashReporter.setSection('section_5');
      CrashReporter.reportNonFatal('op', StateError('x'));
      final d = docs.single;
      expect(d['build'], kAppVersion);
      expect(d['commit'], kGitCommit);
      expect(d['mode'], buildMode);
      expect(d['env'], 'production');
      expect(d['uid'], 'uid123');
      expect(d['section'], 'section_5');
      expect(d['sessionId'], isNotEmpty);
      expect(d.containsKey('email'), isFalse);
    });
  });

  group('flood protection', () {
    test('the same signature stops at 3, a new signature still reports', () {
      final docs = capture();
      for (var i = 0; i < 6; i++) {
        CrashReporter.reportNonFatal('loop', StateError('same shape $i'));
      }
      expect(docs, hasLength(CrashReporter.maxPerSignature));
      CrashReporter.reportNonFatal('loop', const FormatException('other'));
      expect(docs, hasLength(CrashReporter.maxPerSignature + 1));
    });

    test('a session never sends more than the cap', () {
      final docs = capture();
      for (var i = 0; i < 60; i++) {
        // Distinct labels → distinct signatures → only the session cap stops
        // them.
        CrashReporter.reportNonFatal('label_$i', StateError('e$i'));
      }
      expect(docs.length, CrashReporter.maxReportsPerSession);
    });
  });

  group('startup and failure safety', () {
    test('reports before install are buffered and flushed on install', () {
      CrashReporter.reportNonFatal('early', StateError('pre-init'));
      final docs = <Map<String, dynamic>>[];
      CrashReporter.install((d) async => docs.add(d), emulatorMode: false);
      expect(docs, hasLength(1));
      expect(docs.single['label'], 'early');
    });

    test('a synchronously-throwing writer cannot take the app down', () {
      CrashReporter.install(
        (d) => throw StateError('writer exploded'),
        emulatorMode: false,
      );
      expect(
        () => CrashReporter.reportNonFatal('op', StateError('x')),
        returnsNormally,
      );
    });

    test('a throwing remote sink never suppresses the local sink', () {
      final local = <String>[];
      final prev = setFatalSinkForTest((l, e, s) => local.add(l));
      addTearDown(() => setFatalSinkForTest(prev));
      attachRemoteFatalSink((l, e, s) => throw StateError('remote broken'));
      expect(() => reportFatal('boom', StateError('x')), returnsNormally);
      expect(local, ['boom']);
    });

    test('the remote sink receives what reportFatal receives', () {
      final remote = <String>[];
      final prev = setFatalSinkForTest((l, e, s) {});
      addTearDown(() => setFatalSinkForTest(prev));
      attachRemoteFatalSink((l, e, s) => remote.add('$l|$e'));
      reportFatal('FlutterError', StateError('ui broke'));
      expect(remote.single, contains('FlutterError'));
      expect(remote.single, contains('ui broke'));
    });
  });

  group('one ownership model — source guard on main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('both global handlers exist and feed the one seam', () {
      expect(main, contains('runZonedGuarded'));
      expect(main, contains('FlutterError.onError'));
      expect(main, contains('reportFatal'));
      expect(main, contains('attachRemoteFatalSink(CrashReporter.handleFatal)'));
      expect(main, contains('collection(FsCollections.consoleCrashReports)'));
    });

    test('no second file installs a competing global handler', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('main.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('FlutterError.onError =') ||
            src.contains('runZonedGuarded(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'global error capture has exactly one owner: main.dart');
    });
  });

  group('crash-test gating', () {
    test('the compile-time gate is OFF unless the define is passed', () {
      // This test suite runs without --dart-define=CRASH_TEST=true, exactly
      // like every normal production build.
      expect(kCrashTestEnabled, isFalse);
    });

    testWidgets('the panel renders nothing when gated off', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Stack(children: [SizedBox(), CrashTestPanel()]),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.textContaining('CRASH TEST'), findsNothing);
    });
  });
}
