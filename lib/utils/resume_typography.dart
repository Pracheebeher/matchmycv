import 'package:flutter/painting.dart';

import 'resume_typography_sizes.dart';

export 'resume_typography_sizes.dart' show ResumeTypographySizes;

/// Universal font scale for every resume template (preview + export).
///
/// Use [heading] for section titles, job titles, and sidebar headings.
/// Use [body] for bullets, summary, dates, company lines, and chips.
/// Use [name] only for the candidate name in template banners.
class ResumeTypography {
  ResumeTypography._();

  static const double heading = ResumeTypographySizes.heading;
  static const double body = ResumeTypographySizes.body;
  static const double name = ResumeTypographySizes.name;

  static const double lineHeightBody = ResumeTypographySizes.lineHeightBody;
  static const double lineHeightTight = ResumeTypographySizes.lineHeightTight;

  static const double sectionTitle = heading;
  static const double jobTitle = heading;
  static const double bodyCompact = heading;
  static const double bodyMuted = body;
  static const double caption = body;

  static TextStyle headingStyle(
    String fontFamily, {
    Color? color,
    FontWeight fontWeight = FontWeight.w900,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: heading,
      fontWeight: fontWeight,
      height: height ?? lineHeightTight,
      letterSpacing: letterSpacing ?? 1.0,
      color: color,
    );
  }

  static TextStyle bodyStyle(
    String fontFamily, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: body,
      fontWeight: fontWeight,
      height: height ?? lineHeightBody,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static TextStyle nameStyle(
    String fontFamily, {
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: name,
      fontWeight: fontWeight,
      height: height ?? 1.15,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}
