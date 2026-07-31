import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// One automation rule as the founder sees it (`automation_rules/{id}`).
///
/// Rules are CF-owned: this console READS them and toggles `enabled` through a
/// callable. It never writes a rule directly — a client able to edit a rule
/// could point any trigger at any audience and broadcast to the platform.
class AutomationRule {
  final String id;
  final String trigger;
  final bool enabled;
  final int version;
  final String templateId;
  final String audience;
  final int priority;

  /// How many times this rule has fired. Engine-owned.
  final int fireCount;
  final int failureCount;
  final DateTime? lastFiredAt;
  final String? lastError;

  const AutomationRule({
    required this.id,
    this.trigger = '',
    this.enabled = false,
    this.version = 1,
    this.templateId = '',
    this.audience = '',
    this.priority = 0,
    this.fireCount = 0,
    this.failureCount = 0,
    this.lastFiredAt,
    this.lastError,
  });

  bool get isHealthy => failureCount == 0 && (lastError ?? '').isEmpty;

  factory AutomationRule.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? const {};
    int i(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    DateTime? d(String k) =>
        (m[k] is Timestamp) ? (m[k] as Timestamp).toDate() : null;
    final err = (m['lastError'] ?? '').toString();
    return AutomationRule(
      id: doc.id,
      trigger: (m['trigger'] ?? '').toString(),
      enabled: m['enabled'] == true,
      version: i('version') == 0 ? 1 : i('version'),
      templateId: (m['templateId'] ?? '').toString(),
      audience: (m['audience'] ?? '').toString(),
      priority: i('priority'),
      fireCount: i('fireCount'),
      failureCount: i('failureCount'),
      lastFiredAt: d('lastFiredAt'),
      lastError: err.isEmpty ? null : err,
    );
  }
}

/// One evaluation, fired or not (`automation_runs/{id}`).
class AutomationRun {
  final String id;
  final String ruleId;
  final String trigger;
  final String subjectId;
  final bool fired;

  /// Why it did or did not fire — the answer to the question founders
  /// actually ask.
  final String reason;
  final int delivered;
  final DateTime? createdAt;

  const AutomationRun({
    required this.id,
    this.ruleId = '',
    this.trigger = '',
    this.subjectId = '',
    this.fired = false,
    this.reason = '',
    this.delivered = 0,
    this.createdAt,
  });

  /// Plain-language explanation. A founder should never have to read an enum.
  String get explanation {
    switch (reason) {
      case 'ok':
        return delivered > 0
            ? 'Sent to $delivered recipient${delivered == 1 ? '' : 's'}'
            : 'Fired, but resolved to no recipients';
      case 'disabled':
        return 'Skipped — the automation is switched off';
      case 'cooldown':
        return 'Skipped — still inside the cooldown window';
      case 'maxSends':
        return 'Skipped — this subject hit the send limit';
      case 'quietHours':
        return 'Skipped — quiet hours';
      case 'conditionFailed':
        return 'Skipped — conditions did not match';
      case 'duplicate':
        return 'Skipped — this occurrence was already handled';
      case 'loopGuard':
        return 'Skipped — the event came from another automation';
      case 'triggerMismatch':
        return 'Skipped — trigger did not match';
      case 'unknownTrigger':
        return 'Skipped — the rule points at an unknown trigger';
      default:
        return reason;
    }
  }

  factory AutomationRun.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? const {};
    return AutomationRun(
      id: doc.id,
      ruleId: (m['ruleId'] ?? '').toString(),
      trigger: (m['trigger'] ?? '').toString(),
      subjectId: (m['subjectId'] ?? '').toString(),
      fired: m['fired'] == true,
      reason: (m['reason'] ?? '').toString(),
      delivered: (m['delivered'] is num) ? (m['delivered'] as num).toInt() : 0,
      createdAt: (m['createdAt'] is Timestamp)
          ? (m['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

/// A trigger the platform actually emits, with the code that proves it.
class AutomationTrigger {
  final String id;
  final String label;
  final String subject;

  /// The repository source that emits this fact. Shown in the console so a
  /// founder can see an automation is bound to something real.
  final String source;

  const AutomationTrigger(this.id, this.label, this.subject, this.source);
}

/// The console's window onto the EP-5 Automation Engine.
class AutomationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  Stream<List<AutomationRule>> watchRules() => _db
      .collection('automation_rules')
      .snapshots()
      .map((s) => s.docs.map(AutomationRule.fromSnapshot).toList()
        ..sort((a, b) => a.trigger.compareTo(b.trigger)));

  /// Recent evaluations, newest first — including the decisions NOT to fire.
  Stream<List<AutomationRun>> watchRuns({int limit = 100}) => _db
      .collection('automation_runs')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(AutomationRun.fromSnapshot).toList());

  Future<List<AutomationTrigger>> triggers() async {
    final res = await _fns.httpsCallable('listAutomationTriggers').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    return ((m['triggers'] as List?) ?? const []).map((e) {
      final t = Map<String, dynamic>.from(e as Map);
      return AutomationTrigger(
        (t['id'] ?? '').toString(),
        (t['label'] ?? '').toString(),
        (t['subject'] ?? '').toString(),
        (t['source'] ?? '').toString(),
      );
    }).toList();
  }

  /// Switches an automation on or off. A callable rather than a direct write,
  /// so `automation_rules` stays entirely CF-owned.
  Future<void> setEnabled(String ruleId, bool enabled) async {
    await _fns.httpsCallable('setAutomationEnabled')
        .call({'ruleId': ruleId, 'enabled': enabled});
  }
}
