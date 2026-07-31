import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the create / edit wizard.
///
/// Replaces a single 300-line form. A food carries thirty-odd fields across
/// five unrelated concerns, and presenting them as one wall guarantees two
/// things: curators skip the parts they do not recognise, and a validation
/// failure at the bottom is invisible from the top.
///
/// Five steps, each validated before the next unlocks, and a final review that
/// shows exactly what will be written. The SERVER still re-validates
/// everything — duplicating the nutrition rules here would create a second,
/// drifting copy of them, and the console would start accepting rows the
/// platform rejects. What the wizard validates is what it can prove locally,
/// so a curator is not made to wait on a round trip to learn a name is blank.
class FoodWizardDialog extends StatefulWidget {
  final GlobalFoodController controller;

  /// The food being edited, or null to create.
  final GlobalFoodModel? existing;

  /// True when [existing] is being used as a TEMPLATE for a new food.
  final bool duplicating;

  const FoodWizardDialog({
    super.key,
    required this.controller,
    this.existing,
    this.duplicating = false,
  });

  @override
  State<FoodWizardDialog> createState() => _FoodWizardDialogState();
}

/// The micronutrients the console can author, with their stored units.
const List<({String key, String label, String unit})> kMicroFields = [
  (key: 'sodium', label: 'Sodium', unit: 'mg'),
  (key: 'potassium', label: 'Potassium', unit: 'mg'),
  (key: 'calcium', label: 'Calcium', unit: 'mg'),
  (key: 'iron', label: 'Iron', unit: 'mg'),
  (key: 'magnesium', label: 'Magnesium', unit: 'mg'),
  (key: 'zinc', label: 'Zinc', unit: 'mg'),
  (key: 'cholesterol', label: 'Cholesterol', unit: 'mg'),
  (key: 'vitaminA', label: 'Vitamin A', unit: 'µg'),
  (key: 'vitaminC', label: 'Vitamin C', unit: 'mg'),
  (key: 'vitaminD', label: 'Vitamin D', unit: 'µg'),
  (key: 'vitaminB12', label: 'Vitamin B12', unit: 'µg'),
  (key: 'folate', label: 'Folate', unit: 'µg'),
  (key: 'transFat', label: 'Trans fat', unit: 'g'),
  (key: 'monounsaturatedFat', label: 'Mono fat', unit: 'g'),
  (key: 'polyunsaturatedFat', label: 'Poly fat', unit: 'g'),
];

/// Dialog dimensions that never exceed the window — a dialog wider than the
/// viewport clips its own content, and nothing can scroll it sideways.
double _wizardWidth(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - 80;
  return available < 720 ? (available < 280 ? 280 : available) : 720;
}

double _wizardHeight(BuildContext context) {
  final available = MediaQuery.sizeOf(context).height - 260;
  return available < 460 ? (available < 240 ? 240 : available) : 460;
}

class _FoodWizardDialogState extends State<FoodWizardDialog> {
  int _step = 0;

