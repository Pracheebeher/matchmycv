import 'package:flutter/material.dart';
import '../utils/resume_theme.dart';

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ResumeTheme.sectionTitle),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 40,
          color: ResumeTheme.accent,
        ),
      ],
    );
  }
}