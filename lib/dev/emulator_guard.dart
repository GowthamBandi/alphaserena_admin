// ============================================================================
// EMULATOR GUARD — proves, at RUNTIME, that every Firebase service this console
// touches is bound to the local emulator, and BLOCKS the console if it is not.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS EXISTS
// ─────────────────────────────────────────────────────────────────────────────
// During Settlement V1 testing the console was launched with
// `--dart-define=USE_FIREBASE_EMULATOR=true`, the launch config said emulator,
// and the app nevertheless came up signed in to the PRODUCTION project. The
// flag had not reached the running process. Nothing was written — but the next
// click would have been a financial mutation against a live ledger.
//
// The lesson is not "be careful with the flag". It is that a build-time flag is
// an INTENTION, and money needs a PROOF. So this file asks the four services
// where they actually are, and fails CLOSED: if any answer is not the emulator,
// the console does not render at all.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHAT COUNTS AS PROOF (and why each check is the strongest one available)
// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE  — reads, as the signed-in founder, a document that exists ONLY in
//              the emulator. A proof of BINDING, not of configuration: the
//              bytes came back, so the SDK is genuinely talking to the
//              emulator. (`Settings.host` looks like the obvious check and is
//              useless on web — it is never written by `useFirestoreEmulator`
//              on that platform.)
// STORAGE    — `getDownloadURL()` of a real settlement proof object. The
//              returned URL CONTAINS the host that will serve the bytes, so
//              this is a true endpoint reading, and it exercises exactly the
//              path the transfer feature uses.
// AUTH       — the signed-in uid must equal the uid recorded in an
//              emulator-only sentinel document. Auth exposes no host getter in
//              Dart, so identity is used instead: a production account cannot
//              have the uid that the emulator seeder wrote into the emulator's
//              own Firestore (already proven emulator by the check above).
//              This is what would have caught the incident: the console was
//              signed in as a production user whose uid is not the fixture's.
// FUNCTIONS  — verified OUT OF BAND rather than guessed at here: the callable's
//              invocation appears in the functions-emulator log, and the
//              browser's network log shows the request going to localhost:5001.
//              A weak in-app inference (comparing returned totals) would be
//              worse than an honest external check, so this file does not
//              pretend to prove it — see `functionsNote`.
//
// Debug-only by construction: `main.dart` calls this exclusively inside the
// `kDebugMode && USE_FIREBASE_EMULATOR` branch, so a release build never
// reaches it.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Firestore document the seeder writes; exists ONLY in the emulator.
const String kEmulatorSentinelDoc = 'platform_config/emulator_sentinel';

/// Storage object the seeder writes; exists ONLY in the emulator.
///
/// NOT used for the pre-login proof: Storage rules deny every read to an
/// unauthenticated caller, so a pre-login `getDownloadURL()` fails for the
/// wrong reason and would prove nothing. Storage is proven AFTER sign-in
/// against a REAL settlement proof object — see [proveEmulatorSession] — which
/// has the additional merit of exercising the exact path the feature uses.
const String kEmulatorSentinelObject = 'emulator_probe/sentinel.txt';

/// One service's answer to "where are you actually pointing?".
class ServiceProof {
  final String service;
  final bool ok;

  /// The evidence itself — an endpoint, a URL, a uid. Shown verbatim, because
  /// a proof an operator cannot read is not a proof.
  final String evidence;
  final String detail;

  const ServiceProof({
    required this.service,
    required this.ok,
    required this.evidence,
    this.detail = '',
  });
}

class EmulatorProof {
  final List<ServiceProof> proofs;
  final String host;

  const EmulatorProof({required this.proofs, required this.host});

  bool get allProven => proofs.every((p) => p.ok);
  Iterable<ServiceProof> get failures => proofs.where((p) => !p.ok);

  /// Stated honestly: Functions cannot be endpoint-proven from Dart, and is
  /// confirmed from the emulator's own invocation log instead.
  static const String functionsNote =
      'Functions: no host getter exists in the Dart SDK. Confirmed externally '
      'via the functions-emulator invocation log and the browser network log '
      '(localhost:5001).';

  String get report {
    final b = StringBuffer('EMULATOR PROOF (host $host)\n');
    for (final p in proofs) {
      b.writeln('  ${p.ok ? "PASS" : "FAIL"}  ${p.service.padRight(10)} '
          '${p.evidence}${p.detail.isEmpty ? "" : "  — ${p.detail}"}');
    }
    b.writeln('  NOTE  $functionsNote');
    return b.toString();
  }
}

bool _isLocal(String s, String host) =>
    s.contains(host) || s.contains('localhost') || s.contains('127.0.0.1');

/// PRE-LOGIN: THERE IS DELIBERATELY NO BLOCKING PROOF HERE.
///
/// The first version of this guard read an emulator-only sentinel document
/// before the login screen. That worked, but it required a PUBLIC-READ rule in
/// `firestore.rules` — a production security posture bent to serve a
/// development concern. The rule has been removed, and this stage went with it.
///
/// Nothing is lost that matters. Every proof this guard exists to provide is
/// still enforced, one step later and BEFORE the console renders:
///
///   • Signing in is itself an Auth probe. `founder@emulator.test` exists only
///     inside the local Auth emulator, so a build wired to production simply
///     cannot authenticate it.
///   • [proveEmulatorSession] then blocks the console unless the signed-in uid
///     matches the emulator's own sentinel AND a real proof object resolves to
///     a localhost URL.
///
/// The safety property is unchanged: **no surface that can move money renders
/// on an unproven environment.** A login screen is not such a surface.
Future<EmulatorProof> proveEmulatorEndpoints({required String host}) async {
  return EmulatorProof(host: host, proofs: const []);
}

