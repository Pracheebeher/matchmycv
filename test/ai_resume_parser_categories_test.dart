import 'package:flutter_test/flutter_test.dart';
import 'package:matchmycv/models/resume_model.dart';
import 'package:matchmycv/services/ai_resume_parser.dart';

void main() {
  group('AIResumeParser category hygiene', () {
    test('sanitizeExtractedData removes PDF page footer noise', () {
      final d = ResumeData();
      d.categories['Courses'] = ['Page 3 of 3', 'Kubernetes Workshop'];
      d.categories['Certifications'] = ['Page 2 of 2', 'AWS Solutions Architect'];

      AIResumeParser.sanitizeExtractedData(d);

      expect(d.categories['Courses'], ['Kubernetes Workshop']);
      expect(d.categories['Certifications'], ['AWS Solutions Architect']);
    });

    test('applyQuickLocalParse does not treat standalone Training as Courses', () {
      final d = ResumeData();
      const text = '''
Skills
Python

Training
Page 3 of 3

Summary
Builder text
''';

      AIResumeParser.applyQuickLocalParse(text, d);
      AIResumeParser.sanitizeExtractedData(d);

      expect(
        (d.categories['Courses'] ?? []).where((s) => s.trim().isNotEmpty).toList(),
        isEmpty,
      );
      expect(
        (d.categories['Courses'] ?? []).join(' ').toLowerCase(),
        isNot(contains('page 3')),
      );
    });

    test('mergeCoursesAndCertificationsFromFullText picks certs after combined heading',
        () {
      final d = ResumeData();
      const text = '''
Experience
Company A

Certifications & Training
AWS Certified Developer - Associate
Google Professional Cloud Architect

Courses
Advanced Algorithms
Operating Systems
''';

      AIResumeParser.applyQuickLocalParse(text, d);
      AIResumeParser.sanitizeExtractedData(d);
      AIResumeParser.mergeCoursesAndCertificationsFromFullText(text, d);

      final certs = d.categories['Certifications'] ?? [];
      final courses = d.categories['Courses'] ?? [];

      expect(certs, isNotEmpty);
      expect(
        certs.any((c) => c.toLowerCase().contains('aws')),
        isTrue,
        reason: 'Expected AWS cert line under combined heading',
      );
      expect(courses, isNotEmpty);
      expect(
        courses.any((c) => c.toLowerCase().contains('algorithms')),
        isTrue,
        reason: 'Expected course line under Courses heading',
      );
      expect(
        [...certs, ...courses].join(' ').toLowerCase(),
        isNot(contains('page ')),
        reason: 'Page markers should never appear in extracted lists',
      );
    });

    test('section headings may include subtitles on the same line', () {
      final d = ResumeData();
      const text = '''
Professional Development — 2024
Advanced Negotiation Workshop

Certifications & Training
AWS Certified Developer
''';

      AIResumeParser.applyQuickLocalParse(text, d);
      AIResumeParser.sanitizeExtractedData(d);

      expect(
        (d.categories['Courses'] ?? []).join('\n').toLowerCase(),
        contains('negotiation'),
      );
      expect(
        (d.categories['Certifications'] ?? []).join('\n').toLowerCase(),
        contains('aws'),
      );
    });

    test('merge dedupes case-insensitively with existing items', () {
      final d = ResumeData();
      d.categories['Courses'] = ['Existing Course'];
      const text = '''
Courses
Data Structures
existing course
''';

      AIResumeParser.mergeCoursesAndCertificationsFromFullText(text, d);

      expect(d.categories['Courses']!.length, 2);
      expect(
        d.categories['Courses']!.any((s) => s.toLowerCase().contains('structures')),
        isTrue,
      );
    });

    test('merge picks achievements under honors-style headings', () {
      final d = ResumeData();
      const text = '''
Experience
Acme Corp

Honors & Awards
Dean's List 2020
Employee of the Year 2022

Professional Qualifications
PMP, Six Sigma Green Belt

Workshops
Design Thinking Intensive
''';

      AIResumeParser.applyQuickLocalParse(text, d);
      AIResumeParser.sanitizeExtractedData(d);
      AIResumeParser.mergeCoursesAndCertificationsFromFullText(text, d);

      final ach = d.categories['Achievements'] ?? [];
      final certs = d.categories['Certifications'] ?? [];
      final courses = d.categories['Courses'] ?? [];

      expect(
        ach.any((s) => s.toLowerCase().contains('dean')),
        isTrue,
        reason: 'Expected honors line under Achievements',
      );
      expect(
        certs.any((s) => s.toLowerCase().contains('pmp')),
        isTrue,
        reason: 'Expected professional qualifications under Certifications',
      );
      expect(
        courses.any((s) => s.toLowerCase().contains('design thinking')),
        isTrue,
        reason: 'Expected workshop line under Courses',
      );
    });

    test('blank line after heading still collects certification lines', () {
      final d = ResumeData();
      const text = '''
Certifications

AWS Certified Developer

Courses

Data Structures
''';

      AIResumeParser.applyQuickLocalParse(text, d);
      AIResumeParser.sanitizeExtractedData(d);
      AIResumeParser.mergeCoursesAndCertificationsFromFullText(text, d);

      expect(
        (d.categories['Certifications'] ?? []).any((s) => s.toLowerCase().contains('aws')),
        isTrue,
      );
      expect(
        (d.categories['Courses'] ?? []).any((s) => s.toLowerCase().contains('structures')),
        isTrue,
      );
    });
  });
}
