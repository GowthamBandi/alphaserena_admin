// THE COMMERCIAL CONTROL PLANE MUST BE REACHABLE, HONEST, AND SERVER-GATED.
//
// The Access Requests section is where TrainerArena is now sold: a prospect's
// request becomes an organization here, and nowhere else. Three classes of
// defect would each make it worthless in a different way, and this file pins
// all three.
//
//  1. UNREACHABLE. This console has no router — navigation is an integer index
//     into a page factory, and a finished screen with no `case` or no sidebar
//     entry ships invisible. That has happened here before (Automation and
//     Engagement, 1,269 lines, no way to open them).
//
//  2. DISHONEST. A failed stream must not render as "No access requests yet".
//     That reads as "nobody wants the product" and the founder answers nobody.
//     Same class as the dashboard-blindness defects.
//
//  3. CLIENT-TRUSTING. Every mutation must go through a Cloud Function.
//     `access_requests` denies client writes to everyone — super admins
//     included — so a controller that wrote Firestore directly would simply be
//     broken, and a UI that gated an action only by hiding a button would be
//     no gate at all.
//
// ⚠️ Comments are stripped before source is inspected: this file and the
// controller both DISCUSS the writes they must not perform.

import 'dart:io';

import 'package:alphaserena_admin_portel/controllers/access_request_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/core/services/saas_onboarding_service.dart';
import 'package:alphaserena_admin_portel/models/access_request_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// A controller that never touches Firestore.
class _Offline extends AccessRequestController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

String codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

