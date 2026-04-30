import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../models/resume_model.dart';
import '../utils/category_entry_display.dart';
import '../utils/pdf_export_ats_markers.dart';
import 'pdf_text_extractor.dart';

class AIResumeParser {
  /// Prefer `--dart-define=OPENAI_API_KEY=...` (same as ATS / tailoring).
  static const String _apiKeyFromEnv = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static String get _effectiveOpenAiKey => _apiKeyFromEnv.trim();

  /// Max characters sent to the model (large PDFs slow the API with little benefit).
  static const int _maxCharsForModel = 10000;

  static const Duration _openAiTimeout = Duration(seconds: 32);

  /// Removes the embedded machine text layer we add to styled template PDF exports.
  /// That layer is intentionally verbose (for ATS extractors) and must not be
  /// interpreted as resume sections on re-import.
  static String stripEmbeddedMachineAtsText(String raw) {
    return PdfExportAtsMarkers.stripEmbeddedMachineText(raw);
  }

  static int _wordCount(String s) {
    return s
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .length;
  }

  /// Picks text for the no-network "quick parse" step.
  ///
  /// For our styled-template exports we embed an ATS machine-text block between
  /// markers. Stripping it is important to avoid polluting categories — but if
  /// the PDF text extractor mostly returns that embedded layer, stripping can
  /// leave almost nothing and the import looks "blank".
  ///
  /// Heuristic: if stripped text is much smaller than the raw extraction, fall
  /// back to raw for local parsing (categories are still sanitized afterwards).
  static String chooseTextForLocalParse(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return raw;

    // For our own exported template PDFs, prefer the embedded machine layer when present.
    // It is the most accurate representation of sections like Education / City.
    if (r.contains(PdfExportAtsMarkers.begin)) {
      final embedded = PdfExportAtsMarkers.extractEmbeddedMachineText(raw).trim();
      if (embedded.isNotEmpty) return embedded;
    }

    final stripped = stripEmbeddedMachineAtsText(raw).trim();
    if (stripped.isEmpty) return raw;

    // If markers aren't present, stripped should ~= raw anyway.
    if (!r.contains(PdfExportAtsMarkers.begin)) return stripped;

    final rw = _wordCount(r);
    final sw = _wordCount(stripped);
    if (sw == 0) return raw;
    if (rw >= 120 && sw < 40) return raw;
    if (rw >= 60 && sw < 18) return raw;
    if (stripped.length < 240 && r.length > stripped.length * 4) return raw;
    return stripped;
  }

  /// PDF extraction + quick local heuristics + sanitize (work history stays empty
  /// until [refineResumeWithOpenAI] / [parseResume] runs — same ordering as before).
  /// Fast path: no network. Use with [refineResumeWithOpenAI] when you want the
  /// blocking dialog to dismiss quickly; call [parseResume] when you must await
  /// the full pipeline (e.g. ATS checker).
  /// Cleans skills/education/experience after PDF import or stale sessions.
  /// Safe to call before showing the preview.
  static void sanitizeExtractedData(ResumeData data) {
    _sanitizeImportedResume(data);
  }

  /// Extract text, apply local parse, fill experiences from heuristics when empty,
  /// then sanitize. Returns the full extracted text for [refineResumeWithOpenAI].
  static Future<String> extractAndApplyQuickParse(
    File file,
    ResumeData data,
  ) async {
    final text = await PdfTextExtractorService.extractText(file);
    final forParse = chooseTextForLocalParse(text);
    applyQuickLocalParse(forParse.trim().isEmpty ? text : forParse, data);
    // If OpenAI refine is unavailable, still try to recover work history from the
    // raw extracted text (quick parse intentionally leaves experiences empty).
    _applyExperienceHeuristicFallback(text, data);
    _sanitizeImportedResume(data);
    mergeCoursesAndCertificationsFromFullText(text, data);
    return text;
  }

  /// Same as [extractAndApplyQuickParse], but uses bytes (more reliable than file
  /// paths on Android SAF / scoped storage).
  static Future<String> extractAndApplyQuickParseBytes(
    Uint8List pdfBytes,
    ResumeData data,
  ) async {
    final text = await PdfTextExtractorService.extractTextFromBytes(pdfBytes);
    final forParse = chooseTextForLocalParse(text);
    applyQuickLocalParse(forParse.trim().isEmpty ? text : forParse, data);
    _applyExperienceHeuristicFallback(text, data);
    _sanitizeImportedResume(data);
    mergeCoursesAndCertificationsFromFullText(text, data);
    return text;
  }

  /// OpenAI refinement + sanitize + experience fallback if still empty.
  static Future<void> refineResumeWithOpenAI(
    String fullText,
    ResumeData data,
  ) async {
    final raw = fullText.trim();
    final forModel = _headTailForOpenAiModel(
      // Prefer cleaned text for the model, but don't starve it when stripping
      // removes almost everything (common for screenshot+embedded-text PDFs).
      chooseTextForLocalParse(fullText),
      maxChars: _maxCharsForModel,
    );
    await _refineWithOpenAI(forModel, data);
    if (data.experiences.isEmpty) {
      _applyExperienceHeuristicFallback(
        raw.isNotEmpty ? raw : fullText,
        data,
      );
    }
    _sanitizeImportedResume(data);
    mergeCoursesAndCertificationsFromFullText(fullText, data);
    if (data.experiences.isEmpty) {
      _applyExperienceHeuristicFallback(
        raw.isNotEmpty ? raw : fullText,
        data,
      );
    }
  }

  /// Full import: same as [extractAndApplyQuickParse] followed by
  /// [refineResumeWithOpenAI]. Await this when the UI must not proceed until AI
  /// merge completes.
  ///
  /// Returns the **full** extracted PDF text (same string used for local + AI
  /// parsing) so callers can run extra heuristics or diagnostics if needed.
  static Future<String> parseResume(File file, ResumeData data) async {
    final text = await extractAndApplyQuickParse(file, data);
    await refineResumeWithOpenAI(text, data);
    return text;
  }

  /// Full import from in-memory PDF bytes (Android SAF / iCloud-friendly).
  static Future<String> parseResumeBytes(Uint8List pdfBytes, ResumeData data) async {
    final text = await extractAndApplyQuickParseBytes(pdfBytes, data);
    await refineResumeWithOpenAI(text, data);
    return text;
  }

  /// Long resumes often list certifications/courses near the end. A single head
  /// truncation hides that from the model — include a tail slice within the
  /// same character budget so extraction still sees end-of-document sections.
  static String _headTailForOpenAiModel(String text, {required int maxChars}) {
    final t = text.trim();
    if (t.length <= maxChars) return t;
    const marker = '\n\n--- OMITTED_MIDDLE (resume continues) ---\n\n';
    final budget = maxChars - marker.length;
    final headChars = (budget * 0.62).floor();
    var tailChars = budget - headChars;
    if (tailChars < 1200) {
      tailChars = 1200;
    }
    final head = t.substring(0, math.min(headChars, t.length));
    final tailStart = math.max(head.length, t.length - tailChars);
    final tail = t.substring(tailStart);
    return '$head$marker$tail';
  }

  static String _categoryLineFromJsonValue(dynamic x) {
    if (x == null) return '';
    if (x is String) return x.trim();
    if (x is num) return '$x'.trim();
    if (x is Map) {
      final m = Map<String, dynamic>.from(x);
      final title =
          '${m['name'] ?? m['title'] ?? m['certification'] ?? m['credential'] ?? m['course'] ?? m['license'] ?? ''}'
              .trim();
      final issuer =
          '${m['issuer'] ?? m['organization'] ?? m['organisation'] ?? m['provider'] ?? m['school'] ?? m['institution'] ?? ''}'
              .trim();
      final period =
          '${m['date'] ?? m['issued'] ?? m['year'] ?? m['expiration'] ?? m['expires'] ?? m['valid_until'] ?? ''}'
              .trim();
      final id = '${m['id'] ?? m['credential_id'] ?? ''}'.trim();
      final parts = <String>[];
      if (title.isNotEmpty) parts.add(title);
      if (issuer.isNotEmpty) parts.add(issuer);
      if (period.isNotEmpty) parts.add(period);
      if (id.isNotEmpty && id.length <= 48) parts.add(id);
      return parts.join(' — ').trim();
    }
    return '$x'.trim();
  }

