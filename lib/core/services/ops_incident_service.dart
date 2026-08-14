// B-11A C4/C5 — the TRIAGE writers for the two operator queues.
//
// These are deliberate direct Firestore updates, not callables: the rules
// grant the founder exactly these fields and nothing else
// (`ops_incidents`: status/acknowledgedAt/resolvedAt/resolutionNote;
//  `paymentAlerts`: status/resolvedAt/resolutionNote), so the write surface
// is rules-bounded the same way the moderation writes are. Every payload
// below names ONLY allowed fields — adding any other key makes the whole
// update PERMISSION_DENIED, which is the guard working, not a bug.
//
// C5 (paymentAlerts) is not optional: that queue has had a resolve RULE since
// day one and no writer, so anything landing there pinned the console red
// forever (B11-09). Shipping the incidents queue without fixing that would
// train the operator to ignore both.

import 'package:cloud_firestore/cloud_firestore.dart';

class OpsIncidentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── ops_incidents ─────────────────────────────────────────────────────

  /// "I have seen this" — distinct from "this is fixed", so the operator does
  /// not re-triage the same row on every console open.
  Future<void> acknowledgeIncident(String id) {
    return _db.collection('ops_incidents').doc(id).update({
      'status': 'acknowledged',
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveIncident(String id, {required String note}) {
    return _db.collection('ops_incidents').doc(id).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolutionNote': note,
    });
  }

  /// Resolved-in-error escape hatch: reopen rather than delete (deletion is
  /// rules-denied for everyone — an incident is a record, not a task).
  Future<void> reopenIncident(String id) {
    return _db.collection('ops_incidents').doc(id).update({
      'status': 'open',
    });
  }

  // ── paymentAlerts (B11-09) ────────────────────────────────────────────

  Future<void> resolvePaymentAlert(String id, {required String note}) {
    return _db.collection('paymentAlerts').doc(id).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolutionNote': note,
    });
  }
}
