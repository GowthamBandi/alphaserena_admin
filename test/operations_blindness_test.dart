// A TRIAGE SURFACE MAY RUN OUT OF ROWS. IT MAY NEVER SAY "ALL CLEAR" WHEN IT
// CANNOT SEE.
//
// 🔴 THE DEFECT THIS GUARDS. The Operations Center is the founder's daily "what
// needs me across the platform" home. It DERIVES most of its feed from three
// other controllers — AdminController (pending approvals, lapsed and expiring
// subscriptions, orgs under moderation), SupportController (open complaints,
// critical reviews) and CommunicationController (failed / stuck campaigns).
//
// It already raised a warning card when its OWN two streams failed
// (`incidentsError`, `telemetryError`). It raised nothing at all when a DERIVED
// source failed. Those controllers set `isLoading = false` and leave their list
// empty on error, so `anyLoading` went false, `alerts` came back empty, and the
// screen rendered a green **"All clear"** over a platform it could not read.
//
// That is the worst failure mode in this console: every other broken screen
// looks broken, and this one looks fine.
//
// The fix follows the pattern already in `alerts` for the controller's own
// streams — one card per unavailable feed, naming what is hidden.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _denied = ConsoleError(
  kind: ConsoleErrorKind.permission,
  message: 'Firestore refused this read.',
);

class _OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineSupport extends SupportController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineComms extends CommunicationController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineOps extends OperationsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Registers the three derived sources in a healthy, finished-loading state.
({_OfflineAdmins admins, _OfflineSupport support, _OfflineComms comms})
    _healthySources() {
  final admins = Get.put<AdminController>(_OfflineAdmins(), permanent: true)
      as _OfflineAdmins;
  final support = Get.put<SupportController>(_OfflineSupport(), permanent: true)
      as _OfflineSupport;
  final comms = Get.put<CommunicationController>(_OfflineComms(),
      permanent: true) as _OfflineComms;
  admins.isLoading.value = false;
  support.feedbackLoading.value = false;
  support.reviewsLoading.value = false;
  comms.isLoading.value = false;
  return (admins: admins, support: support, comms: comms);
}

/// An Operations controller whose own two feeds have loaded cleanly, so any
/// alert it produces comes from the derived sources and nothing else.
_OfflineOps _opsWithOwnFeedsHealthy() {
  final ops = _OfflineOps();
  ops.telemetryLoaded.value = true;
  ops.incidentsLoaded.value = true;
  return ops;
}

bool _mentionsUnavailable(OperationsController ops, String needle) =>
    ops.alerts.any((a) =>
        a.title.toLowerCase().contains(needle) ||
        a.detail.toLowerCase().contains(needle));

void main() {
  tearDown(Get.reset);

  test('CONTROL — healthy, empty sources genuinely are "all clear"', () {
    // Without this the fix could pass every test below by always raising an
    // alert, which would make the screen permanently red and equally useless.
    _healthySources();
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.anyLoading, isFalse);
    expect(ops.alerts, isEmpty, reason: 'nothing is wrong, so say nothing');
  });

  test('a failed ORGANIZATIONS stream must not read as "all clear"', () {
    final s = _healthySources();
    s.admins.loadError.value = _denied;
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.alerts, isNotEmpty,
        reason: 'pending approvals, lapsed and expiring subscriptions and '
            'orgs under moderation are ALL derived from this stream');
    expect(_mentionsUnavailable(ops, 'organization'), isTrue);
  });

  test('a failed SUPPORT stream must not read as "all clear"', () {
    final s = _healthySources();
    s.support.feedbackError.value = true;
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.alerts, isNotEmpty);
    expect(_mentionsUnavailable(ops, 'support'), isTrue);
  });

  test('a failed REVIEWS stream must not read as "all clear"', () {
    final s = _healthySources();
    s.support.reviewsError.value = true;
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.alerts, isNotEmpty);
  });

  test('a failed CAMPAIGN stream must not read as "all clear"', () {
    final s = _healthySources();
    s.comms.hasError.value = true;
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.alerts, isNotEmpty);
    expect(_mentionsUnavailable(ops, 'campaign'), isTrue);
  });

  test('an UNREGISTERED source is a blind spot too, not a clear one', () {
    // At boot a source controller may not be registered yet. `sourcesReady`
    // knows this; `alerts` did not.
    Get.reset();
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.sourcesReady, isFalse);
    expect(ops.anyLoading, isTrue,
        reason: 'a missing source is "still loading", never "all clear"');
  });

  test('every derived failure is reported at once, not just the first', () {
    final s = _healthySources();
    s.admins.loadError.value = _denied;
    s.support.feedbackError.value = true;
    s.comms.hasError.value = true;
    final ops = _opsWithOwnFeedsHealthy();

    expect(ops.alerts.length, greaterThanOrEqualTo(3),
        reason: 'an operator fixing one feed must still see the other two');
  });
}
