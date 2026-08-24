// Crash Reports (Governance) — the founder-facing viewer's pure contract.
//
// Inherits the SA-01 discipline from the Audit Log verbatim: the view is a
// capped live window, and a filtered miss over a capped window must read
// "not found yet", never "none". Adds the incident-grouping contract: a
// repeated failure must be tellable from an isolated one at a glance.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena_admin_portel/controllers/crash_reports_controller.dart';
import 'package:alphaserena_admin_portel/models/crash_report_model.dart';
import 'package:alphaserena_admin_portel/models/crash_signature_model.dart';
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
  _triageTests();
  _liveContractTests();
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
      // Incidents is now the default view; this test is about the raw
      // evidence list, so select it explicitly.
      c.view.value = 'reports';
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
      c.view.value = 'reports';
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
      expect(report(id: 'y', app: 'trainersarena').appLabel, 'Trainersarena');
      expect(report(id: 'z', app: 'alphasarena').appLabel, 'Alphasarena');
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

// ── THE TRIAGE VIEW (crash_signatures) ──────────────────────────────────────
// One row per DEFECT. These pin the properties the per-occurrence report list
// structurally could not express.

CrashSignatureModel signature({
  String id = 'sig1',
  String app = 'alphasarena',
  String kind = 'fatal',
  String errorClass = 'StateError',
  String normalized = 'Bad state: No element',
  int occurrences = 1,
  int affectedUsers = 1,
  bool truncated = false,
  Map<String, int> builds = const {'1.0.0+3': 1},
  bool production = true,
  String priority = 'P2',
  DateTime? lastSeenAt,
}) =>
    CrashSignatureModel(
      id: id,
      app: app,
      kind: kind,
      label: 'FlutterError',
      errorClass: errorClass,
      normalized: normalized,
      sampleError: '$errorClass: $normalized',
      sampleStack: '#0 main',
      sampleSection: 'home',
      occurrences: occurrences,
      affectedUsers: affectedUsers,
      affectedUsersTruncated: truncated,
      builds: builds,
      production: production,
      priority: priority,
      firstSeenAt: DateTime(2026, 8, 20),
      lastSeenAt: lastSeenAt ?? DateTime(2026, 8, 23),
    );

/// A mobile report as it looks AFTER the trigger has projected it: stamped
/// with the incident it belongs to.
CrashReportModel reportWithSignature(String sig, String error) =>
    CrashReportModel(
      id: 'r-$sig',
      app: 'alphasarena',
      platform: 'android',
      kind: 'fatal',
      label: 'FlutterError',
      error: error,
      stack: '#0 main',
      breadcrumbs: const [],
      build: '1.0.0+3',
      commit: 'abc',
      mode: 'release',
      env: 'production',
      uid: 'u1',
      section: 'home',
      sessionId: 's1',
      occurrence: 1,
      at: DateTime(2026, 8, 23),
      signature: sig,
    );

