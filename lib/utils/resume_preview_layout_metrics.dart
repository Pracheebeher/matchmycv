import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/resume_model.dart';
import '../services/ai_resume_parser.dart';
import 'experience_display.dart';
import 'resume_typography.dart';
import 'template1_layout_metrics.dart';

/// Measures preview/PDF page columns for all templates (template 1 delegates to
/// [Template1LayoutMetrics]).
class ResumePreviewLayoutMetrics {
  ResumePreviewLayoutMetrics._();

  /// Conservative margin so packed content does not clip at the page bottom.
  static const double renderSafetyMargin = 12.0;

  /// Slight extra budget when estimates are a few pixels short (reduces bottom gaps).
  static const double packHeightBudget = 20.0;

  static const double template2PackHeightBudget = 32.0;

  static double packBudgetFor(String templateId) =>
      templateId == '2' ? template2PackHeightBudget : packHeightBudget;

  static const double _sectionBottomPad = 12.0;
  static const double _titleGap = 8.0;
  static const double _bulletGap = 4.0;
  static const double _bulletIndent = 14.0;

  /// Space taken by template-specific headers inside the main column on page 1.
  static double page1MainHeaderReserve(String templateId) {
    switch (templateId) {
      case '2':
        return 0;
      case '3':
        return 118;
      case '4':
        return 72;
      case '5':
        return 88;
      case '6':
        return 78;
      case '7':
        return 128;
      case '8':
        return 148;
      case '9':
        return 102;
      case '10':
        return 118;
      case '11':
      case '12':
      case '13':
        return 76;
      default:
        return 0;
    }
  }

  static double _paint(String text, TextStyle style, double maxWidth) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  static TextStyle _titleStyle(String fontFamily) =>
      ResumeTypography.headingStyle(fontFamily, letterSpacing: 1.2, height: 1.15);

  static TextStyle _bodyStyle(String fontFamily) => ResumeTypography.bodyStyle(fontFamily);

  static TextStyle _mutedStyle(String fontFamily) => ResumeTypography.bodyStyle(
        fontFamily,
        height: ResumeTypography.lineHeightTight,
      );

  static TextStyle _jobTitleStyle(String fontFamily) =>
      ResumeTypography.headingStyle(fontFamily, height: 1.2);

  static double _contentTitleHeight(String title, String fontFamily) {
    return _paint(title.toUpperCase(), _titleStyle(fontFamily), double.infinity) +
        5 +
        3.5;
  }

  /// Matches [_contentTitleTemplate2] in the preview (rule under the label).
  static double _template2SectionTitleHeight(String title, String fontFamily) {
    return _paint(
          title.toUpperCase(),
          ResumeTypography.headingStyle(
            fontFamily,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.6,
            height: 1.0,
          ),
          double.infinity,
        ) +
        8 +
        1;
  }

