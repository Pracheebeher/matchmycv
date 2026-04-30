import '../models/resume_model.dart';
import '../utils/category_entry_display.dart';

String _mapCategoryItemForGroup(String label, String s) {
  final t = s.trim();
  if (t.isEmpty) return '';
  if (label == 'Languages') {
    return CategoryEntryDisplay.formatLanguageEnglish(t);
  }
  return CategoryEntryDisplay.primarySecondaryLine(t);
}

String _formatProjectItem(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final sep = CategoryEntryDisplay.sep;
  if (!t.contains(sep)) return t;
  final parts = t
      .split(sep)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  final name = parts[0];
  final duration = parts.length >= 2 ? parts[1] : '';
  final details = parts.length >= 3 ? parts.sublist(2).join(' ') : '';
  if (duration.isNotEmpty && details.isNotEmpty) return '$name — $duration: $details';
  if (duration.isNotEmpty) return '$name — $duration';
  if (details.isNotEmpty) return '$name: $details';
  return name;
}

class ResumeLayoutEngine {
  /// [templateId] selects layout shape; only `"1"` uses the single-column classic stack.
  static List<Map<String, dynamic>> build(ResumeData data, {String? templateId}) {
    if (templateId == "1") {
      return _layoutTemplate1(data);
    }
    if (templateId == "2") {
      return _layoutTemplate2(data);
    }
    return _layoutDefault(data);
  }

  /// Navy sidebar holds education; main column: profile, timeline experience, references.
  static List<Map<String, dynamic>> _layoutTemplate2(ResumeData data) {
    return [
      {
        "type": "header",
        "name": data.name,
        "email": data.email,
        "phone": data.phone,
      },
      {
        "type": "section",
        "title": "SUMMARY",
        "content": data.summary,
      },
      {
        "type": "experience",
        "items": data.experiences,
      },
    ];
  }

  static List<Map<String, dynamic>> _layoutDefault(ResumeData data) {
    return [
      {
        "type": "header",
        "name": data.name,
        "email": data.email,
        "phone": data.phone,
      },
      {
        "type": "section",
        "title": "PROFILE",
        "content": data.summary,
      },
      {
        "type": "experience",
        "items": data.experiences,
      },
      if (data.educationList.isNotEmpty)
        {
          "type": "education",
          "items": data.educationList,
        },
    ];
  }

  static List<Map<String, dynamic>> _layoutTemplate1(ResumeData data) {
    final projects = (data.categories["Projects"] ?? const <String>[])
        .map(_formatProjectItem)
        .where((s) => s.isNotEmpty)
        .toList();
    final achievements = CategoryEntryDisplay.sanitizeAchievementDisplayList(
      (data.categories["Achievements"] ?? const <String>[])
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );

    final languages = (data.categories["Languages"] ?? const <String>[])
        .map((s) => CategoryEntryDisplay.formatLanguageEnglish(s))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final courses = (data.categories["Courses"] ?? const <String>[])
        .map((s) => CategoryEntryDisplay.primarySecondaryLine(s))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final certifications = (data.categories["Certifications"] ?? const <String>[])
        .map((s) => CategoryEntryDisplay.primarySecondaryLine(s))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final skillTokens = <String>[
      ...data.skills,
      ...(data.categories["Frameworks"] ?? const <String>[]),
      ...(data.categories["Cloud/Databases/Tech-Stack"] ?? const <String>[]),
      ...(data.categories["Cloud"] ?? const <String>[]),
      ...(data.categories["Databases"] ?? const <String>[]),
    ]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final seenSkills = <String>{};
    final skills = <String>[];
    for (final s in skillTokens) {
      final k = s.toLowerCase();
      if (seenSkills.contains(k)) continue;
      seenSkills.add(k);
      skills.add(s);
      if (skills.length >= 36) break;
    }

    return [
      {
        "type": "header",
        "name": data.name,
        "email": data.email,
        "phone": data.phone,
      },
      if (data.summary.trim().isNotEmpty)
        {
          "type": "section",
          "title": "PROFESSIONAL SUMMARY",
          "content": data.summary.trim(),
        },
      if (skills.isNotEmpty)
        {
          "type": "skills",
          "items": skills,
        },
      {
        "type": "experience",
        "items": data.experiences,
      },
      if (projects.isNotEmpty)
        {
          "type": "projects",
          "items": projects,
        },
      if (courses.isNotEmpty)
        {
          "type": "courses",
          "items": courses,
        },
      if (certifications.isNotEmpty)
        {
          "type": "certifications",
          "items": certifications,
        },
      if (achievements.isNotEmpty)
        {
          "type": "achievement",
          "items": achievements,
        },
      // Keep education/languages at the end for Template 1.
      if (data.educationList.isNotEmpty)
        {
          "type": "education",
          "items": data.educationList,
        },
      if (languages.isNotEmpty)
        {
          "type": "languages",
          "items": languages,
        },
    ];
  }
}
