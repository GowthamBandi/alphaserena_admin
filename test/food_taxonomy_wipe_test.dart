// A FAILED TAXONOMY READ MUST NOT RELABEL THE WHOLE LIBRARY.
//
// 🔴 THE DEFECT THIS GUARDS. `GlobalFoodController._bindCategories` handled a
// category-stream failure with:
//
//     // The taxonomy is a filter, not a dependency — its failure must never
//     // take the library down with it.
//     onError: (Object _) => categories.clear(),
//
// The comment states the right principle and the code does the opposite of it.
// `categoryName(id)` and `categoryPath(id)` both resolve through `categories`
// and return `''` when it does not contain the id — so emptying the list
// silently relabels EVERY food in the global library as uncategorised, and the
// category filter renders as though the platform has no taxonomy at all.
//
// A stale label is a much smaller lie than a deleted one. Keep the last good
// list and record the failure.

import 'package:alphaserena_admin_portel/controllers/global_food_controller.dart';
import 'package:alphaserena_admin_portel/models/global_food_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineFood extends GlobalFoodController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  test('a taxonomy stream failure keeps the last good categories', () {
    final c = _OfflineFood();
    c.onCategories([
      FoodCategoryModel.fromMap(const {'name': 'Protein'}, 'protein'),
    ]);

    // Exactly what the stream's onError does.
    c.onCategoriesError(Exception('permission-denied'));

    expect(c.categories, isNotEmpty,
        reason: 'clearing relabels every food in the library as uncategorised');
    expect(c.categoryName('protein'), 'Protein',
        reason: 'the label the library renders must survive a filter outage');
    expect(c.categoriesError.value, isTrue,
        reason: 'the failure must still be recorded');
  });

  test('CONTROL — a successful emission replaces the list and clears the flag',
      () {
    // Without this control, a fix that simply never updated `categories` would
    // pass the assertion above and freeze the taxonomy forever.
    final c = _OfflineFood();
    c.categoriesError.value = true;
    c.onCategories([
      FoodCategoryModel.fromMap(const {'name': 'Carbs'}, 'carbs'),
    ]);

    expect(c.categoryName('carbs'), 'Carbs');
    expect(c.categoriesError.value, isFalse);
  });
}
