// ACTION OUTCOMES — the honest words for what a money or moderation call did.
//
// ONE place both refund doors (Revenue and the organization workspace), the
// grant dialog, the status actions and the "Re-apply status effects" action
// read their verdicts from, so two screens can never describe the same
// backend answer two different ways again (the Revenue door titled a lost
// response "Refund failed" and kept a stale dialog open for a second press,
// while the workspace door said "cannot tell").
//
// THE RULE. A call has exactly one of four answers, and the words follow it:
//   • it DID the thing                    → say what it did (server figures)
//   • it DEFINITELY did not               → "not issued / not recorded" +
//                                           "No money moved / Nothing changed"
//   • something equivalent is IN FLIGHT   → "already in progress" (not a
//                                           failure; do not repeat it)
//   • the console CANNOT KNOW             → "outcome unknown". Never titled
//                                           "failed" or "not issued": a lost
//                                           response after the gateway moved
//                                           money is exactly this case, and a
//                                           "failed" title invites a second
//                                           refund.
//
// Backend contract: CONTRACTS C2 (refundPayment), C4 (grantSubscription),
// C6 (reapplyAdminStatusEffects). The console must work against the
// deployed backend too, which predates those details — so every mapping has
// a fallback that reads only the error code.

import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import 'org_moderation_service.dart' show ReapplyResult;
import 'organization_language.dart';
import 'refund_service.dart' show RefundResult;
import 'saas_onboarding_service.dart' show GrantResult;

/// What a refund call did.
enum RefundVerdict {
  /// The gateway accepted a refund (or an earlier attempt of the SAME intent
  /// already had — `replayed`).
  refunded,

  /// Definitely not refunded: refused before the gateway, or the gateway
  /// refused. No money moved.
  notRefunded,

  /// A refund for this payment / intent is already in flight or was just
  /// made (`already-exists`). Not a failure — and not something to repeat.
  inFlight,

  /// The pre-check could not reach the gateway, so NOTHING was sent
  /// (`unavailable` + `details.outcome == not_attempted`).
  notAttempted,

  /// Nobody can tell whether money moved.
  unknown,
}

class RefundOutcome {
  const RefundOutcome({
    required this.verdict,
    required this.title,
    required this.message,
  });

  final RefundVerdict verdict;
  final String title;
  final String message;

  /// The refund dialog closes on every answer except a definite "no": after
  /// a success, an in-flight refund or an UNKNOWN outcome, the same form must
  /// not be one press away from a second refund. The refundable maximum is
  /// recomputed from the live receipt the next time the dialog opens.
  bool get closesDialog =>
      verdict != RefundVerdict.notRefunded &&
      verdict != RefundVerdict.notAttempted;

  /// Whether anything changed: true / false / null = cannot know.
  bool? get changed => switch (verdict) {
    RefundVerdict.refunded => true,
    RefundVerdict.notRefunded || RefundVerdict.notAttempted => false,
    RefundVerdict.inFlight || RefundVerdict.unknown => null,
  };

  bool get ok =>
      verdict == RefundVerdict.refunded || verdict == RefundVerdict.inFlight;
}

/// A banner-ready verdict for the grant / status / re-apply calls.
class ActionVerdict {
  const ActionVerdict({
    required this.ok,
    required this.title,
    required this.message,
    required this.changed,
  });

  final bool ok;
  final String title;
  final String message;

  /// true / false / null = the console cannot know.
  final bool? changed;
}

class ActionOutcomes {
  ActionOutcomes._();

  /// The sentence every unknown outcome carries, verbatim, so a founder
  /// learns to recognise it.
  static const String cannotTell =
      'The console cannot tell whether the change was applied — the record '
      'on screen is live, so check it before retrying.';

  // ── refund ────────────────────────────────────────────────────────────────

