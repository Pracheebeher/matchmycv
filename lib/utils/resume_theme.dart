import 'package:flutter/material.dart';

import 'resume_typography.dart';

class ResumeTheme {
  static const accent = Color(0xFF4A90E2);

  static const nameStyle = TextStyle(
    fontSize: ResumeTypography.name,
    fontWeight: FontWeight.bold,
  );

  static const sectionTitle = TextStyle(
    fontSize: ResumeTypography.sectionTitle,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );

  static const body = TextStyle(
    fontSize: ResumeTypography.body,
    height: ResumeTypography.lineHeightBody,
  );
}