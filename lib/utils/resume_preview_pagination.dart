/// Splits resume sections across preview "pages" using height estimates
/// (A4-style cards). Conservative margins reduce overflow on dense text.
class ResumePreviewPagination {
  ResumePreviewPagination._();

  static double _estimateSectionHeight(Map<String, dynamic> section) {
    final type = section["type"];
    switch (type) {
      case "header":
        return 88;
      case "section":
        final content = section["content"]?.toString() ?? "";
        if (content.isEmpty) return 0;
        return 52 + (content.length / 50).ceil() * 18.0;
      case "experience":
        final items = section["items"] as List? ?? [];
        if (items.isEmpty) return 0;
        return 48 + items.length * 46.0;
      default:
        return 0;
    }
  }

  /// [maxContentHeight] = vertical space for the main column inside one A4 card
  /// (after inner padding).
  static List<List<Map<String, dynamic>>> paginate(
    List<Map<String, dynamic>> layout,
    double maxContentHeight,
  ) {
    final budget = maxContentHeight * 0.9;
    final pages = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    var used = 0.0;

    for (final section in layout) {
      final h = _estimateSectionHeight(section);
      if (h <= 0) continue;

      if (current.isNotEmpty && used + h > budget) {
        pages.add(current);
        current = <Map<String, dynamic>>[];
        used = 0;
      }
      current.add(section);
      used += h;
    }

    if (current.isNotEmpty) {
      pages.add(current);
    }

    if (pages.isEmpty) {
      pages.add(<Map<String, dynamic>>[]);
    }

    return pages;
  }
}
