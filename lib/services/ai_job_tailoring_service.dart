import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/resume_model.dart';
import 'ai_cover_letter_service.dart';

/// OpenAI-assisted tailoring for cover letters and resumes vs a job description.
/// Uses the same `--dart-define=OPENAI_API_KEY=...` pattern as [AIATSService].
class ResumeJobTailorSuggestion {
  final String suggestedSummary;
  final String suggestedSkillsAddCsv;
  final String matchNotes;

  const ResumeJobTailorSuggestion({
    required this.suggestedSummary,
    required this.suggestedSkillsAddCsv,
    required this.matchNotes,
  });
}

class AIJobTailoringService {
  static const String _apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const Duration _timeout = Duration(seconds: 120);
  static const int _maxJdChars = 14000;
  static const int _maxResumeChars = 24000;

  static String resumePlainText(ResumeData d) {
    final sb = StringBuffer();
    sb.writeln('CONTACT');
    sb.writeln('Name: ${d.name}');
    sb.writeln('Email: ${d.email}');
    sb.writeln('Phone: ${d.phone}');
    String firstNonEmptyCat(String key) {
      for (final s in d.categories[key] ?? const <String>[]) {
        final t = s.trim();
        if (t.isNotEmpty) return t;
      }
      return '';
    }

    final city = firstNonEmptyCat('City');
    final country = firstNonEmptyCat('Country');
    if (city.isNotEmpty) sb.writeln('City: $city');
    if (country.isNotEmpty) sb.writeln('Country: $country');
    if (city.isEmpty && country.isEmpty) {
      final loc = d.categories['Location'] ?? const <String>[];
      if (loc.isNotEmpty) {
        sb.writeln('Location: ${loc.join(', ')}');
      }
    }
    sb.writeln();

    if (d.summary.trim().isNotEmpty) {
      sb.writeln('SUMMARY');
      sb.writeln(d.summary.trim());
      sb.writeln();
    }

    if (d.skills.isNotEmpty) {
      sb.writeln('SKILLS');
      sb.writeln(d.skills.join(', '));
      sb.writeln();
    }

    if (d.experiences.isNotEmpty) {
      sb.writeln('EXPERIENCE');
      for (final e in d.experiences) {
        sb.writeln('${e.role} — ${e.company} (${e.duration})');
        for (final line in e.description) {
          final t = line.trim();
          if (t.isNotEmpty) sb.writeln('- $t');
        }
        sb.writeln();
      }
    }

    if (d.educationList.isNotEmpty) {
      sb.writeln('EDUCATION');
      for (final ed in d.educationList) {
        sb.writeln(
          '${ed.degree} — ${ed.institution} (${ed.year})'.trim(),
        );
      }
      sb.writeln();
    }

    for (final e in d.categories.entries) {
      if (e.value.isEmpty) continue;
      if (e.key == 'Location' ||
          e.key == 'City' ||
          e.key == 'Country') {
        continue;
      }
      sb.writeln(e.key.toUpperCase());
      sb.writeln(e.value.join(', '));
      sb.writeln();
    }

    return sb.toString().trim();
  }