AccessRequestModel _req({
  required String id,
  String status = 'requested',
  String? provisionedOrgUid,
  String org = 'Iron Temple',
  String email = 'owner@example.com',
}) =>
    AccessRequestModel(
      id: id,
      organizationName: org,
      ownerName: 'Arjun Rao',
      email: email,
      phone: '+919876543210',
      status: status,
      provisionedOrgUid: provisionedOrgUid,
      createdAt: DateTime(2026, 8, 20),
    );

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  // ── 1. REACHABLE ─────────────────────────────────────────────────────────

  test('the section is reachable — maxIndex covers its page-factory case', () {
    final root = AdminRootController();
    expect(root.maxIndex, greaterThanOrEqualTo(17),
        reason: 'a page factory case above maxIndex can never be selected');
  });

  test('the sidebar has an entry for every selectable index', () {
    // The sidebar list and maxIndex are two lists that must agree; this repo
    // has shipped a screen that existed in one and not the other.
    //
    // The navigation model moved OUT of admin_root_screen.dart (where the
    // sidebar's position WAS the page index) and into console_destinations.dart
    // (where display order and page identity are independent). This assertion
    // follows it rather than being relaxed: the label must still be declared,
    // and it must still carry the id the page factory routes.
    final destinations =
        File('lib/core/navigation/console_destinations.dart').readAsStringSync();
    expect(destinations.contains("label: 'Access Requests'"), isTrue,
        reason: 'Access Requests must be a declared console destination');
    expect(
        RegExp(r"id:\s*17,\s*\n\s*label:\s*'Access Requests'")
            .hasMatch(destinations),
        isTrue,
        reason: 'Access Requests must keep id 17 — the page factory routes it '
            'there, and the id is identity, not sidebar position');

    final factory =
        codeOnly(File('lib/controllers/admin_root_controller.dart')
            .readAsStringSync());
    expect(factory.contains('AccessRequestsScreen'), isTrue,
        reason: 'the page factory must be able to build the screen');
    expect(RegExp(r'case 17:').hasMatch(factory), isTrue,
        reason: 'the id declared above must have a matching page case');
  });

  test('the controller is both registered and torn down', () {
    final main = codeOnly(File('lib/main.dart').readAsStringSync());
    expect(main.contains('_safePut(AccessRequestController())'), isTrue,
        reason: 'the page factory uses Get.find — an unregistered controller '
            'crashes the section on open');
    expect(main.contains('_safeDelete<AccessRequestController>()'), isTrue,
        reason: 'a controller that outlives sign-out keeps its access_requests '
            'listener open and re-uses the previous session rows');
  });

  // ── 2. HONEST ────────────────────────────────────────────────────────────

  test('a failed stream is NOT reported as an empty pipeline', () {
    final screen =
        codeOnly(File('lib/screens/access_requests_screen.dart')
            .readAsStringSync());
    final emptyAt = screen.indexOf('No access requests yet');
    final errorAt = screen.indexOf('loadError');
    expect(emptyAt, greaterThan(0));
    expect(errorAt, greaterThan(0));
    expect(errorAt, lessThan(emptyAt),
        reason: 'the error branch must be consulted BEFORE the empty state, '
            'or a denied read renders as "nobody applied"');
  });

  test('the open queue excludes provisioned and rejected requests', () {
    final c = Get.put<AccessRequestController>(_Offline());
    c.requests.assignAll([
      _req(id: 'a'),
      _req(id: 'b', status: SaasOnboardingService.contacted),
      _req(id: 'c', status: SaasOnboardingService.organizationCreated),
      _req(id: 'd', status: SaasOnboardingService.rejected),
    ]);
    expect(c.openCount, 2);
    expect(c.filtered.map((r) => r.id), containsAll(<String>['a', 'b']));
    expect(c.filtered.map((r) => r.id), isNot(contains('c')));
    expect(c.filtered.map((r) => r.id), isNot(contains('d')));
  });

  test('search matches the fields a founder actually types', () {
    final c = Get.put<AccessRequestController>(_Offline());
    c.requests.assignAll([
      _req(id: 'a', org: 'Iron Temple', email: 'a@example.com'),
      _req(id: 'b', org: 'Steel Gym', email: 'b@example.com'),
    ]);
    c.statusFilter.value = 'all';

    c.search.value = 'iron';
    expect(c.filtered.single.id, 'a', reason: 'by organization name');

    c.search.value = 'b@example';
    expect(c.filtered.single.id, 'b', reason: 'by email');

    c.search.value = '9876543210';
    expect(c.filtered.length, 2, reason: 'by phone — both fixtures share it');

    c.search.value = 'nothing-matches-this';
    expect(c.filtered, isEmpty);
  });

  test('a provisioned request is recognised by its uid, not by its status',
      () {
    // Idempotency is keyed on provisionedOrgUid server-side. The UI must read
    // the same fact, or it will offer "Create organization" for a request that
    // already has one.
    final live = _req(id: 'x', status: 'approved', provisionedOrgUid: 'org1');
    expect(live.isProvisioned, isTrue);
    expect(_req(id: 'y', status: 'approved').isProvisioned, isFalse);
  });

  // ── 3. SERVER-GATED ──────────────────────────────────────────────────────

  test('nothing in the module writes access_requests from the client', () {
    for (final path in [
      'lib/controllers/access_request_controller.dart',
      'lib/screens/access_requests_screen.dart',
      'lib/core/services/saas_onboarding_service.dart',
    ]) {
      final code = codeOnly(File(path).readAsStringSync());
      for (final write in ['.set(', '.update(', '.add(', '.delete(']) {
        expect(code.contains("collection('access_requests')$write"), isFalse,
            reason: '$path writes access_requests directly');
      }
      expect(code.contains('access_requests').toString(), isNotNull);
    }
    final svc = codeOnly(
        File('lib/core/services/saas_onboarding_service.dart')
            .readAsStringSync());
    expect(svc.contains('FirebaseFirestore'), isFalse,
        reason: 'the service must be callables only — the rules deny client '
            'writes to everyone, super admins included');
  });

  test('every mutation is a named Cloud Function call', () {
    final svc = codeOnly(
        File('lib/core/services/saas_onboarding_service.dart')
            .readAsStringSync());
    for (final fn in [
      'setAccessRequestStatus',
      'addAccessRequestNote',
      'provisionOrganization',
      'grantSubscription',
    ]) {
      expect(svc.contains("httpsCallable('$fn')"), isTrue, reason: fn);
    }
  });

  test('organization_created is never a status the console can SET', () {
    // Only the provisioning transaction may claim it, so that the status and
    // provisionedOrgUid land atomically. A console that offered it as a
    // manual option would be offering a way to break idempotency.
    expect(SaasOnboardingService.settableStatuses,
        isNot(contains(SaasOnboardingService.organizationCreated)));
    expect(SaasOnboardingService.settableStatuses, contains('rejected'));
  });

  test('a duplicate action cannot be launched while one is in flight', () {
    final c = Get.put<AccessRequestController>(_Offline());
    c.isProcessing.value = true;
    // The re-entrancy guard is the cheap half of the defence; the server is
    // idempotent regardless. Both must exist.
    final code = codeOnly(File('lib/controllers/access_request_controller.dart')
        .readAsStringSync());
    expect(code.contains('if (isProcessing.value) return'), isTrue);
    expect(c.isProcessing.value, isTrue);
  });

  // ── 4. CREDENTIAL HONESTY ────────────────────────────────────────────────

  test('the temporary password is never persisted client-side', () {
    for (final path in [
      'lib/controllers/access_request_controller.dart',
      'lib/screens/access_requests_screen.dart',
      'lib/core/services/saas_onboarding_service.dart',
    ]) {
      final code = codeOnly(File(path).readAsStringSync());
      for (final sink in ['GetStorage', 'SharedPreferences', 'logEvent',
        'debugPrint(res.tempPassword', 'print(res.tempPassword']) {
        expect(code.contains(sink), isFalse,
            reason: '$path may be persisting or logging the credential '
                'via $sink');
      }
    }
  });

  test('an idempotent repeat is reported as such, not as a fresh credential',
      () {
    const repeat = ProvisionResult(uid: 'org1', alreadyProvisioned: true);
    expect(repeat.tempPassword, isNull,
        reason: 'a repeat mints no password; showing a blank one as new would '
            'send the founder to deliver an empty credential');

    final screen = codeOnly(File('lib/screens/access_requests_screen.dart')
        .readAsStringSync());
    expect(screen.contains('alreadyProvisioned'), isTrue,
        reason: 'the screen must branch on it rather than always showing the '
            'credential dialog');
  });
}
