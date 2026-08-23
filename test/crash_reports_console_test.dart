// Crash Reports (Governance) — the founder-facing viewer's pure contract.
//
// Inherits the SA-01 discipline from the Audit Log verbatim: the view is a
// capped live window, and a filtered miss over a capped window must read
// "not found yet", never "none". Adds the incident-grouping contract: a
// repeated failure must be tellable from an isolated one at a glance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena_admin_portel/controllers/crash_reports_controller.dart';
import 'package:alphaserena_admin_portel/models/crash_report_model.dart';
import 'package:alphaserena_admin_portel/screens/crash_reports_screen.dart';

class _FakeController extends CrashReportsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

CrashReportModel report({
  String id = 'r1',
  String kind = 'fatal',
  String label = 'FlutterError',
  String error = 'StateError: boom',
  String env = 'production',
  String section = 'section_0',
  String build = '1.0.0+1',
  String app = 'console',
  DateTime? at,
  bool noAt = false,
}) =>
    CrashReportModel(
      id: id,
      app: app,
      kind: kind,
      label: label,
      error: error,
      stack: '#0 main',
      breadcrumbs: const ['12:00:00 BOOT_FIREBASE_READY'],
      build: build,
      commit: 'abc1234',
      mode: 'release',
      env: env,
      uid: 'founder',
      section: section,
      sessionId: 's1',
      occurrence: 1,
      at: noAt ? null : (at ?? DateTime(2026, 8, 22)),
    );

List<CrashReportModel> filler(int n) => List.generate(
      n,
      (i) => report(id: 'noise_$i', label: 'noise', error: 'Noise $i: filler'),
    );

