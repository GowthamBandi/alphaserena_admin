library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// FOOD PLATFORM — turning a failure into something a human can act on.
///
/// This exists because of a real production failure: the console was opened
/// against a project where the food Cloud Functions had never been deployed,
/// and every screen said *"Could not load this view."* The operator had no way
/// to tell an undeployed backend from a permission problem from a network
/// blip — and the message the console chose to guess at ("usually a missing
/// index") was actively wrong.
///
/// A console that manages a library thousands of organizations read must never
/// make an operator guess why it is broken.

/// What actually went wrong, in terms the operator can act on.
enum FoodErrorKind {
  /// The Cloud Function this action needs does not exist in the project.
  notDeployed,

  /// The query needs a composite index that has not been created.
  missingIndex,

  /// Signed in, but not authorized.
  permission,

  /// Network or backend unavailable — retrying is the right response.
  offline,

  /// The server understood and refused (validation, usage guard).
  rejected,

  unknown,
}

class FoodConsoleError {
  final FoodErrorKind kind;

  /// A complete sentence, safe to show verbatim.
  final String message;

  /// The exact remediation, when there is one (a CLI command, a console link).
  final String? remedy;

  /// Firestore hands back a one-click index-creation URL. Losing it turns a
  /// 30-second fix into a support ticket.
  final String? url;

  const FoodConsoleError({
    required this.kind,
    required this.message,
    this.remedy,
    this.url,
  });

  /// Whether a plain "Try again" is a sensible response. A missing function or
  /// index will not fix itself, so offering retry there is a lie.
  bool get isRetryable =>
      kind == FoodErrorKind.offline || kind == FoodErrorKind.unknown;

  /// True when the platform team, not the operator, has to act.
  bool get needsDeploy =>
      kind == FoodErrorKind.notDeployed || kind == FoodErrorKind.missingIndex;
}

final RegExp _indexUrl = RegExp(r'https://console\.firebase\.google\.com/\S+');

/// Classifies any failure raised by the console's Firestore reads or callables.
///
/// [operation] is the callable or view that failed; naming it is the difference
/// between "something went wrong" and "deploy `getFoodLibraryAnalytics`".
FoodConsoleError describeFoodError(Object error, {String? operation}) {
  final what = operation == null ? 'This view' : '`$operation`';

  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      // The function is not in the project. This is the single most common
      // cause of a brand-new console failing everywhere at once.
      case 'not-found':
      case 'unimplemented':
        return FoodConsoleError(
          kind: FoodErrorKind.notDeployed,
          message:
              '$what is not deployed to this Firebase project. The Global Food '
              'Database needs its Cloud Functions before any of it will work.',
          // Scoped deliberately: a blanket `--only functions` would ship
          // every unrelated change sitting in the backend working tree to a
          // project serving live organizations.
          remedy:
              'From trainershq-backend:  '
              'powershell -File scripts/deploy_food_platform.ps1',
        );
      case 'unauthenticated':
      case 'permission-denied':
        return FoodConsoleError(
          kind: FoodErrorKind.permission,
          message:
              'Your account is not authorized for the global food database. '
              'It needs the super-admin claim, or a master_admins record.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
        return FoodConsoleError(
          kind: FoodErrorKind.offline,
          message:
              'The backend did not respond. This is usually a network problem '
              'rather than a fault in the data.',
        );
      case 'invalid-argument':
      case 'already-exists':
      case 'failed-precondition':
        return FoodConsoleError(
          kind: FoodErrorKind.rejected,
          message: error.message ?? 'The server refused that request.',
        );
      case 'internal':
        // `internal` is genuinely ambiguous on web: a missing function and a
        // thrown exception inside a deployed one look the same from here. Say
        // so rather than picking one and being confidently wrong.
        return FoodConsoleError(
          kind: FoodErrorKind.unknown,
          message:
              '$what failed inside the backend. If the Global Food Database '
              'has never been deployed to this project, that is the likely '
              'cause; otherwise check the function logs.',
          remedy: 'firebase functions:log --only ${operation ?? 'foodPlatform'}',
        );
      default:
        return FoodConsoleError(
          kind: FoodErrorKind.unknown,
          message: error.message ?? '$what failed.',
        );
    }
  }

  if (error is FirebaseException) {
    if (error.code == 'failed-precondition') {
      final raw = error.message ?? '';
      final match = _indexUrl.firstMatch(raw);
      return FoodConsoleError(
        kind: FoodErrorKind.missingIndex,
        message:
            'This view needs a Firestore composite index that does not exist '
            'in this project yet.',
        remedy:
            'From trainershq-backend:  '
            'firebase deploy --only firestore:indexes',
        // Firestore includes a link that creates exactly the missing index.
        url: match?.group(0),
      );
    }
    if (error.code == 'permission-denied') {
      return const FoodConsoleError(
        kind: FoodErrorKind.permission,
        message:
            'Firestore refused this read. Your account needs the super-admin '
            'claim, or the security rules have not been deployed.',
        remedy:
            'From trainershq-backend:  firebase deploy --only firestore:rules',
      );
    }
    if (error.code == 'unavailable') {
      return const FoodConsoleError(
        kind: FoodErrorKind.offline,
        message:
            'Cannot reach Firestore. You appear to be offline — the console '
            'will work again as soon as the connection returns.',
      );
    }
    return FoodConsoleError(
      kind: FoodErrorKind.unknown,
      message: error.message ?? '$what failed.',
    );
  }

  return FoodConsoleError(
    kind: FoodErrorKind.unknown,
    message: '$what failed unexpectedly.',
  );
}
