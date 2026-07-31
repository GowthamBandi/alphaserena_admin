import 'package:cloud_functions/cloud_functions.dart';

import '../../models/platform_announcement_model.dart';

/// A backend-computed recipient preview.
///
/// Every number here comes from the SAME resolver the fan-out uses
/// (`resolveRecipients`), so what the founder reads before sending is what the
/// worker will deliver to — not an estimate computed a second way.
class AudiencePreview {
  final int total;
  final int owners;
  final int trainers;
  final int members;

  /// Selected or referenced ids that resolved to no existing account — a
  /// deleted entity, or a member record whose profile is gone. Never counted
  /// as recipients; surfaced so a selection/count gap is explainable.
  final int skipped;

  const AudiencePreview({
    this.total = 0,
    this.owners = 0,
    this.trainers = 0,
    this.members = 0,
    this.skipped = 0,
  });

  /// A plain-language breakdown, omitting the roles that aren't involved.
  String get breakdown {
    final parts = <String>[
      if (owners > 0) '$owners owner${owners == 1 ? '' : 's'}',
      if (trainers > 0) '$trainers trainer${trainers == 1 ? '' : 's'}',
      if (members > 0) '$members member${members == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? 'No recipients' : parts.join(' · ');
  }
}

/// One selectable entity in a targeting picker.
class TargetCandidate {
  final String id;
  final String title;
  final String subtitle;
  const TargetCandidate(this.id, this.title, this.subtitle);
}

/// The console's window onto the backend Targeting Engine (EP-2).
///
/// This console NEVER resolves recipients. It names an audience and asks the
/// backend who that reaches. Resolution lives in exactly one place — the
/// server — so the count on screen and the delivery cannot disagree, and a
/// console bug can never widen an audience.
class TargetingService {
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  /// Recipient count + role breakdown for an audience.
  Future<AudiencePreview> preview(
    AnnouncementAudience audience,
    List<String> targetIds,
  ) async {
    final res = await _fns.httpsCallable('previewAudience').call({
      'audience': audience.id,
      // Only selection audiences carry ids; the backend rejects a stale
      // selection left on a broad audience, so don't send one.
      'targetIds': audience.needsSelection ? targetIds : <String>[],
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    return AudiencePreview(
      total: n('total'),
      owners: n('owners'),
      trainers: n('trainers'),
      members: n('members'),
      skipped: n('skipped'),
    );
  }

  /// Candidates for a selection picker. Display data only — no targeting
  /// decision is made here.
  Future<({List<TargetCandidate> results, bool truncated})> search(
    TargetIdKind kind, {
    String query = '',
    int limit = 50,
  }) async {
    final res = await _fns.httpsCallable('searchTargets').call({
      'kind': kind.name,
      'query': query,
      'limit': limit,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    final raw = (m['results'] as List?) ?? const [];
    return (
      results: raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => TargetCandidate(
                (e['id'] ?? '').toString(),
                (e['title'] ?? '').toString(),
                (e['subtitle'] ?? '').toString(),
              ))
          .toList(),
      truncated: m['truncated'] == true,
    );
  }
}
