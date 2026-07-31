import 'package:cloud_functions/cloud_functions.dart';

double _d(dynamic v) => (v is num) ? v.toDouble() : 0;
int _i(dynamic v) => (v is num) ? v.toInt() : 0;
String _s(dynamic v) => (v ?? '').toString();

/// A metric the platform CANNOT measure, with the reason.
///
/// Surfaced in the dashboard rather than omitted: a screen that shows only
/// what it can measure, without saying what it cannot, invites the founder to
/// read a missing number as zero rather than as absent.
class UnavailableMetric {
  final String metric;
  final String reason;
  const UnavailableMetric(this.metric, this.reason);
}

class DeliverySummary {
  final int created;
  final int persisted;
  final int pushDelivered;
  final int pushFailedOrNoToken;
  final int suppressedTotal;
  final Map<String, int> suppressedByReason;
  final double persistRate;
  final double pushRate;
  final double suppressionRate;

  /// Period-over-period change; null when there is no baseline to compare to.
  final double? createdChange;
  final double? pushChange;
  final double? suppressedChange;

  const DeliverySummary({
    this.created = 0,
    this.persisted = 0,
    this.pushDelivered = 0,
    this.pushFailedOrNoToken = 0,
    this.suppressedTotal = 0,
    this.suppressedByReason = const {},
    this.persistRate = 0,
    this.pushRate = 0,
    this.suppressionRate = 0,
    this.createdChange,
    this.pushChange,
    this.suppressedChange,
  });
}

class CampaignPerf {
  final String id;
  final String title;
  final String status;
  final String audience;
  final int targetCount;
  final int sentCount;
  final int pushedCount;
  final int failedCount;
  final double deliveryRate;
  final double pushReach;
  final int reliabilityFlags;

  const CampaignPerf({
    required this.id,
    this.title = '',
    this.status = '',
    this.audience = '',
    this.targetCount = 0,
    this.sentCount = 0,
    this.pushedCount = 0,
    this.failedCount = 0,
    this.deliveryRate = 0,
    this.pushReach = 0,
    this.reliabilityFlags = 0,
  });

  factory CampaignPerf.fromMap(Map<String, dynamic> m) => CampaignPerf(
        id: _s(m['id']),
        title: _s(m['title']),
        status: _s(m['status']),
        audience: _s(m['audience']),
        targetCount: _i(m['targetCount']),
        sentCount: _i(m['sentCount']),
        pushedCount: _i(m['pushedCount']),
        failedCount: _i(m['failedCount']),
        deliveryRate: _d(m['deliveryRate']),
        pushReach: _d(m['pushReach']),
        reliabilityFlags: _i(m['reliabilityFlags']),
      );
}

class AutomationPerf {
  final String ruleId;
  final String trigger;
  final int evaluations;
  final int fired;
  final int delivered;
  final double fireRate;
  final Map<String, int> skipReasons;
  final int firedWithNoRecipients;

  const AutomationPerf({
    required this.ruleId,
    this.trigger = '',
    this.evaluations = 0,
    this.fired = 0,
    this.delivered = 0,
    this.fireRate = 0,
    this.skipReasons = const {},
    this.firedWithNoRecipients = 0,
  });

  factory AutomationPerf.fromMap(Map<String, dynamic> m) => AutomationPerf(
        ruleId: _s(m['ruleId']),
        trigger: _s(m['trigger']),
        evaluations: _i(m['evaluations']),
        fired: _i(m['fired']),
        delivered: _i(m['delivered']),
        fireRate: _d(m['fireRate']),
        skipReasons: Map<String, dynamic>.from(
                (m['skipReasons'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k, _i(v))),
        firedWithNoRecipients: _i(m['firedWithNoRecipients']),
      );
}

class EngagementInsight {
  final String id;
  final String severity;
  final String title;
  final String detail;
  final String evidence;
  final String recommendation;

  const EngagementInsight({
    required this.id,
    this.severity = 'info',
    this.title = '',
    this.detail = '',
    this.evidence = '',
    this.recommendation = '',
  });

  factory EngagementInsight.fromMap(Map<String, dynamic> m) =>
      EngagementInsight(
        id: _s(m['id']),
        severity: _s(m['severity']),
        title: _s(m['title']),
        detail: _s(m['detail']),
        evidence: _s(m['evidence']),
        recommendation: _s(m['recommendation']),
      );
}

class TrendPoint {
  final String day;
  final int created;
  final int pushDelivered;
  final int suppressed;
  const TrendPoint(this.day, this.created, this.pushDelivered, this.suppressed);
}

class ReadSummary {
  final double rate;
  final int items;
  final int read;