  static List<String> _flatCategoryStringsFromJsonValue(dynamic v) {
    if (v is List) {
      return v
          .map(_categoryLineFromJsonValue)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length < 220 && !_isCategoryUiNoiseLine(s))
          .toList();
    }
    if (v is Map) {
      final one = _categoryLineFromJsonValue(v);
      if (one.isEmpty || one.length >= 220 || _isCategoryUiNoiseLine(one)) {
        return const [];
      }
      return [one];
    }
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return const [];
      return t
          .split(RegExp(r'\r?\n+|,\s*|\s*\|\s*'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length < 220 && !_isCategoryUiNoiseLine(s))
          .toList();
    }
    return const [];
  }

  /// PDF extractors often interleave page footers / UI chrome with section bodies.
  static bool _isCategoryUiNoiseLine(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (RegExp(r'^page\s+\d+\s+of\s+\d+', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^page\s+\d+\s*/\s*\d+', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^\d+\s*/\s*\d+$').hasMatch(t)) return true;
    if (RegExp(r'^page\s+\d+\s*$', caseSensitive: false).hasMatch(lower)) return true;
    if (lower == 'continued' ||
        lower == 'continued…' ||
        lower == 'continued...' ||
        lower.startsWith('continued on')) {
      return true;
    }
    if (RegExp(r'^confidential', caseSensitive: false).hasMatch(lower)) return true;
    if (RegExp(r'^draft(\s|$)', caseSensitive: false).hasMatch(lower)) return true;
    return false;
  }

  static void _stripCategoryUiNoise(ResumeData data) {
    void clean(String key) {
      final list = data.categories[key];
      if (list == null || list.isEmpty) return;
      data.categories[key] = list
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_isCategoryUiNoiseLine(s))
          .toList();
    }

    clean('Courses');
    clean('Certifications');
    clean('Achievements');
    clean('City');
    clean('Country');
    clean('Projects');
    clean('Volunteering');
    clean('References');
    clean('Links');
  }

  /// Heuristic parse from raw text — instant, no API. Good enough for first paint.
  static void applyQuickLocalParse(String text, ResumeData data) {
    data.resetCategoryBucketsForImport();
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final emailRe =
        RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
    data.email = emailRe.firstMatch(text)?.group(0) ?? '';

    final phoneRe = RegExp(
      r'(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{2,4}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}\b|\+?\d{10,15}\b',
    );
    data.phone = phoneRe.firstMatch(text)?.group(0)?.trim() ?? '';

    data.name = _guessName(lines);

    data.summary = _quickSummary(lines);

    data.skills = _quickSkills(text, lines);

    // Prefer lines under an Education / Academic header; fall back to degree-like lines.
    final fromSection = _educationLinesFromEducationSection(lines);
    if (fromSection.isNotEmpty) {
      data.educationList = fromSection.take(16).toList();
    } else {
      // Avoid substring false positives (e.g. company names like "Mastercraft").
      data.educationList = lines
          .map((raw) => raw.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim())
          .where(_quickEducationLine)
          .map((e) {
            final st = _structuredEducationFromFreeline(e);
            if (st != null) return _normalizeEducationRow(st);
            final y = _extractAnyEducationPeriod(e) ?? '';
            return _normalizeEducationRow(
              Education(
                degree: e.length > 120 ? '${e.substring(0, 117)}…' : e,
                institution: '',
                year: y,
              ),
            );
          })
          .take(8)
          .toList();
    }

    // IMPORTANT: do not guess "experiences" from random lines here.
    // It creates many fake jobs (each line becomes a role) and breaks previews
    // until OpenAI refinement completes. Leave experiences empty for local parse.
    // Must be mutable: the quick import path may later append heuristic experience
    // rows if OpenAI is skipped/unavailable.
    data.experiences = <Experience>[];

    _quickCategoriesFromSections(lines, data);
    _quickCategoriesFromInlineKeyValue(lines, data);
  }

  /// Scans the **full** extracted resume text for Courses, Certifications, and
  /// Achievements / awards-style blocks and **merges** them into [data.categories],
  /// deduping case-insensitively.
  ///
  /// Runs after quick-parse and again after AI refine so uploads populate the same
  /// buckets the user can edit manually in Home Builder.
  static void mergeCoursesAndCertificationsFromFullText(
    String fullText,
    ResumeData data,
  ) {
    _stripCategoryUiNoise(data);

    List<String> lines = fullText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    List<String> grabAfterHeader(RegExp headerRe, {required bool forCourses}) {
      String? active;
      final out = <String>[];
      for (final raw in lines) {
        final t = raw.trim();
        // Blank lines are common between a heading and bullets; do not drop the section.
        if (t.isEmpty) continue;
        if (headerRe.hasMatch(t)) {
          active = 'on';
          final afterColon = t.contains(':')
              ? t.split(RegExp(r':')).skip(1).join(':').trim()
              : '';
          if (afterColon.isNotEmpty && !_isCategoryUiNoiseLine(afterColon)) {
            out.add(afterColon);
          }
          continue;
        }
        if (active != null) {
          if (forCourses) {
            if (_certificationsSectionHeaderRe().hasMatch(t)) {
              active = null;
              continue;
            }
            if (_achievementsSectionHeaderRe().hasMatch(t)) {
              active = null;
              continue;
            }
          } else {
            if (_coursesSectionHeaderRe().hasMatch(t)) {
              active = null;
              continue;
            }
            if (_achievementsSectionHeaderRe().hasMatch(t)) {
              active = null;
              continue;
            }
          }
          if (_looksLikeOtherResumeSectionHeading(t)) {
            active = null;
            continue;
          }
          final cleaned = t.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim();
          if (cleaned.isEmpty || _isCategoryUiNoiseLine(cleaned)) continue;
          final wc = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          if (wc <= 18 && cleaned.length <= 180) out.add(cleaned);
        }
      }
      return out.toSet().toList();
    }

    void mergeBucket(String key, List<String> discovered) {
      if (discovered.isEmpty) return;
      final existing = (data.categories[key] ?? const <String>[])
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_isCategoryUiNoiseLine(s))
          .toList();
      final seen = <String>{for (final s in existing) s.toLowerCase()};
      final out = List<String>.from(existing);
      for (final raw in discovered) {
        final t = raw.trim();
        if (t.isEmpty || _isCategoryUiNoiseLine(t)) continue;
        final k = t.toLowerCase();
        if (seen.contains(k)) continue;
        seen.add(k);
        out.add(t);
      }
      data.categories[key] = key == 'Achievements'
          ? CategoryEntryDisplay.coalesceLooseAchievementImports(out)
          : out;
    }

    mergeBucket(
      'Certifications',
      grabAfterHeader(_certificationsSectionHeaderRe(), forCourses: false),
    );
    mergeBucket(
      'Courses',
      grabAfterHeader(_coursesSectionHeaderRe(), forCourses: true),
    );
    mergeBucket('Achievements', _grabLinesAfterAchievementsHeader(lines));

    final achMerged = data.categories['Achievements'];
    if (achMerged != null && achMerged.isNotEmpty) {
      data.categories['Achievements'] =
          CategoryEntryDisplay.coalesceLooseAchievementImports(
            List<String>.from(achMerged),
          );
    }
  }

  /// Matches common resume headings for certifications (incl. "Training & Certifications").
  ///
  /// Intentionally **prefix**-based (no trailing `$`): real PDF lines often include
  /// subtitles on the same line ("Certifications — continued", etc.). `isSectionLine`
  /// still caps typical heading length.
  static RegExp _certificationsSectionHeaderRe() {
    return RegExp(
      r'^(certifications?\b|certificates?\b|professional\s+certificates?\b|professional\s+certifications?\b|'
      r'board\s+certifications?\b|industry\s+certifications?\b|vendor\s+certifications?\b|'
      r'accreditations?\b|licenses?\b|credentials?\b|registrations?\b|'
      r'professional\s+qualifications?\b|qualifications?\s*[&:,/|+]\s*certifications?\b|'
      r'certifications?\s*[&:,/|+]\s*qualifications?\b|'
      r'licenses?\s*[&:,/|+]\s*certifications?\b|certifications?\s*[&:,/|+]\s*licenses?\b|'
      r'credentials?\s*[&:,/|+]\s*certifications?\b|'
      r'(training|professional\s+development)\s*[&:,/|+-]+\s*(certifications?|licenses?|credentials?)\b|'
      r'(certifications?|licenses?|credentials?)\s*[&:,/|+-]+\s*(training|courses?)\b)',
      caseSensitive: false,
    );
  }

  /// Course-related headings only — avoid standalone "Training" (often page noise).
  static RegExp _coursesSectionHeaderRe() {
    return RegExp(
      r'^(courses?\b|relevant\s+courses?\b|coursework\b|online\s+courses?\b|'
      r'professional\s+development\b|continuous\s+learning\b|academic\s+coursework\b|'
      r'executive\s+education\b|continuing\s+education\b|corporate\s+training\b|'
      r'technical\s+training\b|professional\s+training\b|training\s+courses?\b|'
      r'workshops?\b|seminars?\b|learning\s+(&|and)\s+development\b)',
      caseSensitive: false,
    );
  }

  /// Honors, awards, and similar recognition blocks (template 1 "ACHIEVEMENT" section).
  static RegExp _achievementsSectionHeaderRe() {
    return RegExp(
      r'^(achievements?\b|key\s+achievements?\b|notable\s+achievements?\b|professional\s+achievements?\b|'
      r'career\s+highlights?\b|accomplishments?\b|awards?\b|honou?rs?\b|honors?\b|'
      r'recognition\b|accolades?\b|distinctions?\b|scholarships?\b|fellowships?\b|'
      r'grants?\s+(&|and|,)\s+awards?\b|awards?\s+(&|and|,)\s+honou?rs?\b|'
      r'prizes?\b|medals?\b|trophies?\b)',
      caseSensitive: false,
    );
  }

  static List<String> _grabLinesAfterAchievementsHeader(List<String> lines) {
    String? active;
    final out = <String>[];
    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (_achievementsSectionHeaderRe().hasMatch(t)) {
        active = 'on';
        final afterColon = t.contains(':')
            ? t.split(RegExp(r':')).skip(1).join(':').trim()
            : '';
        if (afterColon.isNotEmpty && !_isCategoryUiNoiseLine(afterColon)) {
          out.add(afterColon);
        }
        continue;
      }
      if (active != null) {
        if (_coursesSectionHeaderRe().hasMatch(t) ||
            _certificationsSectionHeaderRe().hasMatch(t)) {
          active = null;
          continue;
        }
        if (_looksLikeOtherResumeSectionHeading(t)) {
          active = null;
          continue;
        }
        final cleaned = t.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim();
        if (cleaned.isEmpty || _isCategoryUiNoiseLine(cleaned)) continue;
        final wc = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (wc <= 22 && cleaned.length <= 200) out.add(cleaned);
      }
    }
    return out.toSet().toList();
  }

  static bool _looksLikeOtherResumeSectionHeading(String line) {
    final t = line.trim();
    if (t.length > 64) return false;
    return RegExp(
      r'^(experience|work experience|employment|education|skills|projects?|summary|profile|objective|contact|links?|references?|languages?|hobbies|volunteering|achievements?|awards?|honou?rs?|honors?|publications?)$',
      caseSensitive: false,
    ).hasMatch(t);
  }

  /// Parses one-line ATS-style exports like `Certifications: A | B`.
  /// Our own PDF export embeds categories in this compact form.
  static void _quickCategoriesFromInlineKeyValue(
    List<String> lines,
    ResumeData data,
  ) {
    // Only fill if currently empty, so explicit section parsing wins.
    void setIfEmpty(String key, List<String> values) {
      final existing = (data.categories[key] ?? const <String>[])
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (existing.isNotEmpty) return;
      if (values.isEmpty) return;
      data.categories[key] = values;
    }

    List<String> splitValues(String raw) {
      return raw
          .split(RegExp(r'\s*\|\s*|,\s*'))
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty && s.length <= 140 && !_isCategoryUiNoiseLine(s))
          .toList();
    }

    for (final line in lines) {
      final t = line.trim();
      final i = t.indexOf(':');
      if (i <= 0) continue;
      final keyRaw = t.substring(0, i).trim().toLowerCase();
      final valueRaw = t.substring(i + 1).trim();
      if (valueRaw.isEmpty) continue;

      if (keyRaw == 'certifications' ||
          keyRaw == 'certification' ||
          keyRaw == 'professional certifications' ||
          keyRaw == 'professional certification' ||
          keyRaw == 'professional qualification' ||
          keyRaw == 'professional qualifications' ||
          keyRaw == 'industry certifications' ||
          keyRaw == 'board certifications' ||
          keyRaw == 'certificates' ||
          keyRaw == 'certificate' ||
          keyRaw == 'licenses' ||
          keyRaw == 'license' ||
          keyRaw == 'credentials' ||
          keyRaw == 'credential' ||
          keyRaw == 'accreditations' ||
          keyRaw == 'accreditation' ||
          keyRaw == 'registrations' ||
          keyRaw == 'registration') {
        setIfEmpty('Certifications', splitValues(valueRaw));
        continue;
      }
      if (keyRaw == 'courses' ||
          keyRaw == 'course' ||
          keyRaw == 'relevant courses' ||
          keyRaw == 'coursework' ||
          keyRaw == 'workshops' ||
          keyRaw == 'workshop' ||
          keyRaw == 'seminars' ||
          keyRaw == 'seminar' ||
          keyRaw == 'training' ||
          keyRaw == 'professional development' ||
          keyRaw == 'executive education' ||
          keyRaw == 'continuing education' ||
          keyRaw == 'technical training') {
        setIfEmpty('Courses', splitValues(valueRaw));
        continue;
      }
      if (keyRaw == 'achievements' ||
          keyRaw == 'achievement' ||
          keyRaw == 'awards' ||
          keyRaw == 'award' ||
          keyRaw == 'honors' ||
          keyRaw == 'honor' ||
          keyRaw == 'honours' ||
          keyRaw == 'honour' ||
          keyRaw == 'recognition' ||
          keyRaw == 'accomplishments' ||
          keyRaw == 'accomplishment' ||
          keyRaw == 'scholarships' ||
          keyRaw == 'scholarship' ||
          keyRaw == 'fellowships' ||
          keyRaw == 'fellowship') {
        setIfEmpty('Achievements', splitValues(valueRaw));
        continue;
      }
    }
  }

  /// Pull Languages / Links / etc. from obvious section headers in plain text.
  static void _quickCategoriesFromSections(
    List<String> lines,
    ResumeData data,
  ) {
    final headers = <String, RegExp>{
      'Languages': RegExp(r'^(languages?|language skills)$', caseSensitive: false),
      'Courses': _coursesSectionHeaderRe(),
      'Certifications': _certificationsSectionHeaderRe(),
      'Achievements': _achievementsSectionHeaderRe(),
      'Links': RegExp(r'^(links?|urls?|websites?|portfolio|social)$', caseSensitive: false),
      'City': RegExp(r'^(city|town)\b', caseSensitive: false),
      'Country': RegExp(r'^(country|nationality)\b', caseSensitive: false),
      // NOTE: avoid matching generic "interests" — it frequently appears in professional
      // summaries and causes large mis-imports into Hobbies during PDF text extraction.
      'Hobbies': RegExp(
        r'^(hobbies|personal interests|outside work interests|extracurricular( activities)?)$',
        caseSensitive: false,
      ),
      'Volunteering':
          RegExp(r'^(volunteering|volunteer( experience| work)?)$', caseSensitive: false),
      'References': RegExp(r'^(references?)$', caseSensitive: false),
      'Projects': RegExp(r'^(projects?|personal projects?)$', caseSensitive: false),
    };

    String? active;
    final buf = <String, List<String>>{
      for (final k in headers.keys) k: [],
    };

    bool isSectionLine(String line) {
      final t = line.trim();
      if (t.length > 96) return false;
      for (final e in headers.entries) {
        if (e.value.hasMatch(t)) return true;
      }
      return RegExp(
        r'^(experience|education|skills|employment|work history|projects?|summary|contact|achievements?|awards?|honou?rs?)$',
        caseSensitive: false,
      ).hasMatch(t);
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        // Keep collecting across blank lines for structured buckets; otherwise PDFs
        // with a spacer line after the heading import nothing.
        if (active == 'Courses' ||
            active == 'Certifications' ||
            active == 'Achievements' ||
            active == 'Projects' ||
            active == 'Volunteering' ||
            active == 'References' ||
            active == 'City' ||
            active == 'Country') {
          continue;
        }
        active = null;
        continue;
      }

      if (active != null && isSectionLine(line)) {
        var sameBucket = false;
        for (final e in headers.entries) {
          if (e.key == active && e.value.hasMatch(line)) {
            sameBucket = true;
            break;
          }
        }
        if (!sameBucket) {
          active = null;
        }
      }

      String? matched;
      for (final e in headers.entries) {
        if (e.value.hasMatch(line)) {
          matched = e.key;
          break;
        }
      }

      if (matched != null) {
        active = matched;
        final afterColon = line.contains(':')
            ? line.split(RegExp(r':')).skip(1).join(':').trim()
            : '';
        if (afterColon.isNotEmpty &&
            afterColon.length < 80 &&
            !_isCategoryUiNoiseLine(afterColon)) {
          buf[matched]!.add(afterColon);
        }
        continue;
      }

      if (active != null && !isSectionLine(line)) {
        if (line.length > 120) continue;
        if (active == 'City') {
          if (buf['City']!.isEmpty && line.length <= 80) {
            buf['City']!.add(line);
          }
          continue;
        }
        if (active == 'Country') {
          if (buf['Country']!.isEmpty && line.length <= 80) {
            buf['Country']!.add(line);
          }
          continue;
        }
        if (line.contains(',')) {
          buf[active]!.addAll(
            line
                .split(',')
                .map((s) => s.trim())
                .where((s) =>
                    s.length > 1 &&
                    s.length < 90 &&
                    !_isCategoryUiNoiseLine(s)),
          );
        } else if (RegExp(r'^[•\-\*·]').hasMatch(line)) {
          final b = line.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim();
          if (b.isNotEmpty && !_isCategoryUiNoiseLine(b)) buf[active]!.add(b);
        } else if (RegExp(
          r'https?://|www\.',
          caseSensitive: false,
        ).hasMatch(line)) {
          if (!_isCategoryUiNoiseLine(line)) buf[active]!.add(line);
        } else if (active == 'Languages' || active == 'Hobbies') {
          if (line.split(RegExp(r'\s+')).length <= 6 &&
              !_isCategoryUiNoiseLine(line)) {
            buf[active]!.add(line);
          }
        } else if (active == 'Certifications' ||
            active == 'Courses' ||
            active == 'Achievements' ||
            active == 'Volunteering' ||
            active == 'References' ||
            active == 'Projects') {
          // Many resumes list these as plain one-per-line entries without bullets/commas.
          final wc = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          if (wc <= 18 &&
              line.length <= 160 &&
              !_isCategoryUiNoiseLine(line)) {
            buf[active]!.add(line);
          }
        }
      }
    }

    for (final e in buf.entries) {
      final clean = e.value
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_isCategoryUiNoiseLine(s))
          .toSet()
          .toList();
      if (clean.isEmpty) continue;
      final list = e.key == 'Achievements'
          ? CategoryEntryDisplay.coalesceLooseAchievementImports(
              List<String>.from(clean),
            )
          : List<String>.from(clean);
      data.categories[e.key] = list;
    }
  }

  static const List<String> _categoryModelKeys = [
    'Languages',
    'Courses',
    'Certifications',
    'Achievements',
    'Links',
    'Hobbies',
    'Volunteering',
    'References',
    'City',
    'Country',
  ];

  /// Merges AI `categories` object into [data.categories] when lists are non-empty.
  static void mergeCategoriesFromJson(ResumeData data, Map<String, dynamic> json) {
    final raw = json['categories'];
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);

    List<String> coerceCategoryList(dynamic v) =>
        _flatCategoryStringsFromJsonValue(v);

    String? canonicalKey(String key) {
      final n = key.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      const aliases = <String, String>{
        'language': 'Languages',
        'languages': 'Languages',
        'course': 'Courses',
        'courses': 'Courses',
        'certification': 'Certifications',
        'certifications': 'Certifications',
        'license': 'Certifications',
        'licenses': 'Certifications',
        'credential': 'Certifications',
        'credentials': 'Certifications',
        'certificate': 'Certifications',
        'certificates': 'Certifications',
        'accreditation': 'Certifications',
        'accreditations': 'Certifications',
        'professionalcertification': 'Certifications',
        'professionalcertifications': 'Certifications',
        'training': 'Courses',
        'coursework': 'Courses',
        'professionaldevelopment': 'Courses',
        'workshop': 'Courses',
        'workshops': 'Courses',
        'seminar': 'Courses',
        'seminars': 'Courses',
        'executiveeducation': 'Courses',
        'continuingeducation': 'Courses',
        'achievement': 'Achievements',
        'achievements': 'Achievements',
        'award': 'Achievements',
        'awards': 'Achievements',
        'honor': 'Achievements',
        'honors': 'Achievements',
        'honour': 'Achievements',
        'honours': 'Achievements',
        'recognition': 'Achievements',
        'accomplishment': 'Achievements',
        'accomplishments': 'Achievements',
        'accolade': 'Achievements',
        'accolades': 'Achievements',
        'distinction': 'Achievements',
        'distinctions': 'Achievements',
        'scholarship': 'Achievements',
        'scholarships': 'Achievements',
        'fellowship': 'Achievements',
        'fellowships': 'Achievements',
        'professionalqualifications': 'Certifications',
        'industrycertifications': 'Certifications',
        'boardcertifications': 'Certifications',
        'registration': 'Certifications',
        'registrations': 'Certifications',
        'link': 'Links',
        'links': 'Links',
        'url': 'Links',
        'urls': 'Links',
        'website': 'Links',
        'websites': 'Links',
        'portfolio': 'Links',
        'hobby': 'Hobbies',
        'hobbies': 'Hobbies',
        'interest': 'Hobbies',
        'interests': 'Hobbies',
        'volunteering': 'Volunteering',
        'volunteer': 'Volunteering',
        'reference': 'References',
        'references': 'References',
        'city': 'City',
        'town': 'City',
        'country': 'Country',
        'nationality': 'Country',
        'location': 'City',
        'address': 'City',
      };
      if (aliases.containsKey(n)) return aliases[n];
      for (final c in _categoryModelKeys) {
        if (c.toLowerCase() == key.trim().toLowerCase()) return c;
      }
      return null;
    }

    for (final e in map.entries) {
      final canon = canonicalKey(e.key);
      if (canon == null) continue;
      final v = e.value;
      var list = coerceCategoryList(v);
      if (canon == 'Languages') {
        list = list
            .map(CategoryEntryDisplay.normalizeLanguageStorage)
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (canon == 'Hobbies') {
        list = CategoryEntryDisplay.sanitizeHobbyItems(list);
      }
      if (list.isNotEmpty) {
        data.categories[canon] = list;
      }
    }
  }

  /// Some model responses put Courses/Certs at the top level instead of under `categories`.
  static void mergeTopLevelCategoryListsFromOpenAiJson(
    ResumeData data,
    Map<String, dynamic> json,
  ) {
    void mergeInto(String key, dynamic v) {
      final incoming = _flatCategoryStringsFromJsonValue(v);
      if (incoming.isEmpty) return;
      data.categories[key] = incoming;
    }

    mergeInto('Courses', json['courses'] ?? json['course']);
    mergeInto('Certifications', json['certifications'] ?? json['certification']);
    mergeInto(
      'Achievements',
      json['achievements'] ??
          json['achievement'] ??
          json['awards'] ??
          json['award'] ??
          json['honors'] ??
          json['honours'],
    );
  }

  static String _guessName(List<String> lines) {
    final badHeader = RegExp(
      r'^(resume|cv|curriculum|vitae|profile|contact|summary|experience|education|skills|projects?)$',
      caseSensitive: false,
    );
    for (final line in lines.take(12)) {
      if (line.contains('@')) continue;
      if (line.length > 70 || line.length < 3) continue;
      if (badHeader.hasMatch(line)) continue;
      if (RegExp(r'^\d+[./-]').hasMatch(line)) continue;
      final words = line.split(RegExp(r'\s+'));
      if (words.length < 2 || words.length > 6) continue;
      if (!RegExp(r"^[A-Za-zÀ-ÿ'.\s\-]+$").hasMatch(line)) continue;
      return line;
    }
    return '';
  }

  static String _quickSummary(List<String> lines) {
    int i = 0;
    while (i < lines.length && i < 15) {
      final l = lines[i].toLowerCase();
      if (l.contains('@') || RegExp(r'\+?\d[\d\s().-]{8,}').hasMatch(lines[i])) {
        i++;
        continue;
      }
      if (l == 'summary' ||
          l == 'professional summary' ||
          l == 'objective' ||
          l == 'profile') {
        final buf = StringBuffer();
        for (var j = i + 1; j < lines.length && j < i + 8; j++) {
          final next = lines[j];
          if (RegExp(
            r'^(experience|education|skills|projects?|employment|work history)$',
            caseSensitive: false,
          ).hasMatch(next)) break;
          if (buf.isNotEmpty) buf.writeln();
          buf.write(next);
          if (buf.length > 480) break;
        }
        final s = buf.toString().trim();
        if (s.isNotEmpty) return s;
      }
      i++;
    }
    return '';
  }

  /// Job-history / narrative lines mistaken for education or skills.
  static bool _looksLikeEmploymentOrNoise(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final x = t.toLowerCase();
    if (t.length > 200) return true;
    if (RegExp(
      r'\b(client:|stakeholder|daily status|status report|q[ao]\s|quality assurance|defect tracking|test case|jira|zephyr|confluence|sprint\b|stand-?up|marriott|ingram micro|kpmg|manpower)\b',
      caseSensitive: false,
    ).hasMatch(x)) {
      return true;
    }
    // Month/year ranges appear in BOTH jobs and education. Do not treat them as
    // "employment noise" when the line clearly looks academic — otherwise
    // `_structuredEducationFromFreeline` rejects almost all dated school lines.
    if (RegExp(
      r'\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4}\s*[-–]',
      caseSensitive: false,
    ).hasMatch(x)) {
      final eduHint = RegExp(
        r'\b(bachelor|bachelors|master|masters|mba|m\.?\s*b\.?a\.?|ph\.?\s*d\.?|doctor|doctorate|associate|diploma|degree|university|college|institute|institution|school|academy|gpa|cgpa|btech|b\.?\s*tech|mtech|m\.?\s*tech|postgraduate|undergraduate)\b',
        caseSensitive: false,
      ).hasMatch(x);
      if (!eduHint) return true;
    }
    if (RegExp(
      r'\b(19|20)\d{2}\s*[-–]\s*(present|current|now|today|\w+\s+(19|20)\d{2})\b',
      caseSensitive: false,
    ).hasMatch(x)) {
      return true;
    }
    return false;
  }

  /// True when a single resume line is plausibly an education row (not a company name).
  static bool _quickEducationLine(String raw) {
    final t = raw.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim();
    if (t.length < 10 || t.length > 180) return false;
    if (_looksLikeEmploymentOrNoise(t)) return false;
    final x = t.toLowerCase();
    final degreeish = RegExp(
      r'\b(bachelor|bachelors|b\.?\s*s\.?|b\.?\s*a\.?|b\.?\s*e\.?|btech|b\.?\s*tech|master|masters|m\.?\s*s\.?|m\.?\s*a\.?|m\.?\s*e\.?|mtech|m\.?\s*tech|mba|ph\.?\s*d\.?|doctorate|associate|diploma|h\.?\s*s\.?c|hsc|postgraduate|undergraduate|minor|concentration|cgpa|gpa)\b',
      caseSensitive: false,
    ).hasMatch(x);
    if (!degreeish) return false;
    // "Master" substring-matched "Mastercraft" — require real degree context.
    final schoolish = RegExp(
      r'\b(university|college|institute|institution|school|academy)\b',
      caseSensitive: false,
    ).hasMatch(x);
    final yearish = RegExp(r'\b(19|20)\d{2}\b').hasMatch(x);
    final compactDegree =
        t.length <= 78 && RegExp(r'\b(of|in)\b', caseSensitive: false).hasMatch(x);
    return schoolish || yearish || compactDegree;
  }

  /// Used before and after API merge; keep in sync with [_sanitizeImportedResume] filters.
  static bool _isPlausibleEducationRow(Education e) {
    final d = e.degree.trim();
    final inst = e.institution.trim();
    final y = e.year.trim();
    if (d.isEmpty && inst.isEmpty && y.isEmpty) return false;
    if (d.length > 220 || inst.length > 220) return false;
    if (_looksLikeEmploymentOrNoise('$d $inst $y')) return false;
    return true;
  }

  static const List<String> _monNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static int? _monthTokenToNumber(String token) {
    final key = token.toLowerCase().replaceAll('.', '').trim();
    const byName = <String, int>{
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return byName[key];
  }

  static String? _formatMonYearFromTokens(String mon, String yearStr) {
    final y = int.tryParse(yearStr);
    final m = _monthTokenToNumber(mon);
    if (y == null || m == null) return null;
    if (m < 1 || m > 12) return null;
    return '${_monNames[m - 1]} $y';
  }

  static String? _tryNormalizeMonYearToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return null;

    var m = RegExp(
      r'^([A-Za-z]+)\s+(\d{4})\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      return _formatMonYearFromTokens(m.group(1)!, m.group(2)!);
    }

    m = RegExp(r'^(\d{1,2})/(\d{4})\s*$').firstMatch(t);
    if (m != null) {
      final mo = int.tryParse(m.group(1)!);
      final y = int.tryParse(m.group(2)!);
      if (mo != null && y != null && mo >= 1 && mo <= 12) {
        return '${_monNames[mo - 1]} $y';
      }
    }

    m = RegExp(r'^(\d{4})-(\d{1,2})\s*$').firstMatch(t);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return '${_monNames[mo - 1]} $y';
      }
    }

    // ISO dates like 2020-09-01 or 2020-09
    m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?\s*$').firstMatch(t);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) {
        return '${_monNames[mo - 1]} $y';
      }
    }

    m = RegExp(r'^(\d{4})\s*$').firstMatch(t);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      if (y != null) return '$y';
    }

    if (RegExp(r'^(19|20)\d{2}$').hasMatch(t)) {
      return t;
    }

    return null;
  }

  static String _stripMatchedRange(String line, RegExpMatch m) {
    return (line.substring(0, m.start) + line.substring(m.end))
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\s*,\s*$'), '')
        .trim();
  }

  /// Best-effort date span for UI (`Education.year`) from a free-text blob.
  static String? _extractAnyEducationPeriod(String raw) {
    final line = raw.replaceAll(RegExp(r'[–—]'), '-').trim();
    if (line.length < 6) return null;

    final slashRange = RegExp(
      r'(?<![0-9])'
      r'(\d{1,2}/(?:19|20)\d{2})'
      r'\s*(?:-|to)\s*'
      r'(\d{1,2}/(?:19|20)\d{2})'
      r'(?![0-9])',
      caseSensitive: false,
    ).firstMatch(line);
    if (slashRange != null) {
      final a = _tryNormalizeMonYearToken(slashRange.group(1)!);
      final b = _tryNormalizeMonYearToken(slashRange.group(2)!);
      if (a != null && b != null) return '$a - $b';
    }

    final range = RegExp(
      r'(?<![A-Za-z0-9])'
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
      r'\s*(?:-|to)\s*'
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
      r'(?![A-Za-z0-9])',
      caseSensitive: false,
    ).firstMatch(line);
    if (range != null) {
      final a = _formatMonYearFromTokens(range.group(1)!, range.group(2)!);
      final b = _formatMonYearFromTokens(range.group(3)!, range.group(4)!);
      if (a != null && b != null) return '$a - $b';
    }

    final single = RegExp(
      r'(?<![A-Za-z0-9])'
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
      r'(?![A-Za-z0-9])',
      caseSensitive: false,
    ).firstMatch(line);
    if (single != null) {
      final a = _formatMonYearFromTokens(single.group(1)!, single.group(2)!);
      if (a != null) return a;
    }

    final y2 = RegExp(
      r'\b((?:19|20)\d{2})\s*-\s*((?:19|20)\d{2})\b',
    ).firstMatch(line);
    if (y2 != null) return '${y2.group(1)} - ${y2.group(2)}';

    return null;
  }

  /// Public hook for UI: pull `Sep 2020 - May 2024` / `09/2020 - 05/2022` / `2018 - 2022`
  /// from free text when imports leave [Education.year] empty but embed dates in degree/institution.
  static String? educationPeriodFromFreeText(String raw) =>
      _extractAnyEducationPeriod(raw);

  /// Fills empty [Education.year], pulls trailing year ranges off [Education.institution].
  static Education _normalizeEducationRow(Education e) {
    var degree = e.degree.trim();
    var inst = e.institution.trim();
    var year = e.year
        .trim()
        .replaceAll(RegExp(r'[–—]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (year.isEmpty) {
      final fromBlob = _extractAnyEducationPeriod('$degree $inst');
      if (fromBlob != null && fromBlob.isNotEmpty) year = fromBlob;
    }

    if (year.isEmpty && inst.isNotEmpty) {
      final m = RegExp(
        r'^(.+?)\s+((?:19|20)\d{2})\s*-\s*((?:19|20)\d{2})\s*$',
      ).firstMatch(inst.replaceAll(RegExp(r'[–—]'), '-'));
      if (m != null) {
        inst = m.group(1)!.trim();
        year = '${m.group(2)} - ${m.group(3)}';
      }
    }

    if (year.isEmpty && inst.contains(',')) {
      final parts = inst
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        final last = parts.last.replaceAll(RegExp(r'[–—]'), '-');
        if (RegExp(r'^(?:19|20)\d{2}\s*-\s*(?:19|20)\d{2}$').hasMatch(last)) {
          inst = parts.sublist(0, parts.length - 1).join(', ');
          year = last;
        }
      }
    }

    return Education(degree: degree, institution: inst, year: year);
  }

  /// Parses one free-text education line (comma-separated or single blob + year).
  static Education? _structuredEducationFromFreeline(String raw) {
    final line = raw.trim();
    if (line.length < 6 || line.length > 360) return null;
    if (_looksLikeEmploymentOrNoise(line)) return null;

    // Numeric month/year ranges like `09/2020 - 05/2022`.
    final slashRange = RegExp(
      r'(?<![0-9])'
      r'(\d{1,2}/(?:19|20)\d{2})'
      r'\s*(?:-|\u2013|\u2014|to)\s*'
      r'(\d{1,2}/(?:19|20)\d{2})'
      r'(?![0-9])',
      caseSensitive: false,
    ).firstMatch(line);

    String working = line;
    String? period;
    if (slashRange != null) {
      final a = _tryNormalizeMonYearToken(slashRange.group(1)!);
      final b = _tryNormalizeMonYearToken(slashRange.group(2)!);
      if (a != null && b != null) {
        period = '$a - $b';
        working = _stripMatchedRange(line, slashRange);
      }
    }

    // Prefer explicit month/year ranges over "last 4-digit year" heuristics.
    final range = RegExp(
      r'(?<![A-Za-z0-9])'
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
      r'\s*(?:-|\u2013|\u2014|to)\s*'
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
      r'(?![A-Za-z0-9])',
      caseSensitive: false,
    ).firstMatch(working);

    if (range != null) {
      final a = _formatMonYearFromTokens(range.group(1)!, range.group(2)!);
      final b = _formatMonYearFromTokens(range.group(3)!, range.group(4)!);
      if (a != null && b != null) {
        final merged = '$a - $b';
        // If we already extracted a slash range, keep it (word ranges often duplicate
        // the same window after stripping).
        if (period == null || period.isEmpty) {
          period = merged;
        }
      }
      working = _stripMatchedRange(working, range);
    } else {
      final single = RegExp(
        r'(?<![A-Za-z0-9])'
        r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*)\s+((?:19|20)\d{2})'
        r'(?![A-Za-z0-9])',
        caseSensitive: false,
      ).firstMatch(working);
      if (single != null) {
        final merged = _formatMonYearFromTokens(single.group(1)!, single.group(2)!);
        if (merged != null) {
          if (period == null || period.isEmpty) {
            period = merged;
          } else {
            // Keep explicit ranges; only fill in a lone graduation month/year
            // when we don't already have a richer range.
            final hasRange = period.contains('-');
            if (!hasRange) {
              period = merged;
            }
          }
        }
        working = _stripMatchedRange(working, single);
      }
    }

    final yearMatches = RegExp(r'\b(19|20)\d{2}\b')
        .allMatches(working)
        .map((m) => m.group(0)!)
        .toList();
    final year4 = yearMatches.isNotEmpty ? yearMatches.last : '';
    final year = (period != null && period.isNotEmpty) ? period : year4;

    final commaParts = working
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (commaParts.length >= 3) {
      final last = commaParts.last;
      final lastNorm = last.replaceAll(RegExp(r'[–—]'), '-');
      final lastIsPlainYear = RegExp(r'^(19|20)\d{2}$').hasMatch(lastNorm);
      final lastIsYearRange =
          RegExp(r'^(19|20)\d{2}\s*-\s*(19|20)\d{2}$').hasMatch(lastNorm);
      final yearFromParts =
          lastIsPlainYear ? lastNorm : (lastIsYearRange ? lastNorm : '');
      final chosenYear = () {
        final p = (period ?? '').trim();
        final yp = yearFromParts.trim();
        if (p.isNotEmpty && yp.isNotEmpty && p != yp) {
          // Prefer an extracted month/year range over a trailing graduation year
          // when they disagree (common in CSV-ish education lines).
          return p.contains('-') ? p : yp;
        }
        if (p.isNotEmpty) return p;
        if (yp.isNotEmpty) return yp;
        return year;
      }();

      if (lastIsPlainYear || lastIsYearRange) {
        return Education(
          degree: commaParts.first,
          institution: commaParts.sublist(1, commaParts.length - 1).join(', '),
          year: chosenYear,
        );
      }
      return Education(
        degree: commaParts.first,
        institution: commaParts.sublist(1).join(', '),
        year: chosenYear,
      );
    }
    if (commaParts.length == 2) {
      final a = commaParts[0];
      final b0 = commaParts[1];
      final b = b0.replaceAll(RegExp(r'[–—]'), '-');
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(b)) {
        return Education(degree: a, institution: '', year: year);
      }
      if (RegExp(r'^(19|20)\d{2}\s*-\s*(19|20)\d{2}$').hasMatch(b)) {
        return Education(degree: a, institution: '', year: b);
      }
      return Education(degree: a, institution: b0, year: year);
    }
    final deg = working.trim();
    if (deg.isEmpty) {
      return Education(degree: line, institution: '', year: year);
    }
    return Education(degree: deg, institution: '', year: year);
  }

  /// Collects education rows after an Education / Academic section header.
  static List<Education> _educationLinesFromEducationSection(List<String> lines) {
    final out = <Education>[];
    for (var i = 0; i < lines.length; i++) {
      final low = lines[i].toLowerCase().trim();
      final isHeader = RegExp(
        r'^(education|educational background|academic background|academic qualifications|'
        r'academic profile|academic credentials|qualifications|training\s*&\s*education|'
        r'training and education)\b',
        caseSensitive: false,
      ).hasMatch(low);
      if (!isHeader) continue;

      i++;
      while (i < lines.length) {
        final raw = lines[i].trim();
        if (raw.isEmpty) {
          i++;
          continue;
        }
        final nextLow = raw.toLowerCase();
        if (RegExp(
          r'^(experience|employment|work history|professional experience|skills|technical skills|projects?|certifications?|achievements?|awards?|honou?rs?|summary|objective|references|contact)\b',
          caseSensitive: false,
        ).hasMatch(nextLow)) {
          break;
        }
        if (RegExp(
          r'^(languages?|courses?|links?|hobbies|volunteering)\b',
          caseSensitive: false,
        ).hasMatch(nextLow)) {
          break;
        }
        final cleaned = raw.replaceFirst(RegExp(r'^[•\-\*·]\s*'), '').trim();
        if (cleaned.length >= 6) {
          var ed = _structuredEducationFromFreeline(cleaned);
          if (ed == null) {
            final y = _extractAnyEducationPeriod(cleaned) ?? '';
            ed = Education(degree: cleaned, institution: '', year: y);
          }
          ed = _normalizeEducationRow(ed);
          if (_isPlausibleEducationRow(ed)) {
            out.add(ed);
          }
        }
        i++;
      }
      break;
    }
    return out;
  }

  static Education? _coerceEducationEntry(dynamic e) {
    if (e is String) {
      final parsed = _structuredEducationFromFreeline(e.trim());
      return parsed != null ? _normalizeEducationRow(parsed) : null;
    }
    if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      var degree = '${m['degree'] ?? m['qualification'] ?? m['field'] ?? m['major'] ?? m['program'] ?? m['title'] ?? ''}'
          .trim();
      var inst = '${m['institution'] ?? m['school'] ?? m['university'] ?? m['college'] ?? m['org'] ?? ''}'
          .trim();
      var year =
          '${m['year'] ?? m['graduation'] ?? m['grad_year'] ?? m['graduationYear'] ?? m['graduation_date'] ?? m['gradDate'] ?? m['end_year'] ?? m['end'] ?? m['dates'] ?? ''}'
              .trim()
              .replaceAll('\u001e', ' ')
              .replaceAll(RegExp(r'[–—]'), '-')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

      String pickStr(dynamic v) => v == null ? '' : '$v'.trim();

      final start = pickStr(
        m['start'] ??
            m['start_date'] ??
            m['startDate'] ??
            m['from'] ??
            m['begin'] ??
            m['started'],
      );
      final end = pickStr(
        m['end'] ??
            m['end_date'] ??
            m['endDate'] ??
            m['to'] ??
            m['finished'] ??
            m['completed'],
      );
      if (year.isEmpty && (start.isNotEmpty || end.isNotEmpty)) {
        final a = _tryNormalizeMonYearToken(start);
        final b = _tryNormalizeMonYearToken(end);
        if (a != null && b != null) year = '$a - $b';
        if (a != null && b == null) year = a;
        if (a == null && b != null) year = b;
      }

      if (degree.isNotEmpty && inst.isEmpty && year.isEmpty && degree.contains(',')) {
        final parsed = _structuredEducationFromFreeline(degree);
        if (parsed != null) return _normalizeEducationRow(parsed);
      }
      if (degree.isEmpty && inst.isEmpty) return null;
      return _normalizeEducationRow(
        Education(degree: degree, institution: inst, year: year),
      );
    }
    return null;
  }

  static List<Education> _educationListFromJsonList(List<dynamic> raw) {
    return raw.map(_coerceEducationEntry).whereType<Education>().toList();
  }

  static void _mergeEducationFromOpenAiJson(
    Map<String, dynamic> json,
    ResumeData data,
  ) {
    const keys = [
      'education',
      'educations',
      'academic',
      'degrees',
      'academic_background',
    ];
    for (final k in keys) {
      final v = json[k];
      if (v is! List || v.isEmpty) continue;
      final list =
          _educationListFromJsonList(v).where(_isPlausibleEducationRow).toList();
      if (list.isNotEmpty) {
        data.educationList = list;
        return;
      }
    }
  }

  static List<String> _quickSkills(String text, List<String> lines) {
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      final h = lines[i].trim().toLowerCase();
      if (h == 'skills' ||
          h == 'skills:' ||
          h == 'technical skills' ||
          h == 'technical skills:' ||
          h == 'core skills' ||
          h == 'core skills:' ||
          h == 'core competencies' ||
          h == 'core competencies:') {
        start = i;
        break;
      }
    }
    if (start >= 0) {
      final out = <String>[];
      for (var j = start + 1; j < lines.length && j < start + 24; j++) {
        final line = lines[j].trim();
        if (line.isEmpty) continue;
        if (RegExp(
          r'^(experience|education|projects?|employment|work history|languages?|certifications?|professional experience|summary|contact)$',
          caseSensitive: false,
        ).hasMatch(line)) {
          break;
        }
        if (line.length > 85 || _looksLikeEmploymentOrNoise(line)) continue;
        final wc = line.split(RegExp(r'\s+')).length;
        if (line.contains(',')) {
          out.addAll(
            line
                .split(',')
                .map((s) => s.trim())
                .where(
                  (s) =>
                      s.length > 1 &&
                      s.length < 72 &&
                      !_looksLikeEmploymentOrNoise(s),
                ),
          );
        } else if (line.startsWith('•') ||
            line.startsWith('-') ||
            line.startsWith('*')) {
          final t = line.replaceFirst(RegExp(r'^[•\-\*]\s*'), '').trim();
          if (t.length <= 80 && !_looksLikeEmploymentOrNoise(t)) out.add(t);
        } else if (wc <= 10 && line.length <= 72) {
          out.add(line);
        }
        if (out.length >= 28) break;
      }
      if (out.isNotEmpty) return out.toSet().toList();
    }

    return lines
        .where((l) {
          final x = l.toLowerCase();
          return x.contains('testing') ||
              x.contains('agile') ||
              x.contains('sql') ||
              x.contains('api') ||
              x.contains('java') ||
              x.contains('python') ||
              x.contains('flutter') ||
              x.contains('react') ||
              x.contains('aws');
        })
        .take(16)
        .toList();
  }

  /// Splits `"Company | Jan 2020 - Dec 2022"` or `"Company  Jan 2020 - Present"`.
  static (String, String) _splitCompanyAndDurationLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return ('', '');

    if (t.contains('|')) {
      final parts =
          t.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length >= 2) {
        return (parts.first, parts.sublist(1).join(' | '));
      }
    }

    final re = RegExp(
      r'[\s\-\u2013\u2014|]+\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\s+\d{4}|\d{1,2}/\d{4}|(?:19|20)\d{2})\b',
      caseSensitive: false,
    );
    final m = re.firstMatch(t);
    if (m != null) {
      final left = t.substring(0, m.start).trim();
      final right = t
          .substring(m.start)
          .trim()
          .replaceFirst(RegExp(r'^[\s\-\u2013\u2014|]+'), '');
      if (left.isNotEmpty) return (left, right);
    }

    return (t, '');
  }

  /// When refine fails or omits jobs, infer blocks from an Experience / Work History section.
  static void _applyExperienceHeuristicFallback(String rawText, ResumeData data) {
    if (data.experiences.isNotEmpty) return;

    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    int? start;
    for (var i = 0; i < lines.length; i++) {
      final low = lines[i].toLowerCase();
      if (RegExp(
        r'^(experience|work experience|professional experience|employment(\s+history)?|work history|career history|relevant experience)\s*:?$',
        caseSensitive: false,
      ).hasMatch(low)) {
        start = i + 1;
        break;
      }
    }
    if (start == null) return;

    var end = lines.length;
    for (var i = start; i < lines.length; i++) {
      final low = lines[i].toLowerCase();
      if (RegExp(
        r'^(education|academic|skills|technical skills|core competencies|projects?|certifications?|licenses|professional skills|summary|objective|profile|references|publications|languages|volunteer|interests|awards)\b',
        caseSensitive: false,
      ).hasMatch(low)) {
        end = i;
        break;
      }
    }

    final slice = lines.sublist(start, end);
    if (slice.isEmpty) return;

    bool bullet(String l) =>
        RegExp(r'^[•\-\*·▪►◦\u2022]', caseSensitive: false).hasMatch(l);

    String cleanBullet(String l) =>
        l.replaceFirst(RegExp(r'^[•\-\*·▪►◦\u2022]\s*'), '').trim();

    bool looksLikeDatesOnly(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return false;
      // Common: "June 2018 — Present", "04/2016 — 06/2018", "01/2024 - Present,"
      if (RegExp(
        r'^(?:'
        r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4}'
        r'|\d{1,2}/\d{4}'
        r'|\d{4}'
        r')\s*[-–—]\s*(?:present|current|now|today|'
        r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4}'
        r'|\d{1,2}/\d{4}'
        r'|\d{4})\s*,?$',
        caseSensitive: false,
      ).hasMatch(t)) {
        return true;
      }
      // Also accept a single month-year token like "Jun 2018" in some PDFs.
      if (RegExp(
        r'^(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4}\s*,?$',
        caseSensitive: false,
      ).hasMatch(t)) {
        return true;
      }
      return false;
    }

    for (var i = 0; i < slice.length; ) {
      final line = slice[i];
      if (bullet(line)) {
        i++;
        continue;
      }

      // Some PDFs put a standalone date range on its own line. Never treat it as a role.
      if (looksLikeDatesOnly(line)) {
        i++;
        continue;
      }

      if (line.length > 100) {
        i++;
        continue;
      }

      final words =
          line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words < 2 || words > 16) {
        i++;
        continue;
      }

      final role = line.trim();
      i++;
      var company = '';
      var duration = '';
      final bullets = <String>[];

      if (i < slice.length && !bullet(slice[i])) {
        final meta = slice[i].trim();
        if (meta.length <= 160) {
          // Handle "role" line already containing the employer, then a pure date line next.
          if (looksLikeDatesOnly(meta)) {
            duration = meta;
            i++;
          } else {
            final split = _splitCompanyAndDurationLine(meta);
            company = split.$1.trim();
            duration = split.$2.trim();
            if (company.isEmpty && duration.isEmpty) {
              company = meta;
            }
            i++;
            // Very common: role line, then company line, then dates line.
            if (duration.isEmpty &&
                i < slice.length &&
                !bullet(slice[i]) &&
                looksLikeDatesOnly(slice[i])) {
              duration = slice[i].trim();
              i++;
            }
          }
        }
      }

      while (i < slice.length && bullet(slice[i])) {
        final b = cleanBullet(slice[i]);
        if (b.isNotEmpty && b.length <= 400) bullets.add(b);
        i++;
      }

      if (role.length < 4) continue;

      data.experiences.add(
        Experience(
          role: role,
          company: company,
          duration: duration,
          description: bullets,
        ),
      );
      if (data.experiences.length >= 24) break;
    }
  }

  static Future<void> _refineWithOpenAI(String text, ResumeData data) async {
    final apiKeyUsed = _effectiveOpenAiKey;
    if (apiKeyUsed.isEmpty) {
      // ignore: avoid_print
      print('AI resume refine skipped: no OpenAI API key.');
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKeyUsed',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'messages': [
                {
                  'role': 'user',
                  'content':
                      'Extract resume data. Reply with ONLY compact JSON, no markdown. Keys: '
                      'name,email,phone,summary,skills (string[]), '
                      'experience (array of {role,company,duration,description:string[]}), '
                      'projects (array of {name,duration,details:string[] or string} — keep details concise bullet-style), '
                      'education (array of {degree,institution,year,start,end} — degree/major, '
                      'institution is school name. If attendance dates exist, set start/end as '
                      '"Mon YYYY" or "MM/YYYY" strings, OR set year to a single string like '
                      '"Jan 2020 - May 2024" (preferred). If only graduation month/year exists, '
                      'put that in year. Aliases school/university/graduation_year OK; '
                      'string entries like "B.S. CS, MIT, 2018" allowed), '
                      'categories (object with string arrays ONLY for these keys: '
                      'Languages, Courses, Certifications, Achievements, Links, Hobbies, Volunteering, References, City, Country). '
                      'Include EVERY distinct paid role / contract / internship as its own experience object '
                      '(same employer multiple times is OK if dates or titles differ). '
                      'Do not merge separate jobs into one entry. '
                      'Put spoken languages under Languages ONLY if the resume explicitly contains a Languages / '
                      'Language Skills section. Do NOT infer or guess languages. '
                      'Each string is the language name, '
                      'optionally followed by the literal ASCII record separator character (code point 0x1E) '
                      'and ONE of native, fluent, professional, intermediate, basic for proficiency; '
                      'formal courses, workshops, seminars, executive education under Courses; '
                      'certifications, licenses, professional qualifications, registrations under Certifications; '
                      'awards, honors, scholarships, fellowships, recognition, career highlights under Achievements; '
                      'URLs or portfolio under Links; personal interests under Hobbies; '
                      'volunteer roles under Volunteering; '
                      'each reference as one string "Name — phone or email" under References; '
                      'contact city or town under City and country or region under Country when clearly stated '
                      '(omit or use [] if unknown). '
                      'IMPORTANT: Do NOT put technical skills, tools, frameworks, programming languages, '
                      'keywords, job duties, or long comma-separated keyword dumps under Hobbies. '
                      'Hobbies must be ONLY explicit personal interests/hobbies found in the resume text '
                      '(e.g. photography, chess). If there is no explicit hobbies/interests section, return '
                      'Hobbies as []. '
                      'Do not spell the separator as "U+001E" text — embed the actual 0x1E character. '
                      'Omit a key or use [] if nothing in the resume.\n\n$text',
                }
              ],
              'temperature': 0.1,
              'max_tokens': 5200,
            }),
          )
          .timeout(_openAiTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // ignore: avoid_print
        print('AI refine HTTP ${response.statusCode}: ${response.body}');
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return;

      final first = choices.first;
      if (first is! Map<String, dynamic>) return;
      final message = first['message'];
      if (message is! Map<String, dynamic>) return;
      final content = message['content'] as String? ?? '';

      if (content.isEmpty) return;

      final clean = content
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final decodedBody = jsonDecode(clean);
      if (decodedBody is! Map<String, dynamic>) return;
      final jsonData = decodedBody;

      void mergeStr(void Function(String) set, dynamic v) {
        if (v is! String) return;
        final t = v.trim();
        if (t.isNotEmpty) set(t);
      }

      mergeStr((s) => data.name = s, jsonData['name']);
      mergeStr((s) => data.email = s, jsonData['email']);
      mergeStr((s) => data.phone = s, jsonData['phone']);
      final sum = jsonData['summary'] as String?;
      if (sum != null && sum.trim().isNotEmpty) {
        data.summary = sum.trim();
      }

      final sk = jsonData['skills'];
      if (sk is List && sk.isNotEmpty) {
        final flat = <String>[];
        for (final e in sk) {
          final s = '$e'.trim();
          if (s.isEmpty) continue;
          if (s.length > 180) {
            flat.addAll(
              s
                  .split(RegExp(r'[\n;]+'))
                  .map((x) => x.trim())
                  .where((x) => x.length > 1 && x.length < 140),
            );
          } else {
            flat.add(s);
          }
        }
        if (flat.isNotEmpty) data.skills = flat;
      }

      // Models sometimes return different key names than instructed.
      final expRaw = jsonData['experience'] ??
          jsonData['experiences'] ??
          jsonData['work_experience'] ??
          jsonData['workExperience'] ??
          jsonData['employment'] ??
          jsonData['employment_history'];
      final exp = expRaw is List ? expRaw : null;
      if (exp != null && exp.isNotEmpty) {
        data.experiences = exp
            .map(
              (e) => e is Map<String, dynamic>
                  ? Experience(
                      role: '${e['role'] ?? e['title'] ?? ''}',
                      company: '${e['company'] ?? e['employer'] ?? ''}',
                      duration: '${e['duration'] ?? e['dates'] ?? ''}',
                      description: _coerceStringList(
                        e['description'] ??
                            e['bullets'] ??
                            e['highlights'] ??
                            e['responsibilities'],
                      ),
                    )
                  : null,
            )
            .whereType<Experience>()
          .toList();
      }

      _mergeEducationFromOpenAiJson(jsonData, data);

      // Projects: store in the existing "Projects" category bucket using the same
      // ASCII record-separator field format as other structured categories.
      final projRaw = jsonData['projects'] ??
          jsonData['project'] ??
          jsonData['personal_projects'] ??
          jsonData['personalProjects'];
      if (projRaw is List && projRaw.isNotEmpty) {
        final sep = CategoryEntryDisplay.sep;
        final out = <String>[];
        for (final p in projRaw) {
          if (p is String) {
            final s = p.trim();
            if (s.isNotEmpty) out.add(s);
            continue;
          }
          if (p is! Map) continue;
          final m = Map<String, dynamic>.from(p);
          final name = '${m['name'] ?? m['title'] ?? m['project'] ?? ''}'.trim();
          final duration = '${m['duration'] ?? m['dates'] ?? ''}'.trim();
          final detailsRaw = m['details'] ?? m['description'] ?? m['bullets'];
          final details = _coerceStringList(detailsRaw)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (name.isEmpty && duration.isEmpty && details.isEmpty) continue;
          final blob = [
            if (name.isNotEmpty) name,
            if (duration.isNotEmpty) duration,
            if (details.isNotEmpty) details.join(' '),
          ].join(sep);
          if (blob.trim().isNotEmpty) out.add(blob);
        }
        if (out.isNotEmpty) {
          data.categories['Projects'] = out;
        }
      }

      // Top-level keys fill gaps first; `categories` in JSON wins when both exist.
      mergeTopLevelCategoryListsFromOpenAiJson(data, jsonData);
      mergeCategoriesFromJson(data, jsonData);
    } catch (e) {
      // Keep [data] from applyQuickLocalParse.
      // ignore: avoid_print
      print('AI refine skipped: $e');
    }
  }

  static void _sanitizeImportedResume(ResumeData data) {
    bool looksLikeSentence(String s) {
      final t = s.trim();
      if (t.length < 40) return false;
      if (t.contains('.')) return true;
      if (RegExp(r'\b(and|with|for|to|in|on|as)\b', caseSensitive: false).hasMatch(t)) {
        return true;
      }
      return false;
    }

    bool plausibleSkill(String s) {
      final t = s.trim();
      if (t.isEmpty || t.length > 96) return false;
      if (looksLikeSentence(t)) return false;
      if (_looksLikeEmploymentOrNoise(t)) return false;
      return true;
    }

    // Drop obviously-wrong "jobs" created by bad parsing.
    data.experiences = data.experiences.where((e) {
      final role = e.role.trim();
      if (role.isEmpty) return false;
      if (looksLikeSentence(role) && e.company.trim().isEmpty) return false;
      return true;
    }).toList();

    // De-dupe only true duplicates (same role, employer, and date range).
    // Same company with different titles or dates must stay as separate rows.
    final seen = <String>{};
    data.experiences = data.experiences.where((e) {
      final key =
          '${e.role.trim().toLowerCase()}|${e.company.trim().toLowerCase()}|'
          '${e.duration.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';
      if (key.replaceAll('|', '').trim().isEmpty) return false;
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();

    final skillOut = <String>[];
    final seenSkill = <String>{};
    for (final raw in data.skills) {
      final s = raw.trim();
      if (!plausibleSkill(s)) continue;
      final k = s.toLowerCase();
      if (seenSkill.contains(k)) continue;
      seenSkill.add(k);
      skillOut.add(s);
    }
    data.skills = skillOut;

    _sanitizeStructuredCategoryLists(data);

    // Education: avoid dumping whole paragraphs into degree; drop mis-tagged rows.
    final eduKeys = <String>{};
    data.educationList = data.educationList
        .map(_normalizeEducationRow)
        .map((ed) {
          var deg = ed.degree.trim();
          if (deg.length > 120) deg = '${deg.substring(0, 117)}…';
          return Education(
            degree: deg,
            institution: ed.institution.trim(),
            year: ed.year.trim(),
          );
        })
        .where(_isPlausibleEducationRow)
        .where((ed) {
          final k =
              '${ed.degree.trim().toLowerCase()}|${ed.institution.trim().toLowerCase()}|${ed.year.trim()}';
          if (eduKeys.contains(k)) return false;
          eduKeys.add(k);
          return true;
        })
        .toList();

    _stripCategoryUiNoise(data);

    final ach = data.categories['Achievements'];
    if (ach != null && ach.isNotEmpty) {
      data.categories['Achievements'] =
          CategoryEntryDisplay.coalesceLooseAchievementImports(
            List<String>.from(ach),
          );
    }
  }

  static void _sanitizeStructuredCategoryLists(ResumeData data) {
    final langs = (data.categories['Languages'] ?? const <String>[])
        .map(CategoryEntryDisplay.normalizeLanguageStorage)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    data.categories['Languages'] = langs;

    final rawHobbies = (data.categories['Hobbies'] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final hobbies = CategoryEntryDisplay.sanitizeHobbyItems(rawHobbies);

    // If the incoming list is huge but almost nothing survives hobby-like filtering,
    // treat it as a mis-imported keyword dump and clear it.
    if (rawHobbies.length >= 12 && hobbies.isEmpty) {
      data.categories['Hobbies'] = [];
    } else {
      data.categories['Hobbies'] = hobbies;
    }
  }

  static List<String> _coerceStringList(dynamic v) {
    if (v is List) {
      return v
          .map((x) => '$x'.trim())
          .where((s) => s.isNotEmpty)
          .expand((s) => _splitBulletLines(s))
          .toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      final lines = _splitBulletLines(v.trim());
      return lines.isNotEmpty ? lines : [v.trim()];
    }
    return const [];
  }

  static List<String> _splitBulletLines(String raw) {
    var parts = raw
        .split(RegExp(r'\r?\n+'))
        .map((s) => s.trim())
        .map((s) => s.replaceFirst(RegExp(r'^[•\-\*·]\s*'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length > 1) return parts;
    if (parts.isEmpty) return const [];
    final one = parts.single;
    if (one.length > 320 && one.contains('•')) {
      parts = one
          .split('•')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return parts.isNotEmpty ? parts : [raw.trim()];
  }
}