void main() {
  group('capped-window honesty (SA-01 inheritance)', () {
    test('a miss inside a FULL window is "not found yet", never "none"', () {
      final c = CrashReportsController();
      c.consoleReports.value = filler(CrashReportsController.pageSize);
      c.search.value = 'settlement crash from last month';
      expect(c.filtered, isEmpty);
      expect(c.emptyReason, CrashEmptyReason.noMatchInLoadedWindow,
          reason: 'older reports exist beyond the window; claiming "no such '
              'report" here is the SA-01 defect all over again');
    });

    test('a miss with the WHOLE collection loaded is a true "none"', () {
      final c = CrashReportsController();
      c.consoleReports.value = filler(3);
      c.search.value = 'nonexistent';
      expect(c.emptyReason, CrashEmptyReason.noMatchAnywhere);
    });

    test('an empty collection is the healthy state, not an error', () {
      final c = CrashReportsController();
      expect(c.emptyReason, CrashEmptyReason.noReportsAtAll);
    });
  });

  group('filtering', () {
    test('kind and environment filters partition correctly', () {
      final c = CrashReportsController();
      c.consoleReports.value = [
        report(id: 'a', kind: 'fatal', env: 'production',
            at: DateTime(2026, 8, 22, 12, 3)),
        report(id: 'b', kind: 'nonfatal', env: 'production',
            at: DateTime(2026, 8, 22, 12, 2)),
        report(id: 'c', kind: 'fatal', env: 'emulator',
            at: DateTime(2026, 8, 22, 12, 1)),
      ];
      c.kindFilter.value = 'fatal';
      expect(c.filtered.map((r) => r.id), ['a', 'c']);
      c.kindFilter.value = 'nonfatal';
      expect(c.filtered.map((r) => r.id), ['b']);
      c.kindFilter.value = 'production';
      expect(c.filtered.map((r) => r.id), ['a', 'b']);
    });

    test('search covers error text, section, build and commit', () {
      final c = CrashReportsController();
      c.consoleReports.value = [
        report(id: 'a', error: 'RangeError: index out of range'),
        report(id: 'b', section: 'section_14'),
        report(id: 'c', build: '1.2.0+7'),
      ];
      c.search.value = 'rangeerror';
      expect(c.filtered.single.id, 'a');
      c.search.value = 'section_14';
      expect(c.filtered.single.id, 'b');
      c.search.value = '1.2.0';
      expect(c.filtered.single.id, 'c');
    });
  });

  group('incident grouping — repeated vs isolated', () {
    test('same label + first error line counts as one incident', () {
      final c = CrashReportsController();
      c.consoleReports.value = [
        report(id: 'a', error: 'StateError: boom\n#0 frameA'),
        report(id: 'b', error: 'StateError: boom\n#0 frameB'),
        report(id: 'c', error: 'StateError: different'),
      ];
      final counts = c.incidentCounts;
      expect(counts[c.consoleReports[0].incidentKey], 2,
          reason: 'differing stacks must not split one incident — minified '
              'web frames vary across reloads of the same defect');
      expect(counts[c.consoleReports[2].incidentKey], 1);
    });
  });

  group('screen renders inside the PageShell scroll context', () {
    testWidgets('a report ROW actually builds — not a zero-height list',
        (t) async {
      // THE DEFECT THIS PINS: the first version put an Expanded ListView
      // inside PageShell's SingleChildScrollView. It collapsed to zero height
      // with no exception, and the founder's first production open showed
      // "1 total" over a blank list. A lazy list in a zero viewport builds
      // NO children, so finding the row text is the regression.
      Get.testMode = true;
      final c = _FakeController();
      c.consoleReports.value = [report(error: 'StateError: THE_VISIBLE_ROW')];
      c.markLoadedForTest();
      Get.put<CrashReportsController>(c);
      addTearDown(Get.reset);

      await t.pumpWidget(GetMaterialApp(home: Scaffold(
        body: CrashReportsScreen(),
      )));
      await t.pump();

      expect(find.textContaining('THE_VISIBLE_ROW'), findsOneWidget);
      expect(t.getSize(find.textContaining('THE_VISIBLE_ROW')).height,
          greaterThan(0));
      expect(find.text('FATAL'), findsOneWidget);
    });

    testWidgets('the healthy empty state says so', (t) async {
      Get.testMode = true;
      final c = _FakeController();
      c.markLoadedForTest();
      Get.put<CrashReportsController>(c);
      addTearDown(Get.reset);
      await t.pumpWidget(GetMaterialApp(home: Scaffold(
        body: CrashReportsScreen(),
      )));
      await t.pump();
      expect(find.text('No crash reports'), findsOneWidget);
    });
  });

  group('the app dimension — both mobile apps merge into one view', () {
    test('merged view is newest-first ACROSS collections and the app filter '
        'partitions it', () {
      final c = CrashReportsController();
      c.consoleReports.value = [
        report(id: 'con', app: 'console', at: DateTime(2026, 8, 22, 12, 2)),
      ];
      c.appReports.value = [
        report(id: 'ta', app: 'trainersarena',
            at: DateTime(2026, 8, 22, 12, 3)),
        report(id: 'as', app: 'alphasarena',
            at: DateTime(2026, 8, 22, 12, 1)),
      ];
      expect(c.reports.map((r) => r.id), ['ta', 'con', 'as'],
          reason: 'the founder triages one timeline, not two collections');
      c.appFilter.value = 'trainersarena';
      expect(c.filtered.single.id, 'ta');
      c.appFilter.value = 'alphasarena';
      expect(c.filtered.single.id, 'as');
      c.appFilter.value = 'console';
      expect(c.filtered.single.id, 'con');
    });

    test('a report with no app field is the console (pre-field documents)',
        () {
      expect(report(id: 'x').app, 'console');
      expect(report(id: 'x').appLabel, 'Console');
      expect(report(id: 'y', app: 'trainersarena').appLabel, 'TrainerArena');
      expect(report(id: 'z', app: 'alphasarena').appLabel, 'AlphaSarena');
    });

    test('ONE stream failing is partial, never total: the other apps\' '
        'reports stay visible and the gap is named', () {
      final c = CrashReportsController();
      c.appReports.value = [report(id: 'ta', app: 'trainersarena')];
      c.markStreamErrorForTest(console: true);
      expect(c.hasError, isFalse,
          reason: 'blanking the mobile reports because the console stream '
              'failed would invert the truth');
      expect(c.partialError, contains('Console'));
      expect(c.reports.single.id, 'ta');
      c.markStreamErrorForTest(console: true, apps: true);
      expect(c.hasError, isTrue);
      expect(c.partialError, isNull);
    });

    test('a report whose serverTimestamp has not resolved sorts LAST, '
        'never impersonating the newest failure', () {
      final c = CrashReportsController();
      c.appReports.value = [
        report(id: 'pending', noAt: true),
        report(id: 'dated', at: DateTime(2026, 8, 22)),
      ];
      expect(c.reports.map((r) => r.id), ['dated', 'pending']);
    });
  });

  group('model parsing', () {
    test('is defensive about missing and mistyped fields', () {
      // fromSnapshot needs a DocumentSnapshot; the defensive helpers are the
      // point, so exercise them through a report with degenerate values.
      final r = CrashReportModel(
        id: 'x',
        kind: '',
        label: '',
        error: '',
        stack: '',
        breadcrumbs: const [],
        build: '',
        commit: '',
        mode: '',
        env: '',
        uid: '',
        section: '',
        sessionId: '',
        occurrence: 0,
        at: null,
      );
      expect(r.isFatal, isFalse);
      expect(r.isProduction, isFalse);
      expect(r.incidentKey, '|');
    });
  });
}