  /// How many day-cohorts were old enough to count. Zero means the headline
  /// rate is not yet meaningful.
  final int cohorts;
  const ReadSummary({
    this.rate = 0,
    this.items = 0,
    this.read = 0,
    this.cohorts = 0,
  });
}

class EngagementIntelligence {
  final int windowDays;
  final DeliverySummary delivery;
  final int campaignTotal;
  final Map<String, int> campaignStatusMix;
  final List<CampaignPerf> topCampaigns;
  final List<CampaignPerf> worstCampaigns;
  final int ruleCount;
  final int rulesEnabled;
  final int rulesFailing;
  final int automationEvaluations;
  final List<AutomationPerf> automations;
  final Map<String, int> messaging;
  final ReadSummary read;
  final List<TrendPoint> trend;
  final List<EngagementInsight> insights;
  final List<UnavailableMetric> unavailable;

  const EngagementIntelligence({
    this.windowDays = 30,
    this.delivery = const DeliverySummary(),
    this.campaignTotal = 0,
    this.campaignStatusMix = const {},
    this.topCampaigns = const [],
    this.worstCampaigns = const [],
    this.ruleCount = 0,
    this.rulesEnabled = 0,
    this.rulesFailing = 0,
    this.automationEvaluations = 0,
    this.automations = const [],
    this.messaging = const {},
    this.read = const ReadSummary(),
    this.trend = const [],
    this.insights = const [],
    this.unavailable = const [],
  });
}

/// The console's window onto the EP-6 Engagement Intelligence layer.
///
/// Every figure is computed SERVER-SIDE by `getEngagementIntelligence`. The
/// console renders; it does not aggregate. That is the same discipline EP-2
/// established for recipient counts, applied to metrics — one source of truth,
/// so a number on screen cannot disagree with the data behind it.
class IntelligenceService {
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  Future<EngagementIntelligence> load({int days = 30}) async {
    final res = await _fns
        .httpsCallable('getEngagementIntelligence')
        .call({'days': days});
    final m = Map<String, dynamic>.from(res.data as Map);

    Map<String, dynamic> sub(String k) =>
        Map<String, dynamic>.from((m[k] as Map?) ?? const {});
    List<Map<String, dynamic>> list(dynamic v) =>
        ((v as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final d = sub('delivery');
    final change = Map<String, dynamic>.from((d['change'] as Map?) ?? const {});
    double? ch(String k) => (change[k] is num)
        ? (change[k] as num).toDouble()
        : null; // null means "no baseline" — never render it as 0%

    final c = sub('campaigns');
    final a = sub('automations');
    final r = sub('read');

    return EngagementIntelligence(
      windowDays: _i(m['windowDays']),
      delivery: DeliverySummary(
        created: _i(d['created']),
        persisted: _i(d['persisted']),
        pushDelivered: _i(d['pushDelivered']),
        pushFailedOrNoToken: _i(d['pushFailedOrNoToken']),
        suppressedTotal: _i(d['suppressedTotal']),
        suppressedByReason: Map<String, dynamic>.from(
                (d['suppressedByReason'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k, _i(v))),
        persistRate: _d(d['persistRate']),
        pushRate: _d(d['pushRate']),
        suppressionRate: _d(d['suppressionRate']),
        createdChange: ch('created'),
        pushChange: ch('pushDelivered'),
        suppressedChange: ch('suppressed'),
      ),
      campaignTotal: _i(c['total']),
      campaignStatusMix:
          Map<String, dynamic>.from((c['statusMix'] as Map?) ?? const {})
              .map((k, v) => MapEntry(k, _i(v))),
      topCampaigns: list(c['top']).map(CampaignPerf.fromMap).toList(),
      worstCampaigns: list(c['worst']).map(CampaignPerf.fromMap).toList(),
      ruleCount: _i(a['rules']),
      rulesEnabled: _i(a['enabled']),
      rulesFailing: _i(a['failing']),
      automationEvaluations: _i(a['evaluations']),
      automations:
          list(a['effectiveness']).map(AutomationPerf.fromMap).toList(),
      messaging: sub('messaging').map((k, v) => MapEntry(k, _i(v))),
      read: ReadSummary(
        rate: _d(r['rate']),
        items: _i(r['items']),
        read: _i(r['read']),
        cohorts: _i(r['cohorts']),
      ),
      trend: list(m['trend'])
          .map((e) => TrendPoint(_s(e['day']), _i(e['created']),
              _i(e['pushDelivered']), _i(e['suppressed'])))
          .toList(),
      insights: list(m['insights']).map(EngagementInsight.fromMap).toList(),
      unavailable: list(m['unavailable'])
          .map((e) => UnavailableMetric(_s(e['metric']), _s(e['reason'])))
          .toList(),
    );
  }
}
