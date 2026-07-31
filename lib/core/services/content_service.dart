import 'package:cloud_functions/cloud_functions.dart';

/// One template from the backend catalog.
class ContentTemplate {
  final String id;
  final String label;
  final String kind;
  final int version;
  final List<String> locales;

  /// Exactly the variables this template references — the composer prompts
  /// for these and nothing else, so a founder is never asked for a field the
  /// copy does not use.
  final List<String> variables;

  const ContentTemplate({
    required this.id,
    required this.label,
    required this.kind,
    required this.version,
    required this.locales,
    required this.variables,
  });
}

/// The rendered payload, exactly as recipients will receive it.
class ContentPreview {
  final bool valid;
  final String? reason;
  final String title;
  final String body;
  final String? summary;
  final String? ctaLabel;
  final String? deepLink;
  final String? imageUrl;
  final String locale;
  final String? templateId;
  final int? version;

  /// Variables the template wanted but nothing supplied.
  final List<String> missing;

  /// Variables filled with sample values for preview purposes only. These are
  /// shown as placeholders so a founder never mistakes demo copy for the real
  /// message.
  final List<String> sampled;

  /// The literal transport map — what actually rides on the wire.
  final Map<String, String> data;

  const ContentPreview({
    required this.valid,
    this.reason,
    required this.title,
    required this.body,
    this.summary,
    this.ctaLabel,
    this.deepLink,
    this.imageUrl,
    required this.locale,
    this.templateId,
    this.version,
    this.missing = const [],
    this.sampled = const [],
    this.data = const {},
  });
}

/// The console's window onto the backend Content Engine (EP-3).
///
/// Rendering and variable substitution happen ENTIRELY on the server. This
/// console sends a template id plus variable values and receives finished
/// strings — it never performs substitution, so what it previews is produced
/// by the same function that produces what gets delivered.
class ContentService {
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  Future<List<ContentTemplate>> templates() async {
    final res = await _fns.httpsCallable('listContentTemplates').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    final raw = (m['templates'] as List?) ?? const [];
    return raw.map((e) {
      final t = Map<String, dynamic>.from(e as Map);
      return ContentTemplate(
        id: (t['id'] ?? '').toString(),
        label: (t['label'] ?? '').toString(),
        kind: (t['kind'] ?? '').toString(),
        version: (t['version'] is num) ? (t['version'] as num).toInt() : 1,
        locales: ((t['locales'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        variables: ((t['variables'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
    }).toList();
  }

  /// Renders content exactly as a recipient will receive it.
  ///
  /// Pass [templateId] for template-driven content, or [title]/[body] for
  /// free text — free text still goes through the server-side variable engine,
  /// so `{{organizationName}}` works either way with identical safety.
  Future<ContentPreview> preview({
    String? templateId,
    String? title,
    String? body,
    String? summary,
    String? imageUrl,
    String locale = 'en',
    Map<String, String> variables = const {},
  }) async {
    final res = await _fns.httpsCallable('previewContent').call({
      if (templateId != null && templateId.isNotEmpty) 'templateId': templateId,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (summary != null) 'summary': summary,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'locale': locale,
      'variables': variables,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    final p = Map<String, dynamic>.from((m['payload'] as Map?) ?? const {});
    String? s(String k) {
      final v = p[k];
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return ContentPreview(
      valid: m['valid'] == true,
      reason: m['reason']?.toString(),
      title: (p['title'] ?? '').toString(),
      body: (p['body'] ?? '').toString(),
      summary: s('summary'),
      ctaLabel: s('ctaLabel'),
      deepLink: s('deepLink'),
      imageUrl: s('imageUrl'),
      locale: (p['locale'] ?? 'en').toString(),
      templateId: s('templateId'),
      version: (p['version'] is num) ? (p['version'] as num).toInt() : null,
      missing: ((m['missing'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      sampled: ((m['sampled'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      data: Map<String, dynamic>.from((m['data'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