/// POST-LOGIN PROOF. Runs after sign-in and BEFORE the console is rendered.
///
/// This is the check that would have caught the incident: the console came up
/// signed in to a production account. Identity, not configuration, is the
/// evidence — a production user cannot have the uid the emulator's own seeder
/// wrote into the emulator's own Firestore.
///
/// Storage is proven here rather than pre-login because its rules deny
/// unauthenticated reads. [settlementProofPath] should be a real
/// `settlement_proofs/…` object, so the proof exercises the exact path the
/// transfer feature uses; the returned download URL names the host that will
/// serve the bytes, which is a true endpoint reading.
Future<EmulatorProof> proveEmulatorSession({
  required String host,
  String? settlementProofPath,
}) async {
  final proofs = <ServiceProof>[];

  // ── AUTH (by identity) ────────────────────────────────────────────────────
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    proofs.add(const ServiceProof(
      service: 'Auth',
      ok: false,
      evidence: '(nobody signed in)',
    ));
  } else {
    try {
      final snap =
          await FirebaseFirestore.instance.doc(kEmulatorSentinelDoc).get();
      final expected = (snap.data()?['founderUid'] ?? '').toString();
      final email = (snap.data()?['founderEmail'] ?? '').toString();
      final ok = expected.isNotEmpty && expected == user.uid;
      // The same read proves TWO different things, so it is reported twice:
      // that the bytes came back at all is the Firestore binding proof; that
      // the uid inside them matches the caller is the Auth proof.
      proofs.add(ServiceProof(
        service: 'Firestore',
        ok: snap.exists && snap.data()?['isEmulator'] == true,
        evidence: snap.exists
            ? 'read $kEmulatorSentinelDoc'
            : 'sentinel ABSENT — this database is not the emulator',
        detail: snap.exists
            ? 'emulator-only data came back, so the SDK is bound to the emulator'
            : 'PRODUCTION, or an unseeded emulator',
      ));
      proofs.add(ServiceProof(
        service: 'Auth',
        ok: ok,
        evidence: '${user.email} (${user.uid})',
        detail: ok
            ? 'uid matches the emulator sentinel'
            : 'NOT the emulator founder — expected $email ($expected). '
                'This session belongs to a DIFFERENT project.',
      ));
    } catch (e) {
      proofs.add(ServiceProof(
        service: 'Auth',
        ok: false,
        evidence: '${user.email} (${user.uid})',
        detail: 'emulator sentinel unreadable: $e',
      ));
    }
  }

  // ── STORAGE (by served host) ──────────────────────────────────────────────
  //
  // The object probed is a REAL settlement proof, discovered from Firestore
  // rather than hardcoded. Two reasons, both learned the hard way:
  //   • A dedicated probe path (`emulator_probe/…`) has no Storage rule, so
  //     reading it fails `unauthorized` even on a perfectly healthy emulator —
  //     a guard that cannot pass is not a guard.
  //   • Probing the path the TRANSFER FEATURE actually uses proves the thing
  //     that matters: that a proof download resolves to the emulator.
  String path = settlementProofPath ?? '';
  if (path.isEmpty) {
    try {
      final q = await FirebaseFirestore.instance
          .collection('settlements')
          .where('status', isEqualTo: 'settled')
          .limit(5)
          .get();
      for (final d in q.docs) {
        final p = (d.data()['proof']?['storagePath'] ?? '').toString();
        if (p.isNotEmpty) {
          path = p;
          break;
        }
      }
    } catch (_) {
      // Falls through to the "no proof object" branch below.
    }
  }

  if (path.isEmpty) {
    proofs.add(const ServiceProof(
      service: 'Storage',
      ok: false,
      evidence: 'no settled settlement carries a proof object',
      detail: 'nothing to resolve a download URL against — run '
          'scripts/seed_settlement_fixtures.sh, which settles one fixture '
          'with a real proof',
    ));
  } else {
    String url = '';
    bool storageOk = false;
    try {
      url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      storageOk = _isLocal(url, host);
    } catch (e) {
      url = 'unreadable ($e)';
    }
    proofs.add(ServiceProof(
      service: 'Storage',
      ok: storageOk,
      evidence: url.length > 96 ? '${url.substring(0, 96)}…' : url,
      detail: storageOk
          ? 'download URL host, via $path'
          : 'not emulator-hosted, or the object is missing/denied',
    ));
  }

  return EmulatorProof(proofs: proofs, host: host);
}

/// The blocking screen shown when a proof fails.
///
/// Deliberately not dismissible and deliberately loud: the only safe response
/// to "I cannot prove this is the sandbox" is to render nothing that can move
/// money. It prints the evidence so the cause is fixable without a debugger.
class EmulatorProofFailedApp extends StatelessWidget {
  final EmulatorProof proof;

  const EmulatorProofFailedApp({super.key, required this.proof});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B0B0B),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gpp_bad_outlined,
                          color: Color(0xFFFF6B6B), size: 34),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'EMULATOR NOT PROVEN — console blocked',
                          style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'This build asked for the local emulator, but at least one '
                    'Firebase service could not be proven to point at it. The '
                    'console will not render, because the next click could be '
                    'a financial mutation against a live project.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      proof.report,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Fix: start the emulator suite, run '
                    'scripts/seed_settlement_fixtures.sh (it writes both '
                    'sentinels), then relaunch with '
                    '--dart-define=USE_FIREBASE_EMULATOR=true.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Publishes the proof to the debug console so it is visible in the browser's
/// log as well as on screen — the two independent places an operator looks.
void logEmulatorProof(EmulatorProof proof) {
  if (!kDebugMode) return;
  for (final line in proof.report.split('\n')) {
    if (line.trim().isNotEmpty) debugPrint(line);
  }
}
