// B-11A C1 — one row of the `ops_incidents` operator queue.
//
// Server-written (raiseIncident, Admin SDK); the console may only move a row
// through triage: status / acknowledgedAt / resolvedAt / resolutionNote. The
// facts (type, severity, fn, correlationId, occurrences, firstSeenAt) are
// rules-pinned unwritable from every client, founder included.

import 'package:cloud_firestore/cloud_firestore.dart';

class OpsIncidentModel {
  final String id;
  final String type;
  final String severity; // "P0" | "P1" | "P2"
  final String fn;
  final String correlationId;
  final String summary;
  final String action;
  final Map<String, String> context;
  final String status; // "open" | "acknowledged" | "resolved"
  final int occurrences;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String resolutionNote;

  const OpsIncidentModel({
    required this.id,
    required this.type,
    required this.severity,
    required this.fn,
    required this.correlationId,
    required this.summary,
    required this.action,
    required this.context,
    required this.status,
    required this.occurrences,
    this.firstSeenAt,
    this.lastSeenAt,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNote = '',
  });

  bool get isOpen => status == 'open';
  bool get isAcknowledged => status == 'acknowledged';
  bool get isResolved => status == 'resolved';
  bool get isP0 => severity == 'P0';

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  factory OpsIncidentModel.fromMap(Map<String, dynamic> m, String id) {
    final rawContext = m['context'];
    final context = <String, String>{};
    if (rawContext is Map) {
      rawContext.forEach((k, v) => context['$k'] = '$v');
    }
    return OpsIncidentModel(
      id: id,
      type: (m['type'] ?? '').toString(),
      severity: (m['severity'] ?? 'P1').toString(),
      fn: (m['fn'] ?? '').toString(),
      correlationId: (m['correlationId'] ?? '').toString(),
      summary: (m['summary'] ?? '').toString(),
      action: (m['action'] ?? '').toString(),
      context: context,
      status: (m['status'] ?? 'open').toString(),
      occurrences: _int(m['occurrences']),
      firstSeenAt: _date(m['firstSeenAt']),
      lastSeenAt: _date(m['lastSeenAt']),
      acknowledgedAt: _date(m['acknowledgedAt']),
      resolvedAt: _date(m['resolvedAt']),
      resolutionNote: (m['resolutionNote'] ?? '').toString(),
    );
  }
}
