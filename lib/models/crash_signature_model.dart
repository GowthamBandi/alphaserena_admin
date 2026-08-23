// lib/models/crash_signature_model.dart
//
// ONE DEFECT, not one occurrence — the row an outage decision is made from.
//
// `console_crash_reports` / `app_crash_reports` are the evidence: append-only,
// one document per crash per user per time. This is the server-built rollup
// over them (`crash_signatures`, written only by the onCrashReportCreated
// trigger), and it exists because the two questions a founder actually asks at
// 9 a.m. cannot be answered from the firehose in the client:
//
//   "how many PEOPLE does this affect?"  — needs DISTINCT uids across every
//                                          report, not the newest 200
//   "is this new, or has it been doing   — needs firstSeenAt, which only
//    this for a month?"                    exists if something recorded it
//
// The priority is computed on the server from a frozen table (see
// functions/src/lib/crash_signature.ts) so the console never invents a
// severity of its own — one place answers "what pages me at 3 a.m.".
import 'package:cloud_firestore/cloud_firestore.dart';

class CrashSignatureModel {
  final String id;
  final String app;
  final String kind; // 'fatal' | 'nonfatal'
  final String label;
  final String errorClass;

  /// The message with per-user values normalised out — the thing that makes
  /// 500 users' crashes ONE row instead of 500.
  final String normalized;

  final String sampleError;
  final String sampleStack;
  final String sampleSection;

  final int occurrences;

  /// DISTINCT users. The axis that separates "one member in a retry loop"
  /// from "an outage".
  final int affectedUsers;

  /// True once the rollup stopped counting distinct users precisely; the
  /// console must then say "200+", never a number it cannot stand behind.
  final bool affectedUsersTruncated;

  /// build string → occurrences. A crash concentrated in one build is a bad
  /// release, and that is a different response from a crash spread evenly.
  final Map<String, int> builds;

  final bool production;
  final String priority; // 'P0' | 'P1' | 'P2' | 'P3'
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  const CrashSignatureModel({
    required this.id,
    required this.app,
    required this.kind,
    required this.label,
    required this.errorClass,
    required this.normalized,
    required this.sampleError,
    required this.sampleStack,
    required this.sampleSection,
    required this.occurrences,
    required this.affectedUsers,
    required this.affectedUsersTruncated,
    required this.builds,
    required this.production,
    required this.priority,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  bool get isFatal => kind == 'fatal';

  String get appLabel => switch (app) {
        'console' => 'Console',
        'trainersarena' => 'TrainerArena',
        'alphasarena' => 'AlphaSarena',
        _ => app,
      };

  /// "200+" once the distinct-user count stopped being exact.
  String get affectedUsersLabel =>
      affectedUsersTruncated ? '$affectedUsers+' : '$affectedUsers';

  /// The builds this defect has been seen in, worst first. A single entry is
  /// the strongest signal a crash system produces: it names the release.
  List<MapEntry<String, int>> get buildsRanked {
    final e = builds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return e;
  }

  /// True when EVERY occurrence came from one build — a release regression
  /// rather than a long-standing defect.
  bool get isSingleBuild => builds.length == 1 && occurrences > 1;

  factory CrashSignatureModel.fromSnapshot(DocumentSnapshot snap) {
    final d = (snap.data() as Map<String, dynamic>?) ?? const {};
    final rawBuilds = (d['builds'] as Map<String, dynamic>?) ?? const {};
    return CrashSignatureModel(
      id: snap.id,
      app: _s(d['app']),
      kind: _s(d['kind']),
      label: _s(d['label']),
      errorClass: _s(d['errorClass']),
      normalized: _s(d['normalized']),
      sampleError: _s(d['sampleError']),
      sampleStack: _s(d['sampleStack']),
      sampleSection: _s(d['sampleSection']),
      occurrences: _i(d['occurrences']),
      affectedUsers: _i(d['affectedUsers']),
      affectedUsersTruncated: d['affectedUsersTruncated'] == true,
      builds: {
        for (final e in rawBuilds.entries) e.key: _i(e.value),
      },
      // Absent means the trigger has not yet stamped it; treating that as
      // production would invent an operational concern from missing data.
      production: d['production'] == true,
      priority: _s(d['priority']).isEmpty ? 'P3' : _s(d['priority']),
      firstSeenAt: _date(d['firstSeenAt']),
      lastSeenAt: _date(d['lastSeenAt']),
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
