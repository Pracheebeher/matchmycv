/// Product rules for templates shown in the app.
class TemplateAccess {
  const TemplateAccess._();

  static const Set<String> allTemplateIds = {
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
  };

  /// Only these templates are usable without purchase; others show the paywall
  /// unless unlocked via [TemplateEntitlementsStore].
  static const Set<String> freeTemplateIds = {'1', '2'};

  static bool isFree(String templateId) => freeTemplateIds.contains(templateId);

  static bool isPaid(String templateId) =>
      allTemplateIds.contains(templateId) && !isFree(templateId);

  static bool isKnownTemplate(String templateId) => allTemplateIds.contains(templateId);
}
