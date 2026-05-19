import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/resume_model.dart';
import 'resume_typography.dart';

/// Measures template 1 section heights with [TextPainter] so pagination matches preview/PDF.
class Template1LayoutMetrics {
  Template1LayoutMetrics._();

  static const double _sectionBottomPad = 12.0;
  static const double _titleGap = 8.0;
  static const double _bulletGap = 4.0;
  static const double _bulletIndent = 14.0;

  /// Subtracted from usable page height so packed content never clips at the bottom.
  static const double renderSafetyMargin = 16.0;

  static const double _chipHPadding = 16.0;
  static const double _chipVPadding = 7.0;
  static const double _chipSpacing = 5.0;
  static const double _chipRunSpacing = 5.0;

  static double _paint(String text, TextStyle style, double maxWidth) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: t, style: style),
      textDirection: TextDirection.ltr,
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

  static double sectionHeight(
    Map<String, dynamic> section, {
    required double contentWidth,
    required String fontFamily,
  }) {
    final type = section['type'];
    final body = _bodyStyle(fontFamily);
    final muted = _mutedStyle(fontFamily);
    final jobTitle = _jobTitleStyle(fontFamily);

    switch (type) {
      case 'section':
        final title = (section['title'] ?? 'SECTION').toString();
        final content = (section['content'] ?? '').toString().trim();
        var h = _contentTitleHeight(title, fontFamily) + _titleGap;
        if (content.isNotEmpty) {
          h += _paint(content, body, contentWidth);
        }
        return h + _sectionBottomPad;

      case 'experience':
        final t1wh = (section['t1_show_work_heading'] as bool?) ?? true;
        final t1jh = (section['t1_show_job_header'] as bool?) ?? true;
        final items = (section['items'] as List?) ?? const [];
        var h = 0.0;
        if (t1wh) {
          h += _contentTitleHeight('WORK EXPERIENCE', fontFamily) + _titleGap;
        }
        for (var itemIdx = 0; itemIdx < items.length; itemIdx++) {
          final exp = items[itemIdx] as Experience;
          if (itemIdx > 0) {
            // SizedBox(5) + Divider(1) between jobs on the same page.
            h += 6.0;
          }
          // Multiple jobs on one page always get a header; single-item slices may hide
          // it when continuing bullets from a prior page (t1_show_job_header: false).
          final showJobHeader = items.length > 1 || t1jh;
          if (showJobHeader) {
            final role = exp.role.trim();
            final when = exp.duration.trim();
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
            if (company.isNotEmpty) {
              h += 3 + _paint(company, muted, contentWidth);
            }
            h += 6;
          } else {
            h += 2;
          }
          final bulletW = math.max(40.0, contentWidth - _bulletIndent);
          for (final b in exp.description) {
            final t = b.trim();
            if (t.isEmpty) continue;
            h += _paint(t, body, bulletW) + _bulletGap;
          }
          if (itemIdx < items.length - 1) {
            h += 6;
          }
        }
        return h + 4.0;

      case 'education':
        final items = (section['items'] as List?) ?? const [];
        final showEduHeading =
            (section['t1_show_section_heading'] as bool?) ?? true;
        var h = showEduHeading
            ? _contentTitleHeight('EDUCATION', fontFamily) + _titleGap
            : 0.0;
        for (final raw in items) {
          final ed = raw as Education;
          final deg = ed.degree.trim();
          final inst = ed.institution.trim();
          final yr = ed.year.trim();
          final leftW = contentWidth * 0.72;
          var rowH = 0.0;
          if (deg.isNotEmpty) {
            rowH += _paint(deg, jobTitle, leftW);
          }
          if (inst.isNotEmpty) {
            rowH += (deg.isNotEmpty ? 2 : 0) +
                _paint(inst, muted, leftW);
          }
          if (yr.isNotEmpty) {
            final yrH = _paint(yr, muted, contentWidth * 0.26);
            if (yrH > rowH) rowH = yrH;
          }
          h += rowH + 8;
        }
        return h + _sectionBottomPad;

      case 'skills':
        final items = (section['items'] as List?) ?? const [];
        var h = _contentTitleHeight('SKILLS', fontFamily) + 6;
        if (items.isNotEmpty) {
          final labels = items.map((e) => e.toString().trim()).where((s) => s.isNotEmpty);
          h += _skillChipsWrapHeight(labels.toList(), contentWidth, fontFamily);
        }
        return h + _sectionBottomPad;

      case 'projects':
      case 'courses':
      case 'certifications':
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

      case 'references':
        final items = (section['items'] as List?) ?? const [];
        var h = _contentTitleHeight('REFERENCES', fontFamily) + _titleGap;
        for (final raw in items) {
          final block = raw.toString().trim();
          if (block.isEmpty) continue;
          h += _paint(block, body, contentWidth) + 8;
        }
        return h + _sectionBottomPad;

      default:
        return 48;
    }
  }

  /// Matches [_template1SkillValueWrap] chip rows in the preview.
  static double _skillChipsWrapHeight(
    List<String> items,
    double contentWidth,
    String fontFamily,
  ) {
    if (items.isEmpty) return 0;
    final style = ResumeTypography.bodyStyle(
      fontFamily,
      fontWeight: FontWeight.w700,
    ).copyWith(height: 1.05, fontSize: ResumeTypography.body);

    double chipWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: contentWidth * 0.88);
      return painter.size.width + _chipHPadding;
    }

    double chipHeight(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: contentWidth * 0.88);
      return painter.size.height + _chipVPadding;
    }

    var rowW = 0.0;
    var rows = 1;
    var rowMaxH = 0.0;
    for (final label in items) {
      final w = chipWidth(label);
      final h = chipHeight(label);
      if (rowW > 0 && rowW + _chipSpacing + w > contentWidth) {
        rows++;
        rowW = w;
        rowMaxH = h;
      } else {
        rowW += rowW > 0 ? _chipSpacing + w : w;
        if (h > rowMaxH) rowMaxH = h;
      }
    }
    return rows * rowMaxH + (rows - 1) * _chipRunSpacing;
  }

  static double stackedSectionsHeight({
    required List<Map<String, dynamic>> sections,
    required double contentWidth,
    required String fontFamily,
  }) {
    var total = 0.0;
    for (final s in sections) {
      total += sectionHeight(s, contentWidth: contentWidth, fontFamily: fontFamily);
    }
    return total;
  }
}
