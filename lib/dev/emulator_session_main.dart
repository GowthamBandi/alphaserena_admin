// EMULATOR SESSION ENTRYPOINT — dev/QA only.
//
// Boots the real console (`main.dart`) and, ONLY when every one of these holds,
// signs in as a seeded emulator founder so a QA run never types a credential:
//
//   • built with `--dart-define=USE_FIREBASE_EMULATOR=true`
//   • a debug build (`kDebugMode`)
//   • `--dart-define=EMULATOR_LOGIN_EMAIL=<seeded founder email>`
//
// A release/profile build, or a build without the emulator define, runs
// `main.dart` unchanged — this file adds nothing to it. Mirrors
// trainersHQ/lib/dev/emulator_session_main.dart. The password is the fixture
// password the emulator seeder uses; it authenticates nothing outside the
// local Auth emulator, and `proveEmulatorSession` in main.dart still blocks
// the console unless the signed-in uid matches the emulator's own sentinel.
//
// Build:
//   flutter build web --debug -t lib/dev/emulator_session_main.dart \
//     --dart-define=USE_FIREBASE_EMULATOR=true \
//     --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 \
//     --dart-define=EMULATOR_LOGIN_EMAIL=founder@emulator.test \
//     --output=<dir>

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../main.dart' as app;

const String _useEmulator = String.fromEnvironment('USE_FIREBASE_EMULATOR');
const String _email = String.fromEnvironment('EMULATOR_LOGIN_EMAIL');
const String _emulatorPassword = 'emu-pass-123456';

void main() {
  app.main();
  if (_useEmulator != 'true' || !kDebugMode || _email.isEmpty) return;
  unawaited(_signInWhenReady());
}

Future<void> _signInWhenReady() async {
  while (Firebase.apps.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  // Let main.dart finish binding the SDKs to the emulator before signing in.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final auth = FirebaseAuth.instance;
  if (auth.currentUser?.email == _email) return;
  if (auth.currentUser != null) await auth.signOut();
  try {
    await auth.signInWithEmailAndPassword(
      email: _email,
      password: _emulatorPassword,
    );
    debugPrint('⚠️  EMULATOR SESSION — signed in as $_email');
  } catch (e) {
    debugPrint('EMULATOR SESSION sign-in failed: $e');
  }
}
