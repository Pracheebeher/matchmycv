/// Helpers for splitting imported work-experience description lines for templates.
class ExperienceDisplay {
  ExperienceDisplay._();

  static final RegExp _metaLine = RegExp(
    r'^(client|defect\s+management\s+tool|project|tool|environment|platform|technology|product|application)\s*:',
    caseSensitive: false,
  );

  static final RegExp _responsibilitiesHeading = RegExp(
    r'^(roles?\s+and\s+responsibilities|responsibilities)\s*:?\s*$',
    caseSensitive: false,
  );

  /// True for lines like "Client: …" or "Defect Management Tool: …".
  static bool looksLikeMetaLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    return _metaLine.hasMatch(t.toLowerCase());
  }

  static bool looksLikeResponsibilitiesHeading(String line) {
    return _responsibilitiesHeading.hasMatch(line.trim());
  }

  /// Only long paragraph-style openers become a non-bullet intro — not every bullet that ends with ".".
  static bool looksLikeSummaryIntro(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (looksLikeMetaLine(t) || looksLikeResponsibilitiesHeading(t)) {
      return false;
    }
    if (t.length < 120) return false;
    if (t.length > 140) return true;
    final sentenceEnds =
        RegExp(r'[.!?](?:\s|$)').allMatches(t).length;
    return sentenceEnds >= 2;
  }

  /// Splits the first description line into an optional intro paragraph vs bullet list.
  static ({String? intro, List<String> bullets}) splitIntroFromBullets(
    List<String> description, {
    bool allowIntro = true,
  }) {
    if (!allowIntro || description.isEmpty) {
      return (intro: null, bullets: List<String>.from(description));
    }
    final first = description.first.trim();
    if (!looksLikeSummaryIntro(first)) {
      return (intro: null, bullets: List<String>.from(description));
    }
    return (
      intro: first,
      bullets: description.skip(1).map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    );
  }
}