void _triageTests() {
  group('incident triage', () {
    test('the WORST defect leads, regardless of how loud the others are', () {
      final c = CrashReportsController();
      c.signatures.value = [
        signature(id: 'noisy', priority: 'P3', occurrences: 5000),
        signature(id: 'outage', priority: 'P0', occurrences: 8),
        signature(id: 'mid', priority: 'P2', occurrences: 900),
      ];
      expect(c.filteredSignatures.map((s) => s.id), ['outage', 'mid', 'noisy'],
          reason: 'a founder opening this screen must land on the outage, and '
              'an outage that started ten minutes ago carries a SMALLER '
              'number than a month-old nuisance');
    });

    test('the priority summary counts what is actually shown', () {
      final c = CrashReportsController();
      c.signatures.value = [
        signature(id: 'a', priority: 'P0'),
        signature(id: 'b', priority: 'P0'),
        signature(id: 'c', priority: 'P2'),
      ];
      expect(c.priorityCounts['P0'], 2);
      expect(c.priorityCounts['P2'], 1);
      expect(c.priorityCounts['P1'], 0);

      // …and it follows the filters, so the header can never disagree with
      // the list under it.
      c.appFilter.value = 'trainersarena';
      expect(c.priorityCounts['P0'], 0);
    });

    test('a truncated distinct-user count says "200+", never a number it '
        'cannot stand behind', () {
      expect(signature(affectedUsers: 12).affectedUsersLabel, '12');
      expect(
          signature(affectedUsers: 200, truncated: true).affectedUsersLabel,
          '200+');
    });

    test('a defect confined to ONE build is flagged — that is a release '
        'regression, not a long-standing bug', () {
      expect(
          signature(builds: {'1.0.0+4': 40}, occurrences: 40).isSingleBuild,
          isTrue);
      expect(
          signature(builds: {'1.0.0+3': 20, '1.0.0+4': 20}, occurrences: 40)
              .isSingleBuild,
          isFalse);
      // A single occurrence in a single build is not yet a pattern.
      expect(signature(builds: {'1.0.0+4': 1}, occurrences: 1).isSingleBuild,
          isFalse);
    });

    test('an absent `production` flag is NOT treated as production', () {
      final s = CrashSignatureModel.fromSnapshot(_FakeSnap('x', const {}));
      expect(s.production, isFalse,
          reason: 'inventing an operational concern out of missing data is '
              'how an alerting system loses its credibility');
      expect(s.priority, 'P3');
      expect(s.occurrences, 0);
    });

    testWidgets('an incident ROW actually builds inside PageShell', (t) async {
      // Same regression the report list already carries a guard for: an
      // Expanded/lazy list inside PageShell's scrollview collapses to zero
      // height with no exception.
      Get.testMode = true;
      final c = _FakeController();
      c.signatures.value = [
        signature(errorClass: 'RangeError', normalized: 'THE_VISIBLE_INCIDENT',
            priority: 'P0', affectedUsers: 8, occurrences: 12),
      ];
      c.markLoadedForTest();
      Get.put<CrashReportsController>(c);
      addTearDown(Get.reset);

      await t.pumpWidget(GetMaterialApp(
          home: Scaffold(body: CrashReportsScreen())));
      await t.pump();

      expect(find.textContaining('THE_VISIBLE_INCIDENT'), findsOneWidget);
      expect(
          t.getSize(find.textContaining('THE_VISIBLE_INCIDENT')).height,
          greaterThan(0));
      expect(find.text('P0'), findsWidgets);
      // BREADTH is on the row, not buried in a dialog.
      expect(find.textContaining('8 users'), findsOneWidget);
    });

    // ── THE MEASUREMENT ITSELF CAN FAIL ────────────────────────────────────

    test('EVIDENCE WITHOUT A ROLLUP IS NOT HEALTH — the projection being down '
        'must never render as "nothing has crashed"', () {
      final c = _FakeController();
      c.appReports.value = [
        report(error: 'StateError: real crash 1'),
        report(error: 'StateError: real crash 2'),
      ];
      c.signatures.clear();
      c.markLoadedForTest();

      expect(c.rollupStalled, isTrue,
          reason: 'reports exist and no incident describes them');
      expect(c.unprojectedReportCount, 2,
          reason: 'neither report carries a signature stamp');
    });

    test('a genuinely quiet platform is NOT reported as a stalled projection',
        () {
      final c = _FakeController();
      c.appReports.clear();
      c.signatures.clear();
      c.markLoadedForTest();
      expect(c.rollupStalled, isFalse);
    });

    test('a STILL-LOADING stream is never diagnosed as stalled', () {
      // Both streams start empty; calling it broken before they answer would
      // flash a false alarm on every open.
      final c = _FakeController();
      c.appReports.value = [report()];
      expect(c.rollupStalled, isFalse, reason: 'nothing has loaded yet');
      c.markLoadedForTest();
      expect(c.rollupStalled, isTrue);
    });

    test('a rollup that IS running clears the alarm', () {
      final c = _FakeController();
      c.appReports.value = [report()];
      c.signatures.value = [signature()];
      c.markLoadedForTest();
      expect(c.rollupStalled, isFalse);
    });

    // ── INCIDENT → ITS OWN OCCURRENCES ─────────────────────────────────────

    test('the signature JOINS the two views — an incident can reach every '
        'occurrence behind it', () {
      final c = _FakeController();
      c.appReports.value = [
        report(error: 'StateError: mine'),
      ];
      c.markLoadedForTest();
      c.showOccurrencesOf('abc123');
      expect(c.view.value, 'reports',
          reason: 'the evidence lives in the reports view');
      expect(c.search.value, 'abc123');
      expect(c.searchField.text, 'abc123',
          reason: 'the visible search box must say what the list is filtered '
              'to — otherwise the founder reads a filtered list as the whole');
    });

    test('searching a signature id FINDS its occurrences', () {
      final c = _FakeController();
      c.appReports.value = [
        reportWithSignature('sig-xyz', 'StateError: the incident'),
        reportWithSignature('sig-other', 'StateError: something else'),
      ];
      c.markLoadedForTest();
      c.showOccurrencesOf('sig-xyz');
      expect(c.filtered, hasLength(1));
      expect(c.filtered.single.error, contains('the incident'));
    });

    test('a report the projection never reached carries no signature, and is '
        'not silently attributed to one', () {
      final c = _FakeController();
      c.appReports.value = [report(error: 'StateError: unprojected')];
      c.markLoadedForTest();
      expect(c.appReports.single.signature, isEmpty);
      c.search.value = 'sig-anything';
      expect(c.filtered, isEmpty);
    });


    testWidgets('an INCIDENT ROW actually builds inside the PageShell scroll '
        'context — not a zero-height list', (t) async {
      // The exact defect the report list shipped with: a ListView inside a
      // scrolling parent collapses to zero height with NO exception, so the
      // header says "3 distinct defects" over a blank page.
      Get.testMode = true;
      final c = _FakeController();
      c.signatures.value = [
        signature(id: 'sigA', normalized: 'Bad state: THE_VISIBLE_INCIDENT'),
      ];
      c.markLoadedForTest();
      Get.put<CrashReportsController>(c);
      addTearDown(Get.reset);

      await t.pumpWidget(GetMaterialApp(
          home: Scaffold(body: CrashReportsScreen())));
      await t.pump();

      expect(find.textContaining('THE_VISIBLE_INCIDENT'), findsOneWidget);
      expect(find.textContaining('1 distinct defect'), findsOneWidget);
      final size = t.getSize(find.textContaining('THE_VISIBLE_INCIDENT').first);
      expect(size.height, greaterThan(0));
    });

    testWidgets('the STALLED-PROJECTION state is what an empty rollup over a '
        'full firehose renders', (t) async {
      Get.testMode = true;
      final c = _FakeController();
      c.appReports.value = [report(error: 'StateError: real crash')];
      c.signatures.clear();
      c.markLoadedForTest();
      Get.put<CrashReportsController>(c);
      addTearDown(Get.reset);

      await t.pumpWidget(GetMaterialApp(
          home: Scaffold(body: CrashReportsScreen())));
      await t.pump();

      expect(find.text('Incidents are not being built'), findsOneWidget);
      expect(find.textContaining('healthy'), findsNothing,
          reason: 'a broken projection must never be described as health');
    });

  });
}

