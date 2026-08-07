/// GLOBAL EXERCISE LIBRARY — turning a failure into something a human can act
/// on.
///
/// The classification lives in `console_errors.dart`, shared with the food
/// console. What is supplied here is only what is exercise-specific: the
/// subject the operator is looking at, and the exact command that deploys the
/// catalog backend.
///
/// The distinction that matters on a brand-new feature: an undeployed callable
/// and a permission failure look identical from the browser, and "Could not
/// load this view" in front of either one is how a five-minute deploy becomes a
/// day of debugging.
library;

import 'console_errors.dart';

export 'console_errors.dart';

/// Classifies any failure raised by the exercise console's reads or callables.
///
/// [operation] is the callable or view that failed; naming it is the difference
/// between "something went wrong" and "deploy `getExerciseLibraryAnalytics`".
ConsoleError describeExerciseError(Object error, {String? operation}) =>
    describeConsoleError(
      error,
      operation: operation,
      subject: 'the Global Exercise Library',
      // Scoped deliberately: a blanket `--only functions` would ship every
      // unrelated change sitting in the backend working tree to a project
      // serving live organizations.
      deployRemedy:
          'From trainershq-backend:  bash scripts/deploy_exercise_catalog.sh',
      logTarget: 'exerciseCatalog',
    );