  static double sectionHeight(
    Map<String, dynamic> section, {
    required double contentWidth,
    required String fontFamily,
    required String templateId,
  }) {
    if (templateId == '1') {
      return Template1LayoutMetrics.sectionHeight(
        section,
        contentWidth: contentWidth,
        fontFamily: fontFamily,
      );
    }

    final type = section['type'];
    final body = _bodyStyle(fontFamily);
    final muted = _mutedStyle(fontFamily);
    final jobTitle = _jobTitleStyle(fontFamily);

    switch (type) {
      case 'section':
        final title = (section['title'] ?? 'SECTION').toString();
        final content = (section['content'] ?? '').toString().trim();
        var h = (templateId == '2'
                ? _template2SectionTitleHeight(title, fontFamily)
                : _contentTitleHeight(title, fontFamily)) +
            (templateId == '2' ? 10 : _titleGap);
        if (content.isNotEmpty) {
          h += _paint(content, body, contentWidth);
        }
        return h + (templateId == '2' ? 18 : _sectionBottomPad);

      case 'experience':
        return _experienceHeight(
          section,
          contentWidth: contentWidth,
          fontFamily: fontFamily,
          templateId: templateId,
          body: body,
          muted: muted,
          jobTitle: jobTitle,
        );

      case 'education':
        final items = (section['items'] as List?) ?? const [];
        final showHeading =
            (section['t1_show_section_heading'] as bool?) ?? true;
        var h = showHeading
            ? _contentTitleHeight('EDUCATION', fontFamily) + _titleGap
            : 0.0;
        for (final raw in items) {
          final ed = raw as Education;
          final deg = ed.degree.trim();
          final inst = ed.institution.trim();
          final yr = ed.year.trim();
          final leftW = contentWidth * 0.72;
          var rowH = 0.0;
          if (deg.isNotEmpty) rowH += _paint(deg, jobTitle, leftW);
          if (inst.isNotEmpty) {
            rowH += (deg.isNotEmpty ? 2 : 0) + _paint(inst, muted, leftW);
          }
          if (yr.isNotEmpty) {
            final yrH = _paint(yr, muted, contentWidth * 0.26);
            if (yrH > rowH) rowH = yrH;
          }
          h += rowH + 8;
        }
        return h + _sectionBottomPad;

      case 'certifications':
      case 'projects':
      case 'courses':
      case 'achievement':
        final title = switch (type) {
          'projects' => 'PROJECTS',
          'courses' => 'COURSES',
          'certifications' => 'CERTIFICATIONS',
          _ => 'ACHIEVEMENTS',
        };
        final items = (section['items'] as List?) ?? const [];
        final showHeading =
            (section['t1_show_section_heading'] as bool?) ?? true;
        var h = showHeading
            ? _contentTitleHeight(title, fontFamily) + _titleGap
            : 0.0;
        final bulletW = math.max(40.0, contentWidth - _bulletIndent);
        for (final raw in items) {
          final line = raw.toString().trim();
          if (line.isEmpty) continue;
          h += _paint(line, body, bulletW) + _bulletGap;
        }
        return h + _sectionBottomPad;

      default:
        return 48;
    }
  }

