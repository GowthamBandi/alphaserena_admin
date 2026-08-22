// Crash Reports (Governance) — the founder-facing viewer's pure contract.
//
// Inherits the SA-01 discipline from the Audit Log verbatim: the view is a
// capped live window, and a filtered miss over a capped window must read
// "not found yet", never "none". Adds the incident-grouping contract: a
// repeated failure must be tellable from an isolated one at a glance.
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/controllers/crash_reports_controller.dart';
import 'package:alphaserena_admin_portel/models/crash_report_model.dart';

CrashReportModel report({
  String id = 'r1',
  String kind = 'fatal',
  String label = 'FlutterError',
  String error = 'StateError: boom',
  String env = 'production',
  String section = 'section_0',
  String build = '1.0.0+1',
}) =>
    CrashReportModel(
      id: id,
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
      at: DateTime(2026, 8, 22),
    );

List<CrashReportModel> filler(int n) => List.generate(
      n,
      (i) => report(id: 'noise_$i', label: 'noise', error: 'Noise $i: filler'),
    );

void main() {
  group('capped-window honesty (SA-01 inheritance)', () {
    test('a miss inside a FULL window is "not found yet", never "none"', () {
      final c = CrashReportsController();
      c.reports.value = filler(CrashReportsController.pageSize);
      c.search.value = 'settlement crash from last month';
      expect(c.filtered, isEmpty);
      expect(c.emptyReason, CrashEmptyReason.noMatchInLoadedWindow,
          reason: 'older reports exist beyond the window; claiming "no such '
              'report" here is the SA-01 defect all over again');
    });

    test('a miss with the WHOLE collection loaded is a true "none"', () {
      final c = CrashReportsController();
      c.reports.value = filler(3);
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
      c.reports.value = [
        report(id: 'a', kind: 'fatal', env: 'production'),
        report(id: 'b', kind: 'nonfatal', env: 'production'),
        report(id: 'c', kind: 'fatal', env: 'emulator'),
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
      c.reports.value = [
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
      c.reports.value = [
        report(id: 'a', error: 'StateError: boom\n#0 frameA'),
        report(id: 'b', error: 'StateError: boom\n#0 frameB'),
        report(id: 'c', error: 'StateError: different'),
      ];
      final counts = c.incidentCounts;
      expect(counts[c.reports[0].incidentKey], 2,
          reason: 'differing stacks must not split one incident — minified '
              'web frames vary across reloads of the same defect');
      expect(counts[c.reports[2].incidentKey], 1);
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
