/// CONSOLE — turning a failure into something a human can act on.
///
/// This exists because of a real production failure: the console was opened
/// against a project where the food Cloud Functions had never been deployed,
/// and every screen said *"Could not load this view."* The operator had no way
/// to tell an undeployed backend from a permission problem from a network
/// blip — and the message the console chose to guess at ("usually a missing
/// index") was actively wrong.
///
/// A console that manages libraries thousands of organizations read must never
/// make an operator guess why it is broken.
///
/// Generalized from `food_errors.dart` when the Global Exercise Library was
/// built: the classification is not food-specific, and the second console would
/// otherwise have inherited a copy that drifts. The only per-feature parts are
/// the SUBJECT (what the operator is looking at) and the DEPLOY REMEDY (the
/// exact command that fixes an undeployed backend). `food_errors.dart` supplies
/// the food ones and re-exports these types unchanged.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// What actually went wrong, in terms the operator can act on.
enum ConsoleErrorKind {
  /// The Cloud Function this action needs does not exist in the project.
  notDeployed,

  /// The query needs a composite index that has not been created.
  missingIndex,

  /// Signed in, but not authorized.
  permission,

  /// Network or backend unavailable — retrying is the right response.
  offline,

  /// The server understood and refused (validation, a guard).
  rejected,

  unknown,
}

class ConsoleError {
  final ConsoleErrorKind kind;

  /// A complete sentence, safe to show verbatim.
  final String message;

  /// The exact remediation, when there is one (a CLI command, a console link).
  final String? remedy;

  /// Firestore hands back a one-click index-creation URL. Losing it turns a
  /// 30-second fix into a support ticket.
  final String? url;

  const ConsoleError({
    required this.kind,
    required this.message,
    this.remedy,
    this.url,
  });

  /// Whether a plain "Try again" is a sensible response. A missing function or
  /// index will not fix itself, so offering retry there is a lie.
  bool get isRetryable =>
      kind == ConsoleErrorKind.offline || kind == ConsoleErrorKind.unknown;

  /// True when the platform team, not the operator, has to act.
  bool get needsDeploy =>
      kind == ConsoleErrorKind.notDeployed ||
      kind == ConsoleErrorKind.missingIndex;
}

final RegExp _indexUrl = RegExp(r'https://console\.firebase\.google\.com/\S+');

/// Classifies any failure raised by a console's Firestore reads or callables.
///
/// [operation] is the callable or view that failed; naming it is the difference
/// between "something went wrong" and "deploy `getFoodLibraryAnalytics`".
/// [subject] names the feature ("the Global Exercise Library") and
/// [deployRemedy] is the exact command that deploys its backend.
ConsoleError describeConsoleError(
  Object error, {
  String? operation,
  required String subject,
  required String deployRemedy,
  required String logTarget,
}) {
  final what = operation == null ? 'This view' : '`$operation`';

  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      // The function is not in the project. This is the single most common
      // cause of a brand-new console failing everywhere at once.
      case 'not-found':
      case 'unimplemented':
        return ConsoleError(
          kind: ConsoleErrorKind.notDeployed,
          message:
              '$what is not deployed to this Firebase project. Without its '
              'Cloud Functions, $subject cannot work at all.',
          // Scoped deliberately: a blanket `--only functions` would ship
          // every unrelated change sitting in the backend working tree to a
          // project serving live organizations.
          remedy: deployRemedy,
        );
      case 'unauthenticated':
      case 'permission-denied':
        return ConsoleError(
          kind: ConsoleErrorKind.permission,
          message:
              'Your account is not authorized for $subject. It needs the '
              'super-admin claim, or a master_admins record.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'aborted':
        return const ConsoleError(
          kind: ConsoleErrorKind.offline,
          message:
              'The backend did not respond. This is usually a network problem '
              'rather than a fault in the data.',
        );
      case 'invalid-argument':
      case 'already-exists':
      case 'failed-precondition':
        return ConsoleError(
          kind: ConsoleErrorKind.rejected,
          message: error.message ?? 'The server refused that request.',
        );
      case 'internal':
        // `internal` is genuinely ambiguous on web: a missing function and a
        // thrown exception inside a deployed one look the same from here. Say
        // so rather than picking one and being confidently wrong.
        return ConsoleError(
          kind: ConsoleErrorKind.unknown,
          message:
              '$what failed inside the backend. If $subject has never been '
              'deployed to this project, that is the likely cause; otherwise '
              'check the function logs.',
          remedy: 'firebase functions:log --only ${operation ?? logTarget}',
        );
      default:
        return ConsoleError(
          kind: ConsoleErrorKind.unknown,
          message: error.message ?? '$what failed.',
        );
    }
  }

  if (error is FirebaseException) {
    if (error.code == 'failed-precondition') {
      final raw = error.message ?? '';
      final match = _indexUrl.firstMatch(raw);
      return ConsoleError(
        kind: ConsoleErrorKind.missingIndex,
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
      return const ConsoleError(
        kind: ConsoleErrorKind.permission,
        message:
            'Firestore refused this read. Your account needs the super-admin '
            'claim, or the security rules have not been deployed.',
        remedy:
            'From trainershq-backend:  firebase deploy --only firestore:rules',
      );
    }
    if (error.code == 'unavailable') {
      return const ConsoleError(
        kind: ConsoleErrorKind.offline,
        message:
            'Cannot reach Firestore. You appear to be offline — the console '
            'will work again as soon as the connection returns.',
      );
    }
    return ConsoleError(
      kind: ConsoleErrorKind.unknown,
      message: error.message ?? '$what failed.',
    );
  }

  return ConsoleError(
    kind: ConsoleErrorKind.unknown,
    message: '$what failed unexpectedly.',
  );
}
