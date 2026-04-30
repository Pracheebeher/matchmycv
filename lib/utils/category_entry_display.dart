/// Optional structured fields in [ResumeData.categories] lists use ASCII
/// record separator (same as references / courses in the home builder).
class CategoryEntryDisplay {
  CategoryEntryDisplay._();

  static final String sep = String.fromCharCode(0x1e);

  static const Set<String> languageProficiencyCodes = {
    'native',
    'fluent',
    'professional',
    'intermediate',
    'basic',
  };

  /// "Primary — Secondary" when [raw] contains [sep]; otherwise trimmed [raw].
  static String primarySecondaryLine(String raw) {
    final t = raw.trim();
    final i = t.indexOf(sep);
    if (i < 0) return t;
    final a = t.substring(0, i).trim();
    final b = t.substring(i + 1).trim();
    if (b.isEmpty) return a;
    return '$a — $b';
  }

  /// Achievements: `Title<SEP>Where<SEP>When` (where/when optional). Empty middle
  /// segments are preserved so "title only when" stays addressable after split.
  static String formatAchievementLine(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (!t.contains(sep)) return t;

    final parts = t.split(sep).map((s) => s.trim()).toList();
    if (parts.isEmpty) return '';
    final title = parts[0];
    if (title.isEmpty) {
      return parts.where((s) => s.isNotEmpty).join(' — ');
    }
    final where = parts.length >= 2 ? parts[1] : '';
    final when = parts.length >= 3 ? parts[2] : '';
    final tail = parts.length > 3
        ? parts.sublist(3).where((s) => s.isNotEmpty).join(' ')
        : '';
    final bits = <String>[
      if (where.isNotEmpty) where,
      if (when.isNotEmpty) when,
      if (tail.isNotEmpty) tail,
    ];
    if (bits.isEmpty) return title;
    return '$title — ${bits.join(' — ')}';
  }

  /// Removes duplicate formatted lines and drops **date-only** rows that repeat a
  /// year/date already shown at the end of another line (e.g. comma-split imports
  /// that created `"Award, 2020"` and a separate `"2020"` entry).
  static List<String> sanitizeAchievementDisplayList(List<String> rawItems) {
    bool isSoloDateLike(String s) {
      final t = s.trim();
      if (t.isEmpty || t.length > 28) return false;
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(t)) return true;
      if (RegExp(r'^Q[1-4]\s*,?\s*(19|20)\d{2}$', caseSensitive: false)
          .hasMatch(t)) {
        return true;
      }
      if (RegExp(
        r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(19|20)\d{2}$',
        caseSensitive: false,
      ).hasMatch(t)) {
        return true;
      }
      if (RegExp(r'^\d{1,2}/\d{4}$').hasMatch(t)) return true;
      if (RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(t)) return true;
      if (t.length <= 12 &&
          RegExp(r'^[\d\s./\-–—]+$', caseSensitive: false).hasMatch(t)) {
        return true;
      }
      return false;
    }

    final formatted = rawItems
        .map((s) => formatAchievementLine(s.trim()))
        .where((s) => s.isNotEmpty)
        .toList();

