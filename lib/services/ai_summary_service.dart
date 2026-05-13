import '../models/resume_model.dart';

class AISummaryService {
  /// Builds a multi-paragraph professional summary from resume fields (local heuristic, no API).
  static String generateSummary({
    required String name,
    required List<String> skills,
    required List<Experience> experiences,
    String targetJobDescription = '',
  }) {
    final cleanName =
        name.trim().isEmpty ? 'This professional' : name.trim();
    final skillList = skills
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final primaryRole = experiences.isNotEmpty &&
            experiences.first.role.trim().isNotEmpty
        ? experiences.first.role.trim()
        : 'results-driven professional';

    final skillsText = skillList.isEmpty
        ? 'a broad mix of tools and practices relevant to modern product delivery'
        : _formatSkillList(skillList);

    final buffer = StringBuffer();

    buffer.writeln(
      '$cleanName is an accomplished $primaryRole with demonstrated strength in $skillsText. '
      'They combine analytical thinking with clear communication and a practical focus on outcomes, '
      'whether shipping features, improving reliability, or collaborating across disciplines.',
    );
    buffer.writeln();

    final expNarrative = _experienceNarrative(experiences);
    if (expNarrative.isNotEmpty) {
      buffer.writeln(expNarrative);
      buffer.writeln();
    } else {
      buffer.writeln(
        'Their background spans delivery ownership, stakeholder alignment, and continuous improvement—'
        'with an emphasis on quality, maintainability, and measurable impact.',
      );
      buffer.writeln();
    }

    final target = targetJobDescription.trim();
    if (target.isNotEmpty) {
      final excerpt = target.length > 8000
          ? '${target.substring(0, 8000).trim()}…'
          : target;
      buffer.writeln(
        'Career direction is oriented toward roles that match the following focus and expectations: '
        '$excerpt',
      );
      buffer.writeln();
    }

    buffer.writeln(
      'They are motivated by challenging problems, accountable execution, and learning environments '
      'where feedback and iteration drive both personal growth and team success.',
    );

    return buffer.toString().trim();
  }

  static String _formatSkillList(List<String> skillList) {
    if (skillList.length <= 6) {
      return _joinOxford(skillList);
    }
    final head = skillList.take(18).toList();
    final rest = skillList.length - head.length;
    return '${_joinOxford(head)}, plus $rest additional competencies';
  }

  static String _joinOxford(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }

  static String _experienceNarrative(List<Experience> experiences) {
    final usable = experiences
        .where(
          (e) =>
              e.role.trim().isNotEmpty ||
              e.company.trim().isNotEmpty ||
              e.duration.trim().isNotEmpty ||
              e.description.any((b) => b.trim().isNotEmpty),
        )
        .toList();
    if (usable.isEmpty) return '';

    final sentences = <String>[];
    final maxRoles = usable.length.clamp(1, 12);

    for (var i = 0; i < maxRoles; i++) {
      final e = usable[i];
      final role = e.role.trim();
      final company = e.company.trim();
      final duration = e.duration.trim();

      final roleCompany = role.isNotEmpty && company.isNotEmpty
          ? '$role at $company'
          : (role.isNotEmpty
              ? role
              : (company.isNotEmpty ? company : ''));
      var clause = roleCompany.trim();
      if (duration.isNotEmpty) {
        clause = clause.isEmpty ? duration : '$clause ($duration)';
      }

      final bullets = e.description
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .take(18)
          .map(_stripTrailingPeriod)
          .toList();

      if (clause.isEmpty && bullets.isEmpty) continue;

      if (clause.isNotEmpty && bullets.isNotEmpty) {
        final lead = role.isNotEmpty
            ? 'As $clause'
            : 'In their work with $clause';
        sentences.add(
          '$lead, they contributed to outcomes such as ${_joinBulletPhrases(bullets)}.',
        );
      } else if (clause.isNotEmpty) {
        sentences.add('Experience includes $clause.');
      } else if (bullets.isNotEmpty) {
        sentences.add(
          'Highlights include ${_joinBulletPhrases(bullets)}.',
        );
      }
    }

    if (sentences.isEmpty) return '';
    if (sentences.length == 1) return sentences.first;

    final lead = sentences.take(5).join(' ');
    if (sentences.length <= 5) return lead;
    return '$lead Additional roles further deepen ownership across the full delivery lifecycle.';
  }

  static String _stripTrailingPeriod(String s) {
    final t = s.trim();
    if (t.endsWith('.')) return t.substring(0, t.length - 1).trim();
    return t;
  }

  static String _joinBulletPhrases(List<String> bullets) {
    if (bullets.length == 1) return bullets.first;
    if (bullets.length == 2) return '${bullets[0]} and ${bullets[1]}';
    return '${bullets.sublist(0, bullets.length - 1).join('; ')}; and ${bullets.last}';
  }
}