  static final Random _rng = Random.secure();
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// A client-generated refund intent id (`[A-Za-z0-9_-]{8,64}`, C2). Made
  /// ONCE per refund dialog opening and reused for every retry from that
  /// dialog, so the server can answer a repeat of the same decision with the
  /// stored outcome instead of reaching the gateway twice.
  static String newRefundIntentId() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = List.generate(
      16,
      (_) => _alphabet[_rng.nextInt(_alphabet.length)],
    ).join();
    return 'rf_${stamp}_$rand';
  }

  static bool isValidIntentId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id);

  /// The backend's post-refund follow-up codes, in words. An unrecognised
  /// code is said to be unrecognised; it is never printed bare as a sentence.
  static String refundWarningWords(String code) => switch (code) {
    'history_stamp_failed' =>
      'the receipt was not updated with this refund yet (an alert is in the '
          'Operations Center) — do not refund again because of it',
    'revoke_failed' =>
      'ending the subscription failed, so the organization still has access '
          '(an alert is in the Operations Center)',
    'revoke_skipped_payment_no_longer_current' =>
      'the subscription was not ended, because this is no longer the '
          'organization\'s current subscription payment',
    _ =>
      'a follow-up step the console does not recognise reported a problem '
          '(reference: $code)',
  };

  static RefundOutcome refundSucceeded(RefundResult r) {
    final minor = r.amountMinor;
    final amount = OrganizationLanguage.rupees(
      minor != null ? minor / 100 : r.amount,
    );
    final stampFailed = r.warnings.contains('history_stamp_failed');
    final others = r.warnings
        .where((w) => w != 'history_stamp_failed')
        .map(refundWarningWords)
        .toList();
    if (r.replayed) {
      return RefundOutcome(
        verdict: RefundVerdict.refunded,
        title: 'Refund already issued',
        message:
            'An earlier attempt of this same refund already returned $amount. '
            'Nothing new was sent to the gateway.'
            '${r.revoked ? ' The subscription was ended.' : ''}',
      );
    }
    final status = switch (r.status) {
      'processed' => ' The gateway has processed it.',
      'created' || 'pending' =>
        ' The gateway accepted it; the money reaches the payer on the '
            'gateway\'s own timeline.',
      _ => '',
    };
    return RefundOutcome(
      verdict: RefundVerdict.refunded,
      title: 'Refund issued',
      message:
          '$amount was sent back through the gateway.$status'
          '${stampFailed ? ' The receipt was NOT updated yet — ${refundWarningWords('history_stamp_failed')}.' : ' The receipt was updated.'}'
          '${r.revoked ? ' The subscription was ended.' : ''}'
          '${others.isEmpty ? '' : ' Follow-up needed: ${others.join('; ')}.'}',
    );
  }

  static String? _detail(Object e, String key) {
    if (e is! FirebaseFunctionsException) return null;
    final d = e.details;
    if (d is Map) {
      final v = d[key];
      return v?.toString();
    }
    return null;
  }

  static RefundOutcome refundFailed(Object e) {
    const noMoney = 'No money moved.';
    if (e is FirebaseFunctionsException) {
      final outcome = _detail(e, 'outcome');
      switch (e.code) {
        case 'failed-precondition':
        case 'invalid-argument':
          return RefundOutcome(
            verdict: RefundVerdict.notRefunded,
            title: 'Refund not issued',
            message:
                '${e.message ?? 'The refund service refused the request.'} '
                '$noMoney',
          );
        case 'not-found':
          return const RefundOutcome(
            verdict: RefundVerdict.notRefunded,
            title: 'Refund not issued',
            message: 'That receipt or payment no longer exists. $noMoney',
          );
        case 'permission-denied':
          return const RefundOutcome(
            verdict: RefundVerdict.notRefunded,
            title: 'Refund not issued',
            message:
                'Your account is not a platform super-admin, so it cannot '
                'refund. $noMoney',
          );
        case 'unauthenticated':
          return const RefundOutcome(
            verdict: RefundVerdict.notRefunded,
            title: 'Refund not issued',
            message: 'Your session expired. Sign in again. $noMoney',
          );
        case 'resource-exhausted':
          return RefundOutcome(
            verdict: RefundVerdict.notRefunded,
            title: 'Refund not issued',
            message:
                '${e.message ?? 'Too many requests right now.'} $noMoney '
                'Wait a moment before trying again.',
          );
        case 'already-exists':
          return const RefundOutcome(
            verdict: RefundVerdict.inFlight,
            title: 'A refund is already in progress',
            message:
                'A refund for this payment was just made or is still being '
                'processed, so this request was not sent again. The receipt '
                'updates when the gateway confirms — check it before '
                'refunding anything more.',
          );
        case 'unavailable':
          if (outcome == 'not_attempted') {
            return const RefundOutcome(
              verdict: RefundVerdict.notAttempted,
              title: 'Refund not attempted',
              message:
                  'The refund service could not reach the payment gateway to '
                  'check this payment, so nothing was sent. $noMoney You can '
                  'try again.',
            );
          }
      }
      return RefundOutcome(
        verdict: RefundVerdict.unknown,
        title: 'Refund outcome unknown',
        message:
            'The console cannot tell whether the gateway refunded this '
            'payment. Do NOT refund again yet: check the receipt and the '
            'Razorpay dashboard first.'
            '${outcome == 'unknown' ? ' The backend flagged it for review in the Operations Center.' : ''}',
      );
    }
    return const RefundOutcome(
      verdict: RefundVerdict.unknown,
      title: 'Refund outcome unknown',
      message:
          'The connection dropped before the refund service answered, so the '
          'console cannot tell whether the gateway refunded this payment. Do '
          'NOT refund again yet: check the receipt and the Razorpay dashboard '
          'first.',
    );
  }

  // ── generic verdict on a callable failure ─────────────────────────────────

  /// Whether the backend refused BEFORE writing. `unavailable` with
  /// `details.outcome == not_attempted` is a definite no-op; any other
  /// transport failure (network, deadline, `internal`) is unknown.
  static bool? changedVerdict(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'invalid-argument':
        case 'failed-precondition':
        case 'not-found':
        case 'permission-denied':
        case 'unauthenticated':
        case 'already-exists':
        case 'resource-exhausted':
          return false;
        case 'unavailable':
          if (_detail(e, 'outcome') == 'not_attempted') return false;
      }
    }
    return null;
  }

  // ── grant ─────────────────────────────────────────────────────────────────

  static const _legacyReferenceRefusal = 'already recorded';

  /// The words after `grantSubscription` refused or failed. [reference] is
  /// the reference the founder typed; [friendly] maps the remaining codes.
  static ActionVerdict grantFailed(
    Object e, {
    required String reference,
    required String Function(Object e) friendly,
  }) {
    final changed = changedVerdict(e);
    if (e is FirebaseFunctionsException) {
      final reason = _detail(e, 'reason');
      if (e.code == 'failed-precondition') {
        switch (reason) {
          case 'price_changed':
            final list = double.tryParse(_detail(e, 'listPrice') ?? '');
            final months = int.tryParse(_detail(e, 'listTermMonths') ?? '');
            return ActionVerdict(
              ok: false,
              title: 'The plan price changed — nothing recorded',
              message:
                  'The plan\'s list price for this term is now '
                  '${list == null ? 'different' : OrganizationLanguage.rupees(list)}'
                  '${months == null ? '' : ' for ${OrganizationLanguage.plural(months, 'month')}'}'
                  ', not the price this dialog showed. Nothing was recorded. '
                  'Open Record payment again to see the current price.',
              changed: false,
            );
          case 'reference_already_recorded':
            final same = _detail(e, 'sameOrganization');
            final at = DateTime.tryParse(_detail(e, 'recordedAt') ?? '');
            final when = at == null
                ? ''
                : ' on ${OrganizationLanguage.exact(at.toLocal())}';
            if (same == 'true') {
              return ActionVerdict(
                ok: true,
                title: 'Already recorded on this organization',
                message:
                    'Reference $reference is already on a receipt for this '
                    'organization$when. This attempt recorded nothing new and '
                    'extended nothing — if you were retrying after an unclear '
                    'result, the first attempt went through. Check the '
                    'receipts below.',
                changed: false,
              );
            }
            if (same == 'false') {
              return ActionVerdict(
                ok: false,
                title: 'Reference already used on another organization',
                message:
                    'Reference $reference was recorded$when on a DIFFERENT '
                    'organization. Nothing was recorded here. A payment '
                    'reference can be recorded once — check it with the payer '
                    'before doing anything else.',
                changed: false,
              );
            }
          case 'activated_online':
            return ActionVerdict(
              ok: false,
              title: 'Already activated online',
              message:
                  'Payment $reference was already used by an online '
                  'activation, so recording it by hand would count the same '
                  'money twice. Nothing was recorded.',
              changed: false,
            );
        }
        // The deployed backend refuses a reused reference with this message
        // and no details. After a lost response the founder's natural retry
        // lands here, so it must NOT read "Payment not recorded … Nothing was
        // changed" — the first attempt may be exactly what recorded it.
        if ((e.message ?? '').contains(_legacyReferenceRefusal)) {
          return ActionVerdict(
            ok: false,
            title: 'Reference already recorded',
            message:
                'Reference $reference is already on file, so this attempt '
                'recorded nothing. If you were retrying after an unclear '
                'result, the earlier attempt may be the one that recorded it: '
                'check this organization\'s receipts before doing anything '
                'else. If it is not there, the reference belongs to another '
                'organization.',
            changed: false,
          );
        }
      }
      if (e.code == 'not-found' && (e.message ?? '').contains('Plan')) {
        return const ActionVerdict(
          ok: false,
          title: 'Payment not recorded',
          message:
              'The plan was deleted while this dialog was open. Nothing was '
              'recorded — choose a published plan and try again.',
          changed: false,
        );
      }
      if (e.code == 'unavailable' && changed == false) {
        return const ActionVerdict(
          ok: false,
          title: 'Payment not recorded',
          message:
              'The server could not start the change, so nothing was '
              'attempted. Nothing was changed. You can try again.',
          changed: false,
        );
      }
    }
    if (changed == false) {
      return ActionVerdict(
        ok: false,
        title: 'Payment not recorded',
        message: '${friendly(e)} Nothing was changed.',
        changed: false,
      );
    }
    return const ActionVerdict(
      ok: false,
      title: 'Payment outcome unknown',
      message:
          'The server did not answer, so the console cannot tell whether the '
          'payment was recorded. $cannotTell The receipts reload now. Retrying '
          'with the SAME reference is safe: if the first attempt went through, '
          'the server refuses to record it twice.',
      changed: null,
    );
  }

  /// A grant the server answered `replayed: true` — the same request was
  /// already recorded; the server recorded nothing new.
  static ActionVerdict grantReplayed(
    GrantResult r, {
    required String name,
  }) => ActionVerdict(
    ok: true,
    title: 'Already recorded',
    message:
        'This exact payment was already recorded for $name — nothing new '
        'was charged or extended.'
        '${r.expiry == null ? '' : ' The plan runs until ${OrganizationLanguage.exact(DateTime.tryParse(r.expiry!))}.'}',
    changed: false,
  );

  // ── status ────────────────────────────────────────────────────────────────

  static ActionVerdict statusFailed(
    Object e, {
    required String Function(Object e) friendly,
  }) {
    final changed = changedVerdict(e);
    if (changed == false) {
      return ActionVerdict(
        ok: false,
        title: 'Could not change the status',
        message: '${friendly(e)} Nothing was changed.',
        changed: false,
      );
    }
    return const ActionVerdict(
      ok: false,
      title: 'Status change outcome unknown',
      message:
          'The moderation service did not answer, so the change may or may '
          'not have been applied. $cannotTell',
      changed: null,
    );
  }

  // ── re-apply status effects (C6) ──────────────────────────────────────────

  static String _leg(String v) => switch (v) {
    'ok' => 'succeeded',
    'failed' => 'FAILED',
    'skipped' => 'was not needed',
    _ => 'did not report',
  };

  static ActionVerdict reapplySucceeded(
    ReapplyResult r, {
    required String name,
  }) {
    final allOk = r.cascade == 'ok' && (r.auth == 'ok' || r.auth == 'skipped');
    if (allOk) {
      return ActionVerdict(
        ok: true,
        title: 'Status effects re-applied',
        message:
            'Trainer access${r.auth == 'ok' ? ' and the owner\'s sign-in' : ''} '
            'were re-run for $name\'s current status'
            '${r.status.isEmpty ? '' : ' (${r.status})'}. The status did not '
            'change and nobody was notified. The backend resolves the '
            'matching open incidents.',
        changed: true,
      );
    }
    return ActionVerdict(
      ok: false,
      title: 'Re-apply did not fully succeed',
      message:
          'For $name: the trainer access sync ${_leg(r.cascade)}; the owner '
          'sign-in enforcement ${_leg(r.auth)}. The incident stays open — try '
          'again, and report it if it keeps failing.',
      changed: true,
    );
  }

  static ActionVerdict reapplyFailed(
    Object e, {
    required String Function(Object e) friendly,
  }) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'not-found':
        case 'unimplemented':
          return const ActionVerdict(
            ok: false,
            title: 'Not available on this backend yet',
            message:
                'Re-applying status effects needs a backend function '
                '(reapplyAdminStatusEffects) that is not deployed to this '
                'project yet. Nothing was changed. Until it ships, a blocked '
                'owner\'s sign-in can be disabled by hand in Firebase '
                'Authentication.',
            changed: false,
          );
        case 'internal':
        case 'unavailable':
        case 'deadline-exceeded':
        case 'unknown':
          break;
        default:
          return ActionVerdict(
            ok: false,
            title: 'Could not re-apply status effects',
            message: '${friendly(e)} Nothing was changed.',
            changed: false,
          );
      }
    }
    return const ActionVerdict(
      ok: false,
      title: 'Re-apply outcome unknown',
      message:
          'The call got no answer. On the web a backend function that is not '
          'deployed yet fails exactly like this, so this action may not be '
          'available on this backend yet. Re-applying is safe to repeat: it '
          'never changes the status and never notifies anyone. $cannotTell',
      changed: null,
    );
  }
}
