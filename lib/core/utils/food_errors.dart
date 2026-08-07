/// FOOD PLATFORM — turning a failure into something a human can act on.
///
/// The CLASSIFICATION now lives in `console_errors.dart`, shared with the
/// Global Exercise Library: nothing about "an undeployed callable looks like
/// `not-found`" is food-specific, and a second copy would drift. What stays
/// here is what genuinely is food — the subject the operator is looking at and
/// the exact command that deploys the food backend.
///
/// The names below are UNCHANGED aliases of the shared types, so every existing
/// `FoodConsoleError` / `FoodErrorKind` call site across the food console keeps
/// compiling and behaving identically.
library;

import 'console_errors.dart';

export 'console_errors.dart';

/// What actually went wrong, in terms the operator can act on.
typedef FoodErrorKind = ConsoleErrorKind;

/// A classified failure, safe to render verbatim.
typedef FoodConsoleError = ConsoleError;

/// Classifies any failure raised by the food console's reads or callables.
///
/// [operation] is the callable or view that failed; naming it is the difference
/// between "something went wrong" and "deploy `getFoodLibraryAnalytics`".
FoodConsoleError describeFoodError(Object error, {String? operation}) =>
    describeConsoleError(
      error,
      operation: operation,
      subject: 'the Global Food Database',
      // Scoped deliberately: a blanket `--only functions` would ship every
      // unrelated change sitting in the backend working tree to a project
      // serving live organizations.
      deployRemedy:
          'From trainershq-backend:  '
          'powershell -File scripts/deploy_food_platform.ps1',
      logTarget: 'foodPlatform',
    );
