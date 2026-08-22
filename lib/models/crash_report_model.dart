// lib/models/crash_report_model.dart
//
// One document from `console_crash_reports` — written by the console's own
// CrashReporter (lib/core/utils/crash_reporter.dart), read back here so the
// founder can inspect production failures without leaving the console.
import 'package:cloud_firestore/cloud_firestore.dart';

class CrashReportModel {
  final String id;
  final String kind; // 'fatal' | 'nonfatal'
  final String label;
  final String error;
  final String stack;
  final List<String> breadcrumbs;
  final String build;
  final String commit;
  final String mode;
  final String env; // 'production' | 'emulator'
  final String uid;
  final String section;
  final String sessionId;
  final int occurrence;
  final DateTime? at;

  const CrashReportModel({
    required this.id,
    required this.kind,
    required this.label,
    required this.error,
    required this.stack,
    required this.breadcrumbs,
    required this.build,
    required this.commit,
    required this.mode,
    required this.env,
    required this.uid,
    required this.section,
    required this.sessionId,
    required this.occurrence,
    required this.at,
  });

  bool get isFatal => kind == 'fatal';
  bool get isProduction => env == 'production';

  /// The identity used to say "this same failure again": the label plus the
  /// first line of the error. Deliberately NOT the stack — a minified web
  /// stack's first frame can differ across reloads of the same defect.
  String get incidentKey => '$label|${error.split('\n').first}';

  factory CrashReportModel.fromSnapshot(DocumentSnapshot snap) {
    final d = (snap.data() as Map<String, dynamic>?) ?? const {};
    return CrashReportModel(
      id: snap.id,
      kind: _s(d['kind']),
      label: _s(d['label']),
      error: _s(d['error']),
      stack: _s(d['stack']),
      breadcrumbs: [
        for (final b in (d['breadcrumbs'] as List?) ?? const []) b.toString(),
      ],
      build: _s(d['build']),
      commit: _s(d['commit']),
      mode: _s(d['mode']),
      env: _s(d['env']),
      uid: _s(d['uid']),
      section: _s(d['section']),
      sessionId: _s(d['sessionId']),
      occurrence: _i(d['occurrence']),
      at: _date(d['at']),
    );
  }

  static String _s(Object? v) => v?.toString() ?? '';
  static int _i(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