  static double _experienceHeight(
    Map<String, dynamic> section, {
    required double contentWidth,
    required String fontFamily,
    required String templateId,
    required TextStyle body,
    required TextStyle muted,
    required TextStyle jobTitle,
  }) {
    final t1wh = (section['t1_show_work_heading'] as bool?) ?? true;
    final t1jh = (section['t1_show_job_header'] as bool?) ?? true;
    final items = (section['items'] as List?) ?? const [];
    var h = 0.0;

    final heading = templateId == '2'
        ? 'PROFESSIONAL EXPERIENCE'
        : (templateId == '4'
            ? 'EMPLOYMENT HISTORY'
            : (templateId == '1' ? 'WORK EXPERIENCE' : 'Employment History'));

    if (t1wh) {
      h += templateId == '2'
          ? _template2SectionTitleHeight(heading, fontFamily) + 10
          : _contentTitleHeight(heading, fontFamily) + _titleGap;
    }

    for (var itemIdx = 0; itemIdx < items.length; itemIdx++) {
      final exp = items[itemIdx] as Experience;
      if (itemIdx > 0 && templateId != '2') h += 6.0;

      final bullets = exp.description
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();

      if (templateId == '2') {
        final showHeader = items.length > 1 || t1jh;
        final split = ExperienceDisplay.splitIntroFromBullets(
          bullets,
          allowIntro: showHeader,
        );
        final intro = split.intro;
        final bulletLines = split.bullets;

        if (showHeader) {
          final role = exp.role.trim();
          final company = exp.company.trim();
          final when = exp.duration.trim();
          if (role.isNotEmpty || when.isNotEmpty) {
            final dateW =
                when.isNotEmpty ? math.max(72.0, contentWidth * 0.34) : 0.0;
            final roleW = math.max(
              80.0,
              contentWidth - dateW - (when.isNotEmpty ? 8.0 : 0.0),
            );
            final roleH = role.isNotEmpty
                ? _paint(role.toUpperCase(), jobTitle, roleW)
                : 0.0;
            final dateH =
                when.isNotEmpty ? _paint(when, muted, dateW) : 0.0;
            h += math.max(roleH, dateH);
          }
          if (company.isNotEmpty) {
            h += 4 + _paint(company, muted, contentWidth);
          }
          if (intro != null && intro.isNotEmpty) {
            h += 8 + _paint(intro, body, contentWidth);
          }
        } else {
          h += 2;
        }

        if (bulletLines.isNotEmpty) {
          h += intro == null || !showHeader ? 8 : 6;
          for (final b in bulletLines) {
            if (ExperienceDisplay.looksLikeResponsibilitiesHeading(b)) {
              h += 22;
              continue;
            }
            if (ExperienceDisplay.looksLikeMetaLine(b)) {
              h += _paint(b, body.copyWith(fontWeight: FontWeight.w800),
                      contentWidth) +
                  3;
              continue;
            }
            h += _paint(b.startsWith('•') ? b : '• $b', body, contentWidth) + 3;
          }
        }
        if (itemIdx < items.length - 1) {
          h += 12 + 1;
        }
        continue;
      }

      final showJobHeader = items.length > 1 || t1jh;
      if (showJobHeader) {
        final role = exp.role.trim();
        final when = AIResumeParser.formatExperienceDurationDisplay(
          exp.duration.trim().isNotEmpty
              ? exp.duration
              : (AIResumeParser.experiencePeriodFromFreeText(
                    '${exp.role} ${exp.company}',
                  ) ??
                  ''),
        );
        final company = exp.company.trim();
        if (role.isNotEmpty || when.isNotEmpty) {
          final dateW =
              when.isNotEmpty ? math.max(72.0, contentWidth * 0.34) : 0.0;
          final roleW = math.max(
            80.0,
            contentWidth - dateW - (when.isNotEmpty ? 8.0 : 0.0),
          );
          final roleH =
              role.isNotEmpty ? _paint(role, jobTitle, roleW) : 0.0;
          final dateH =
              when.isNotEmpty ? _paint(when, muted, dateW) : 0.0;
          h += math.max(roleH, dateH);
        }
        if (company.isNotEmpty) h += 3 + _paint(company, muted, contentWidth);
        h += 6;
      } else {
        h += 2;
      }

      final bulletW = math.max(40.0, contentWidth - _bulletIndent);
      for (final b in bullets) {
        h += _paint(b, body, bulletW) + _bulletGap;
      }
      if (itemIdx < items.length - 1) h += 6;
    }

    return h + (templateId == '1' ? 4.0 : 18.0);
  }

  /// How many sections fit in [availHeight] (main column).
  static int fitSectionCount({
    required List<Map<String, dynamic>> sections,
    required double availHeight,
    required double contentWidth,
    required String fontFamily,
    required String templateId,
  }) {
    if (sections.isEmpty) return 0;
    final budget = packBudgetFor(templateId);
    final limit = templateId == '1'
        ? availHeight - Template1LayoutMetrics.renderSafetyMargin
        : availHeight - renderSafetyMargin + budget;

    var used = 0.0;
    var count = 0;
    for (final s in sections) {
      final h = sectionHeight(
        s,
        contentWidth: contentWidth,
        fontFamily: fontFamily,
        templateId: templateId,
      );
      if (count > 0 && used + h > limit) break;
      if (count == 0 && h > limit + budget) {
        count = 1;
        break;
      }
      used += h;
      count++;
    }
    return math.max(1, count);
  }

  static double stackedSectionsHeight({
    required List<Map<String, dynamic>> sections,
    required double contentWidth,
    required String fontFamily,
    required String templateId,
  }) {
    var total = 0.0;
    for (final s in sections) {
      total += sectionHeight(
        s,
        contentWidth: contentWidth,
        fontFamily: fontFamily,
        templateId: templateId,
      );
    }
    return total;
  }
}