  static String _postProcessCoverLetterOutput(
    String raw, {
    required String dateLine,
    required String applicantName,
    required String company,
  }) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r"(?i)today'?s\s+date\b"), dateLine);
    s = s.replaceAll(RegExp(r'(?i)\bplaceholder\s+date\b'), dateLine);
    s = s.replaceAll(
      RegExp(r'\nHiring Manager\n[^\n\r]+', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\nHiring Manager\s*\n', caseSensitive: false),
      '\n',
    );

    final name = applicantName.trim();
    if (name.isNotEmpty) {
      s = s.replaceFirstMapped(
        RegExp(
          r'(Sincerely,)[ \t]*\r?\n\s*Your Name\b',
          caseSensitive: false,
        ),
        (m) => '${m[1]}\n$name',
      );
      s = s.replaceAll(RegExp(r'(?m)^\s*Your Name\s*$'), name);
    }
    return s.trim();
  }

  /// Cover letter: uses JD when provided; falls back to offline template if no API key.
  static Future<String> generateCoverLetterTailored({
    required String company,
    required String position,
    required String skills,
    String applicantName = '',
    String jobDescription = '',
  }) async {
    final dateLine = AICoverLetterService.formattedLetterDate();
    final co = company.trim();

    if (_apiKey.isEmpty) {
      return AICoverLetterService.generate(
        company: company,
        position: position,
        skills: skills,
        applicantName: applicantName,
      );
    }

    final jd = jobDescription.trim();
    final jdBlock = jd.isEmpty
        ? ''
        : '\nJob description (tailor to this posting; do not copy sentences verbatim):\n'
            '${jd.length > _maxJdChars ? jd.substring(0, _maxJdChars) : jd}\n';

    final nameLine = applicantName.trim().isEmpty
        ? 'Applicant name: (not provided — end with "Sincerely," only, no placeholder name line)'
        : 'Applicant name to print on the line after "Sincerely," (exact spelling): ${applicantName.trim()}';

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'messages': [
              {
                'role': 'system',
                'content':
                    'You write concise, professional cover letters. Output ONLY the letter body as plain text '
                    '(no JSON, no markdown fences). '
                    'Structure: (1) First line must be the calendar date string provided in the user message — use it exactly, '
                    'never the words "today\'s date" or any placeholder. '
                    '(2) Do not add a recipient or address block after the date: no "Hiring Manager" line, no company street/mailing lines. '
                    '(3) Then a blank line, then a Subject line that includes the role title, then Dear Hiring Manager, '
                    'then 2–3 short paragraphs, a short closing, then "Sincerely," and if an applicant name is provided, that name alone on the next line. '
                    'Do not invent employers, degrees, or credentials not implied by the user inputs. '
                    'If a job description is provided, align language to responsibilities and keywords without plagiarizing.',
              },
              {
                'role': 'user',
                'content':
                    'First line of the letter must be exactly this date (copy verbatim): $dateLine\n'
                    '$nameLine\n'
                    'Company (mention in body only as needed): $co\n'
                    'Role: ${position.trim()}\n'
                    'Skills / strengths (comma-separated): ${skills.trim()}'
                    '$jdBlock',
              },
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw StateError(_extractApiError(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List<dynamic>)[0]['message']['content']?.toString();
    final out = (content ?? '').trim();
    if (out.isEmpty) {
      throw StateError('Empty response from AI.');
    }
    return _postProcessCoverLetterOutput(
      out,
      dateLine: dateLine,
      applicantName: applicantName,
      company: co,
    );
  }

  /// Suggests a stronger summary + skills to add from the JD (truthful; no invented employers).
  static Future<ResumeJobTailorSuggestion> tailorResumeToJob({
    required ResumeData data,
    required String jobDescription,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'OpenAI API key is not set. Run or build with --dart-define=OPENAI_API_KEY=your_key',
      );
    }

    final jd = jobDescription.trim();
    if (jd.isEmpty) {
      throw StateError('Job description is empty.');
    }

    var resume = resumePlainText(data);
    if (resume.length > _maxResumeChars) {
      resume = resume.substring(0, _maxResumeChars);
    }
    final jdTrim = jd.length > _maxJdChars ? jd.substring(0, _maxJdChars) : jd;

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are an expert resume coach. Given a resume (plain text) and a job description, return ONLY JSON with keys: '
                    'suggested_summary (string), suggested_skills_add (string of comma-separated NEW skills/phrases to add that are supported by the resume and JD), '
                    'match_notes (string, short bullet guidance). '
                    'Do not invent employers, degrees, dates, certifications, or tools not evidenced by the resume text. '
                    'Do not copy the job description verbatim into the summary.',
              },
              {
                'role': 'user',
                'content': 'RESUME:\n$resume\n\nJOB DESCRIPTION:\n$jdTrim\n',
              },
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw StateError(_extractApiError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (body['choices'] as List<dynamic>)[0]['message']['content']?.toString();
    if (content == null || content.trim().isEmpty) {
      throw StateError('Empty AI response.');
    }

    final parsed = jsonDecode(content) as Map<String, dynamic>;
    return ResumeJobTailorSuggestion(
      suggestedSummary: (parsed['suggested_summary'] ?? '').toString().trim(),
      suggestedSkillsAddCsv:
          (parsed['suggested_skills_add'] ?? '').toString().trim(),
      matchNotes: (parsed['match_notes'] ?? '').toString().trim(),
    );
  }

  static String _extractApiError(http.Response response) {
    try {
      final err = jsonDecode(response.body) as Map<String, dynamic>?;
      final error = err?['error'];
      if (error is Map && error['message'] != null) {
        return 'API error (HTTP ${response.statusCode}): ${error['message']}';
      }
    } catch (_) {}
    return 'API request failed (HTTP ${response.statusCode}).';
  }
}