class _FakeSnap implements DocumentSnapshot {
  _FakeSnap(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── THE CROSS-BOUNDARY CONTRACT ────────────────────────────────────────────
//
// Two self-consistent sides are not a contract. This platform has shipped that
// mistake before — `coaching_rollups` passed unit tests, `tsc` and review on
// BOTH sides because each side agreed about a shape that never existed in the
// database, and the reader silently returned empty for every member.
//
// `test/fixtures/live_crash_signature.json` is not hand-typed: it is a
// `crash_signatures` document READ BACK OUT OF PRODUCTION after the deployed
// `onCrashReportCreated` trigger built it (2026-08-23, probe run recorded in
// CRASH_MONITORING_CERTIFICATION.md §LIVE PROOF). If the trigger's output shape
// ever changes, this reds on the READER side, which is the side that would
// otherwise fail silently.
void _liveContractTests() {
  group('the console reads what the DEPLOYED trigger actually writes', () {
    Map<String, dynamic> live() => jsonDecode(
            File('test/fixtures/live_crash_signature.json').readAsStringSync())
        as Map<String, dynamic>;

    test('every field the model reads is present in the live document', () {
      final d = live();
      for (final key in const [
        'app', 'kind', 'label', 'errorClass', 'normalized',
        'sampleError', 'sampleStack', 'sampleSection',
        'occurrences', 'affectedUsers', 'builds', 'production', 'priority',
        'firstSeenAt', 'lastSeenAt',
      ]) {
        expect(d.containsKey(key), isTrue,
            reason: '`$key` is absent from the document production actually '
                'wrote — the reader would render a default and say nothing');
      }
    });

    test('the model produces the row a founder would read', () {
      final m = CrashSignatureModel.fromSnapshot(_LiveSnapshot(live()));
      expect(m.occurrences, 3);
      expect(m.affectedUsers, 2);
      expect(m.affectedUsersLabel, '2');
      expect(m.isFatal, isTrue);
      expect(m.appLabel, 'Alphasarena');
      expect(m.errorClass, 'StateError');
      expect(m.priority, 'P1');
      expect(m.production, isTrue);
      // The build breakdown is the signal that names a bad release, and it is
      // exactly what the dotted-key defect made permanently unreadable.
      expect(m.builds, isNotEmpty);
      expect(m.isSingleBuild, isTrue);
      expect(m.buildsRanked.first.value, 3);
      expect(m.firstSeenAt, isNotNull);
      expect(m.lastSeenAt, isNotNull);
    });

    test('no per-member value reached the row the founder reads', () {
      final m = CrashSignatureModel.fromSnapshot(_LiveSnapshot(live()));
      // The NORMALISED message is what the incident row renders. The sample
      // error deliberately still carries the real values — one real example is
      // the point of it — but the grouping key must not.
      for (final v in const ['Zx7Yw2Vu5Ts8Rq', 'probe-user-1', '799']) {
        expect(m.normalized, isNot(contains(v)));
      }
    });
  });
}

/// A DocumentSnapshot over a decoded production document. Firestore hands the
/// model `Timestamp`s where this hands it ISO strings; the model's `_date`
/// accepts both, which is exactly the tolerance being asserted.
class _LiveSnapshot implements DocumentSnapshot {
  _LiveSnapshot(this._data);
  final Map<String, dynamic> _data;
  @override
  String get id => '65e238c7e1531eea88274de245d68d1e';
  @override
  Map<String, dynamic> data() => _data;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