    final seen = <String>{};
    final deduped = <String>[];
    for (final f in formatted) {
      final k = f.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);
      deduped.add(f);
    }

    if (deduped.every((e) => !isSoloDateLike(e))) return deduped;

    String? lastEmDashSegmentLower(String line) {
      final parts = line.split('—');
      if (parts.isEmpty) return null;
      return parts.last.trim().toLowerCase();
    }

    return deduped.where((line) {
      final t = line.trim();
      if (!isSoloDateLike(t)) return true;
      final tl = t.toLowerCase();
      for (final other in deduped) {
        if (identical(other, line)) continue;
        if (isSoloDateLike(other)) continue;
        final ol = other.toLowerCase();
        if (ol == tl) continue;
        if (ol.contains(tl)) return false;
        final last = lastEmDashSegmentLower(other);
        if (last != null && last == tl) return false;
        if (other.contains(',')) {
          final tail = other.split(',').last.trim().toLowerCase();
          if (tail == tl || tail.endsWith(tl)) return false;
        }
      }
      return true;
    }).toList();
  }

  static bool _isLikelyAchievementDateOnly(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 28) return false;
    if (RegExp(r'^(19|20)\d{2}$').hasMatch(t)) return true;
    if (RegExp(r'^Q[1-4]\s*,?\s*(19|20)\d{2}$', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    if (RegExp(
      r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(19|20)\d{2}$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}/\d{4}$').hasMatch(t)) return true;
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{2,4}$').hasMatch(t)) return true;
    return false;
  }

  /// True when [s] looks like a **new** achievement bullet (do not merge into prior).
  static bool looksLikeNewAchievementLine(String s) {
    final t = s.trim();
    if (t.length < 4 || t.length > 72) return false;
    return RegExp(
      r'^(awarded?|received|won|selected|honou?red|named|recipient|'
      r'employee\s+of|scholarship|fellowship|certificate|certified|'
      r'accomplishment|achievement|recognition|award|prize|medal|distinction|'
      r'top\s+\d)',
      caseSensitive: false,
    ).hasMatch(t);
  }

  static bool _shouldCoalesceAchievementContinuation(String prev, String next) {
    if (next.contains(sep)) return false;
    if (looksLikeNewAchievementLine(next)) return false;
    if (_isLikelyAchievementDateOnly(prev)) return false;

    final parts =
        prev.split(sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if (_isLikelyAchievementDateOnly(next)) {
      if (parts.length >= 3 && parts[2].isNotEmpty) return false;
      if (parts.length >= 2 && _isLikelyAchievementDateOnly(parts[1])) {
        return false;
      }
      return true;
    }

    // "Where" continuation: only after a single-segment title (no sep yet).
    if (parts.length != 1) return false;
    if (next.length > 80) return false;
    if (next.split(RegExp(r'\s+')).length > 12) return false;
    return true;
  }

  static String _appendAchievementContinuation(String prev, String next) {
    final t = next.trim();
    final parts = prev.split(sep).map((e) => e.trim()).toList();

    if (_isLikelyAchievementDateOnly(t)) {
      if (parts.length == 1) {
        return '${parts[0]}$sep$sep$t';
      }
      if (parts.length == 2) {
        return '${parts[0]}$sep${parts[1]}$sep$t';
      }
      if (parts.length >= 3) {
        final a = parts[0];
        final b = parts[1];
        return '$a$sep$b$sep$t';
      }
    }

    if (parts.length == 1) {
      return '${parts[0]}$sep$t';
    }
    return '$prev$sep$t';
  }

  /// Merges consecutive loose lines from PDF/ATS import (`title` on one line,
  /// `where` / `when` on the next) into `Title<SEP>Where<SEP>When` storage.
  static List<String> coalesceLooseAchievementImports(List<String> raw) {
    final lines =
        raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.length <= 1) return lines;

    final out = <String>[];
    for (final s in lines) {
      if (out.isEmpty) {
        out.add(s);
        continue;
      }
      if (looksLikeNewAchievementLine(s) || s.contains(sep)) {
        out.add(s);
        continue;
      }
      final prev = out.last;
      if (_shouldCoalesceAchievementContinuation(prev, s)) {
        out[out.length - 1] = _appendAchievementContinuation(prev, s);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// When the second segment is a known proficiency [code], uses [labelForCode].
  /// Otherwise falls back to [primarySecondaryLine].
  static String formatLanguage(
    String raw,
    String Function(String code) labelForCode,
  ) {
    final t = raw.trim();
    final i = t.indexOf(sep);
    if (i < 0) return t;
    final lang = t.substring(0, i).trim();
    final code = t.substring(i + 1).trim();
    if (lang.isEmpty) return t;
    if (code.isEmpty) return lang;
    final key = code.toLowerCase();
    if (languageProficiencyCodes.contains(key)) {
      return '$lang — ${labelForCode(key)}';
    }
    return primarySecondaryLine(raw);
  }

  /// English labels for PDF / layout when [AppLocalizations] is unavailable.
  static String formatLanguageEnglish(String raw) {
    // Normalize first so odd imports like "English U+001E Fluent" or malformed
    // separator variants don't leak raw control characters into the UI.
    final normalized = normalizeLanguageStorage(raw);
    return formatLanguage(normalized, (code) {
      switch (code.toLowerCase()) {
        case 'native':
          return 'Native';
        case 'fluent':
          return 'Fluent';
        case 'professional':
          return 'Professional working proficiency';
        case 'intermediate':
          return 'Intermediate';
        case 'basic':
          return 'Basic';
        default:
          return code;
      }
    });
  }

  /// Normalizes odd model/PDF outputs into the canonical storage format:
  /// `Language<SEP>proficiencyCode` (or just `Language`).
  ///
  /// Handles cases like `English U+001E Fluent` where the separator was emitted as text.
  static String normalizeLanguageStorage(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // Keep the real record-separator as the canonical delimiter, but don't
    // blindly convert ALL control chars into separators (some extractors inject
    // newlines/tabs which would accidentally split and drop proficiency).
    //
    // - Convert the real RS (0x1E) to itself (no-op)
    // - Convert other control chars to spaces, then collapse whitespace.
    s = s.replaceAll(RegExp(r'[\u0000-\u0009\u000B-\u001D\u001F\u007F]'), ' ');

    // Some extractors/renderers surface control chars as printable tokens.
    // We've seen `^XX` and mojibake like `âXX` appear between language and proficiency.
    s = s.replaceAll(RegExp(r'\^XX', caseSensitive: false), sep);
    s = s.replaceAll(RegExp(r'â\s*XX', caseSensitive: false), sep);

    // Common mistake: model prints "U+001E" instead of embedding the real char.
    s = s.replaceAll(RegExp(r'U\+001E', caseSensitive: false), sep);
    s = s.replaceAll(RegExp(r'\bU001E\b', caseSensitive: false), sep);
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp('${RegExp.escape(sep)}+'), sep);
    s = s.replaceAll(RegExp(r'\s*' + RegExp.escape(sep) + r'\s*'), sep);

    String normalizeProfToken(String token) {
      final t = token.trim();
      if (t.isEmpty) return '';
      final lower = t.toLowerCase();

      // If the model still left a textual mention behind, drop it.
      if (lower.contains('u+001e')) return '';
      if (lower == 'u001e') return '';

      if (lower == 'fluent' || lower.startsWith('fluent')) return 'fluent';
      if (lower == 'native' || lower.startsWith('native')) return 'native';
      if (lower.contains('professional')) return 'professional';
      if (lower == 'intermediate' || lower.startsWith('intermediate')) {
        return 'intermediate';
      }
      if (lower == 'basic' || lower.startsWith('basic')) return 'basic';

      if (languageProficiencyCodes.contains(lower)) return lower;

      // Unknown / overly long — drop proficiency side.
      if (t.length > 24) return '';
      return '';
    }

    final i = s.indexOf(sep);
    if (i < 0) {
      // If the separator is missing but the line ends with a known proficiency,
      // rehydrate it into the canonical `Language<SEP>code` form.
      final m2 = RegExp(
        r'^(.*?)\s*(?:[-–—|/,:]|\s{1,3})\s*'
        r'(native|fluent|professional|intermediate|basic)\s*$',
        caseSensitive: false,
      ).firstMatch(s);
      if (m2 != null) {
        final lang = m2.group(1)!.trim();
        final prof = normalizeProfToken(m2.group(2)!);
        if (lang.isEmpty) return '';
        if (prof.isEmpty) return lang;
        return '$lang$sep$prof';
      }
      final m = RegExp(r'^(.*?)\s*[-–—]\s*(.+)$').firstMatch(s);
      if (m != null) {
        final lang = m.group(1)!.trim();
        final prof = normalizeProfToken(m.group(2)!);
        if (lang.isEmpty) return '';
        if (prof.isEmpty) return lang;
        return '$lang$sep$prof';
      }
      return s;
    }

    final lang = s.substring(0, i).trim();
    final prof = normalizeProfToken(s.substring(i + 1));
    if (lang.isEmpty) return '';
    if (prof.isEmpty) return lang;
    return '$lang$sep$prof';
  }

  static bool _looksLikeTechKeywordToken(String s) {
    final t = s.toLowerCase().trim();
    if (t.isEmpty) return false;
    const bad = <String>{
      'python',
      'java',
      'javascript',
      'typescript',
      'sql',
      'aws',
      'azure',
      'gcp',
      'kubernetes',
      'docker',
      'react',
      'flutter',
      'dart',
      'node',
      'nodejs',
      'node.js',
      'express',
      'nestjs',
      'django',
      'spring',
      'kafka',
      'redis',
      'mongodb',
      'postgres',
      'postgresql',
      'mysql',
      'git',
      'github',
      'gitlab',
      'jira',
      'confluence',
      'ci/cd',
      'cicd',
      'agile',
      'scrum',
      'excel',
      'tableau',
      'power bi',
      'machine learning',
      'deep learning',
      'nlp',
      'llm',
      'data science',
      'analytics',
      'angular',
      'vue',
      'svelte',
      'nextjs',
      'next.js',
      'graphql',
      'grpc',
      'terraform',
      'ansible',
      'jenkins',
      'circleci',
      'githubactions',
      'snowflake',
      'databricks',
      'spark',
      'hadoop',
      'airflow',
      'dbt',
      'pandas',
      'numpy',
      'pytorch',
      'tensorflow',
      'sklearn',
      'scikit-learn',
      'opencv',
    };
    if (bad.contains(t)) return true;
    if (t.contains('http://') || t.contains('https://')) return true;
    if (RegExp(r'\b(api|sdk|saas|paas|iaas)\b').hasMatch(t)) return true;
    if (RegExp(r'\b(ci/cd|cicd|devops|microservices|kubernetes|k8s)\b').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'\b(v\d+\.\d+)\b').hasMatch(t)) return true; // e.g. Angular 17.2
    return false;
  }

  static bool _looksLikeLikelyHobbyToken(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.length > 40) return false;
    if (t.contains('@')) return false;
    if (RegExp(r'https?://', caseSensitive: false).hasMatch(t)) return false;
    if (RegExp(r'\d').hasMatch(t)) return false;
    if (RegExp(r'[/_]').hasMatch(t)) return false;
    if (RegExp(r'[.:;]').hasMatch(t)) return false;
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words == 0 || words > 4) return false;
    if (_looksLikeTechKeywordToken(t)) return false;
    // All-caps acronyms are usually tech/business, not hobbies.
    if (t.length >= 3 && t == t.toUpperCase() && RegExp(r'^[A-Z0-9+#.-]+$').hasMatch(t)) {
      return false;
    }
    return true;
  }

  static bool _looksLikeCommaSeparatedKeywordDumpLine(String s) {
    if (!s.contains(',')) return false;
    final parts = s
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.length < 4) return false;
    var tech = 0;
    for (final p in parts) {
      if (_looksLikeTechKeywordToken(p)) tech++;
    }
    return tech >= (parts.length * 0.55).ceil();
  }

  static bool _looksLikeDumpedCategoryLine(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.length > 140) return true;
    final commas = ','.allMatches(t).length;
    final pipes = '|'.allMatches(t).length;
    if (commas >= 6 || pipes >= 4) return true;
    if (RegExp(
      r'\b(keywords?|tech stack|frameworks?|tools?)\b',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    return false;
  }

  /// Splits obvious "keyword blob" hobby lines and filters tech keywords.
  static List<String> sanitizeHobbyItems(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};

    void tryAdd(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      if (t.length > 64) return;
      if (t.split(RegExp(r'\s+')).length > 6) return;
      if (_looksLikeDumpedCategoryLine(t)) return;
      if (_looksLikeCommaSeparatedKeywordDumpLine(t)) return;
      if (_looksLikeTechKeywordToken(t)) return;
      if (!_looksLikeLikelyHobbyToken(t)) return;
      final k = t.toLowerCase();
      if (seen.contains(k)) return;
      seen.add(k);
      out.add(t);
    }

    for (final item in raw) {
      final s0 = item.trim();
      if (s0.isEmpty) continue;

      // Split common "dump" separators if the line is long / list-like.
      if (s0.length >= 48 && RegExp(r'[,;|/]').hasMatch(s0)) {
        final parts = s0
            .split(RegExp(r'[,;|/]'))
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .toList();
        if (parts.length >= 4) {
          var good = 0;
          for (final p in parts) {
            if (_looksLikeLikelyHobbyToken(p)) good++;
          }
          // If this looks like a keyword blob, don't import token-by-token.
          if (good < (parts.length * 0.35).ceil()) {
            continue;
          }
          for (final p in parts) {
            tryAdd(p);
          }
          continue;
        }
      }

      tryAdd(s0);
    }

    // If we still ended up with a long "almost-but-not-quite hobbies" list, it's
    // usually a mis-tagged keyword pile — drop it entirely.
    if (out.length > 6) {
      var good = 0;
      for (final h in out) {
        if (_looksLikeLikelyHobbyToken(h)) good++;
      }
      if (good / out.length < 0.6) {
        return const [];
      }
    }

    // Hard cap: hobbies should be a small list in UI + templates.
    if (out.length > 8) {
      return out.take(8).toList();
    }
    return out;
  }
}