  // Step 1 — basics
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brand ?? '');
  late final _barcode = TextEditingController(
    text: widget.existing?.barcode ?? '',
  );
  late String _categoryId = widget.existing?.categoryId ?? '';
  late String _foodType = widget.existing?.foodType ?? 'ingredient';
  late String _cuisine = widget.existing?.cuisine ?? '';

  // Step 2 — nutrition
  late final _calories = _numCtl(widget.existing?.calories);
  late final _protein = _numCtl(widget.existing?.protein);
  late final _carbs = _numCtl(widget.existing?.carbs);
  late final _fat = _numCtl(widget.existing?.fat);
  late final _fiber = _numCtl(widget.existing?.fiber);
  late final _sugar = _numCtl(widget.existing?.sugar);
  late final _satFat = _numCtl(widget.existing?.saturatedFat);
  bool _allowEnergyMismatch = false;

  // Step 2b — micronutrients
  late final Map<String, TextEditingController> _micros = {
    for (final m in kMicroFields)
      m.key: _numCtl(widget.existing?.micros[m.key]),
  };

  // Step 3 — serving sizes
  late final List<({TextEditingController label, TextEditingController grams})>
  _portions = [
    for (final p in widget.existing?.portions ?? const [])
      (
        label: TextEditingController(text: p.label),
        grams: TextEditingController(text: p.grams.toStringAsFixed(0)),
      ),
  ];

  // Step 4 — search metadata
  late final _aliases = TextEditingController(
    text: widget.existing?.aliases.join(', ') ?? '',
  );

  // Step 5 — publish
  late String _status = widget.duplicating
      ? 'draft'
      : (widget.existing?.status ?? 'draft');
  final _reason = TextEditingController();

  bool get _isEdit => widget.existing != null && !widget.duplicating;

  static TextEditingController _numCtl(double? v) =>
      TextEditingController(text: (v == null || v == 0) ? '' : _fmt(v));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.duplicating) {
      // A duplicate must not be a duplicate: the name is the identity, and
      // saving an exact copy is precisely what the server refuses.
      _name.text = '${widget.existing?.name ?? ''} (copy)';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _barcode, _calories, _protein, _carbs, _fat,
      _fiber, _sugar, _satFat, _aliases, _reason,
    ]) {
      c.dispose();
    }
    for (final c in _micros.values) {
      c.dispose();
    }
    for (final p in _portions) {
      p.label.dispose();
      p.grams.dispose();
    }
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────

  /// Problems the console can prove locally, per step. Anything requiring
  /// knowledge of the rest of the library (duplicate names, for instance) is
  /// left to the server, which is the only place that can answer it correctly.
  List<String> _problems(int step) {
    switch (step) {
      case 0:
        final out = <String>[];
        if (_name.text.trim().length < 2) {
          out.add('A name of at least 2 characters is required.');
        }
        final code = _barcode.text.replaceAll(RegExp(r'\D'), '');
        if (code.isNotEmpty && (code.length < 8 || code.length > 14)) {
          out.add('A barcode must be 8–14 digits.');
        }
        return out;
      case 1:
        final out = <String>[];
        final p = _d(_protein), c = _d(_carbs), f = _d(_fat);
        if (p + c + f > 105) {
          out.add('Macros exceed 100 g per 100 g (P$p C$c F$f).');
        }
        if (_d(_sugar) > c + 2) {
          out.add('Sugar cannot exceed carbohydrate.');
        }
        if (_d(_satFat) > f + 1) {
          out.add('Saturated fat cannot exceed total fat.');
        }
        final estimate = 4 * p + 4 * c + 9 * f;
        final declared = _d(_calories);
        if (declared > 0 && estimate > 0 && !_allowEnergyMismatch) {
          final tolerance = estimate * 0.35 < 50 ? 50.0 : estimate * 0.35;
          if ((declared - estimate).abs() > tolerance) {
            out.add(
              'Declared ${declared.toStringAsFixed(0)} kcal but the macros '
              'imply ${estimate.toStringAsFixed(0)} kcal. Fix the numbers, or '
              'tick the override if this food genuinely breaks the 4/4/9 rule.',
            );
          }
        }
        return out;
      case 2:
        final out = <String>[];
        final seen = <String>{};
        for (final p in _portions) {
          final label = p.label.text.trim();
          final grams = double.tryParse(p.grams.text.trim()) ?? 0;
          if (label.isEmpty && grams == 0) continue;
          if (label.isEmpty) out.add('Every portion needs a label.');
          if (grams <= 0) out.add('"$label" needs a weight in grams.');
          if (grams > 5000) out.add('"$label" is heavier than 5 kg.');
          if (label.isNotEmpty && !seen.add(label.toLowerCase())) {
            out.add('"$label" is listed twice.');
          }
        }
        return out;
      default:
        return const [];
    }
  }

  bool get _canAdvance => _problems(_step).isEmpty;

  // ── Assembly ───────────────────────────────────────────────────────

  GlobalFoodModel _build() {
    final micros = <String, double>{};
    _micros.forEach((key, ctl) {
      final v = _d(ctl);
      if (v > 0) micros[key] = v;
    });

    final portions = <({String label, double grams})>[];
    for (final p in _portions) {
      final label = p.label.text.trim();
      final grams = double.tryParse(p.grams.text.trim()) ?? 0;
      if (label.isNotEmpty && grams > 0) {
        portions.add((label: label, grams: grams));
      }
    }

    return GlobalFoodModel(
      // A duplicate is a NEW food: carrying the id forward would overwrite the
      // original, which is the opposite of duplicating it.
      id: _isEdit ? widget.existing!.id : '',
      scope: 'global',
      name: _name.text,
      brand: _brand.text,
      categoryId: _categoryId,
      cuisine: _cuisine,
      foodType: _foodType,
      aliases: _aliases.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.length >= 2)
          .toList(),
      barcode: _barcode.text,
      baseGrams: 100,
      calories: _d(_calories),
      protein: _d(_protein),
      carbs: _d(_carbs),
      fat: _d(_fat),
      fiber: _d(_fiber),
      sugar: _d(_sugar),
      saturatedFat: _d(_satFat),
      micros: micros,
      portions: portions,
      source: widget.existing?.source ?? 'manual',
      sourceRef: _isEdit ? widget.existing!.sourceRef : '',
    );
  }

  Future<void> _submit() async {
    final ok = await widget.controller.saveFood(
      _build(),
      allowEnergyMismatch: _allowEnergyMismatch,
      status: _status,
      reason: _reason.text.trim(),
    );
    if (ok) Get.back();
  }

  // ── Chrome ─────────────────────────────────────────────────────────

  static const _steps = [
    (title: 'Basics', icon: Icons.label_outline),
    (title: 'Nutrition', icon: Icons.local_fire_department_outlined),
    (title: 'Serving sizes', icon: Icons.straighten),
    (title: 'Search metadata', icon: Icons.search),
    (title: 'Review', icon: Icons.fact_check_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEdit
                ? 'Edit "${widget.existing!.name}"'
                : widget.duplicating
                ? 'Duplicate food'
                : 'New global food',
            style: AppText.title(size: 22).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Every organization on the platform will be able to read this.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          _stepper(context),
        ],
      ),
      content: SizedBox(
        width: _wizardWidth(context),
        height: _wizardHeight(context),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              switch (_step) {
                0 => _stepBasics(context),
                1 => _stepNutrition(context),
                2 => _stepServings(context),
                3 => _stepMetadata(context),
                _ => _stepReview(context),
              },
              // BELOW the fields on purpose. When this sat above them, showing
              // or hiding it moved every input under the operator's cursor
              // mid-entry — observed live, twice, silently losing typed
              // values. Here the form never reflows, and the error sits
              // directly above the button it is blocking.
              Obx(() => _problemBanner(context)),
            ],
          ),
        ),
      ),
      actions: [
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step--),
            child: const Text('Back'),
          ),
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        if (_step < _steps.length - 1)
          FilledButton(
            onPressed: _canAdvance ? () => setState(() => _step++) : null,
            child: const Text('Continue'),
          )
        else
          Obx(
            () => FilledButton.icon(
              onPressed: widget.controller.isSaving.value ? null : _submit,
              icon: Icon(
                _status == 'published' ? Icons.public : Icons.save_outlined,
                size: 18,
              ),
              label: Text(
                _status == 'published'
                    ? (_isEdit ? 'Save & publish' : 'Publish')
                    : 'Save as draft',
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepper(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: GestureDetector(
              // Jumping BACK is always allowed; jumping forward past an invalid
              // step is not, or the review would show a food that cannot save.
              onTap: i < _step ? () => setState(() => _step = i) : null,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= _step ? p.accent : p.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _steps[i].icon,
                        size: 13,
                        color: i <= _step ? p.accent : p.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _steps[i].title,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 11).copyWith(
                            color: i <= _step ? p.textPrimary : p.textMuted,
                            fontWeight: i == _step
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (i < _steps.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _problemBanner(BuildContext context) {
    // Local validation problems PLUS whatever the server said about the last
    // refused write. Both belong in the same place: the operator does not care
    // which side rejected their food, only what to change.
    final serverFailure = widget.controller.writeError.value;
    final problems = [
      ..._problems(_step),
      if (serverFailure != null) serverFailure.message,
    ];
    if (problems.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.08),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 15, color: p.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      problem,
                      style: AppText.body(
                        size: 12.5,
                      ).copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Steps ──────────────────────────────────────────────────────────

  Widget _stepBasics(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'The canonical name coaches will see.',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _brand,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Brand (optional)',
                  helperText: 'Two brands of one product stay distinct foods.',
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _barcode,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Barcode (optional)',
                  helperText: '8–14 digits (EAN / UPC).',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _dropdown(
          label: 'Category',
          value: _categoryId,
          items: {
            '': 'Uncategorised',
            for (final c in widget.controller.activeCategories)
              c.id: widget.controller.categoryPath(c.id),
          },
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'Type',
                value: _foodType,
                items: const {
                  'ingredient': 'Ingredient',
                  'dish': 'Dish',
                  'recipe': 'Recipe',
                  'branded': 'Branded product',
                  'beverage': 'Beverage',
                  'supplement': 'Supplement',
                },
                onChanged: (v) => setState(() => _foodType = v),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _dropdown(
                label: 'Cuisine',
                value: _cuisine,
                items: const {
                  '': 'Any',
                  'indian': 'Indian',
                  'continental': 'Continental',
                  'east-asian': 'East Asian',
                  'middle-eastern': 'Middle Eastern',
                  'mediterranean': 'Mediterranean',
                },
                onChanged: (v) => setState(() => _cuisine = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepNutrition(BuildContext context) {
    final p = context.palette;
    final estimate = 4 * _d(_protein) + 4 * _d(_carbs) + 9 * _d(_fat);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Per 100 g — the platform basis for every global food, so quantities '
          'scale by grams in every diet plan.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _num('Calories (kcal)', _calories)),
            const SizedBox(width: 12),
            Expanded(child: _num('Protein (g)', _protein)),
            const SizedBox(width: 12),
            Expanded(child: _num('Carbs (g)', _carbs)),
            const SizedBox(width: 12),
            Expanded(child: _num('Fat (g)', _fat)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _num('Fiber (g)', _fiber)),
            const SizedBox(width: 12),
            Expanded(child: _num('Sugar (g)', _sugar)),
            const SizedBox(width: 12),
            Expanded(child: _num('Saturated fat (g)', _satFat)),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          estimate > 0
              ? 'The macros imply ${estimate.toStringAsFixed(0)} kcal (4/4/9). '
                    'Leave calories blank to use that.'
              : 'Enter macros and the energy estimate appears here.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        CheckboxListTile(
          value: _allowEnergyMismatch,
          onChanged: (v) => setState(() => _allowEnergyMismatch = v ?? false),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Accept an energy mismatch',
            style: AppText.body(size: 12.5),
          ),
          subtitle: Text(
            'For foods the 4/4/9 rule genuinely cannot explain — alcohol, '
            'polyols, fortified products.',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Micronutrients (optional)',
            style: AppText.label(size: 13).copyWith(color: p.textPrimary),
          ),
          subtitle: Text(
            'Only fill in what a source actually published — a zero reads as '
            'fact, and inventing one is worse than leaving it blank.',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in kMicroFields)
                  SizedBox(
                    width: 210,
                    child: _num('${m.label} (${m.unit})', _micros[m.key]!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }

  Widget _stepServings(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Household portions are what make a diet plan quick to build: a coach '
          'picks "2 katori" instead of typing 300 g. Every portion is a weight '
          'in grams — nutrition is always derived from the per-100 g base.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        if (_portions.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: AppRadii.smR,
            ),
            child: Text(
              'No portions yet. This is optional — coaches can always enter '
              'grams directly.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            ),
          ),
        for (var i = 0; i < _portions.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _portions[i].label,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'katori, roti, cup, slice',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portions[i].grams,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Grams',
                      suffixText: 'g',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => setState(() {
                    _portions[i].label.dispose();
                    _portions[i].grams.dispose();
                    _portions.removeAt(i);
                  }),
                  icon: Icon(Icons.close, size: 18, color: p.error),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _portions.length >= 8
                ? null
                : () => setState(
                    () => _portions.add((
                      label: TextEditingController(),
                      grams: TextEditingController(),
                    )),
                  ),
            icon: const Icon(Icons.add, size: 17),
            label: Text(
              _portions.length >= 8 ? 'Maximum 8 portions' : 'Add a portion',
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepMetadata(BuildContext context) {
    final p = context.palette;
    final aliases = _aliases.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.length >= 2)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aliases are how a regional or colloquial name reaches this food. '
          'They are indexed exactly like the name, so filing "Cottage Cheese" '
          'with the alias "Paneer" makes both searches land here.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _aliases,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Also known as',
            helperText: 'Comma separated. Up to 12 are stored.',
          ),
        ),
        const SizedBox(height: 16),
        if (aliases.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in aliases.take(12))
                FoodPill(label: a, color: p.accent),
              if (aliases.length > 12)
                FoodPill(
                  label: '${aliases.length - 12} will be dropped',
                  color: p.error,
                ),
            ],
          ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: AppRadii.smR,
          ),
          child: Text(
            'Search index: the platform builds bounded prefix tokens from the '
            'name, brand and aliases when it saves. A coach typing two or more '
            'characters of any word will find this food.',
            style: AppText.body(size: 12).copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _stepReview(BuildContext context) {
    final p = context.palette;
    final food = _build();
    final gaps = food.missingData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: AppRadii.cardR,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                food.name,
                style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (food.brand.isNotEmpty) food.brand,
                  widget.controller.categoryPath(food.categoryId).isEmpty
                      ? 'Uncategorised'
                      : widget.controller.categoryPath(food.categoryId),
                  food.foodType,
                ].join('  ·  '),
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 26,
                runSpacing: 12,
                children: [
                  FoodStat(
                    label: 'kcal / 100 g',
                    value: food.calories.toStringAsFixed(0),
                    color: p.accent,
                  ),
                  FoodStat(
                    label: 'protein',
                    value: '${food.protein.toStringAsFixed(1)} g',
                  ),
                  FoodStat(
                    label: 'carbs',
                    value: '${food.carbs.toStringAsFixed(1)} g',
                  ),
                  FoodStat(label: 'fat', value: '${food.fat.toStringAsFixed(1)} g'),
                  FoodStat(label: 'portions', value: '${food.portions.length}'),
                  FoodStat(label: 'aliases', value: '${food.aliases.length}'),
                  FoodStat(label: 'micros', value: '${food.micros.length}'),
                ],
              ),
            ],
          ),
        ),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.textMuted.withValues(alpha: 0.08),
              borderRadius: AppRadii.smR,
            ),
            child: Text(
              'This food has no ${gaps.join(', ')}. That is allowed — it will '
              'appear in the "Foods missing data" queue so someone can finish '
              'it later.',
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'PUBLISH STATE',
          style: AppText.body(size: 10.5).copyWith(
            color: p.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FoodChip(
              label: 'Save as draft',
              icon: Icons.edit_note,
              active: _status != 'published',
              onTap: () => setState(() => _status = 'draft'),
            ),
            const SizedBox(width: 8),
            FoodChip(
              label: 'Publish to all organizations',
              icon: Icons.public,
              active: _status == 'published',
              onTap: () => setState(() => _status = 'published'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _status == 'published'
              ? 'Every organization will be able to search and use this '
                    'immediately.'
              : 'Only the platform team sees drafts. Nothing reaches coaches '
                    'until you publish.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            helperText: 'Recorded in this food\'s revision history.',
          ),
        ),
      ],
    );
  }

  // ── Fields ─────────────────────────────────────────────────────────

  Widget _num(String label, TextEditingController c) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(labelText: label, isDense: true),
  );

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    final safe = items.containsKey(value) ? value : items.keys.first;
    return DropdownButtonFormField<String>(
      initialValue: safe,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}
