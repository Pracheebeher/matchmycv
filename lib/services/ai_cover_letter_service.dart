class AICoverLetterService {
  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// e.g. `April 20, 2026` — used by the offline template and AI cover-letter prompts.
  static String formattedLetterDate([DateTime? when]) {
    final d = when ?? DateTime.now();
    return '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Builds a tailored cover letter. [position] strongly steers tone and examples.
  static String generate({
    required String company,
    required String position,
    required String skills,
    String applicantName = '',
  }) {
    final c = company.trim().isEmpty ? 'your company' : company.trim();
    final p = position.trim().isEmpty ? 'this role' : position.trim();
    final rawSkills = skills
        .split(RegExp(r'[,;\n•|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final topSkills = rawSkills.take(6).toList();

    final skillLine = topSkills.isEmpty ? '' : topSkills.join(', ');
    final skillsClause = skillLine.isEmpty
        ? ''
        : ' My strengths include $skillLine, and I’m eager to apply them in this context.';

    final dateLine = formattedLetterDate();
    final signOff = applicantName.trim();

    final tone = _toneForPosition(p);

    return [
      dateLine,
      '',
      'Subject: Application for $p',
      '',
      'Dear Hiring Manager,',
      '',
      'I am writing to apply for the $p role at $c. ${tone.opening}$skillsClause',
      '',
      tone.body,
      '',
      'I am motivated by the impact $c can create in this space, and I would welcome the opportunity to discuss how my experience aligns with your needs for the $p position.',
      '',
      'Thank you for your time and consideration.',
      '',
      'Sincerely,',
      if (signOff.isNotEmpty) signOff,
    ].join('\n');
  }
}

class _LetterTone {
  final String opening;
  final String body;

  const _LetterTone({required this.opening, required this.body});
}

_LetterTone _toneForPosition(String position) {
  final q = position.toLowerCase();

  bool has(RegExp re) => re.hasMatch(q);

  if (has(RegExp(
      r'software|engineer|developer|devops|sre|programmer|backend|front[- ]?end|full[- ]?stack|mobile|ios|android|web\s*dev|tech\s*lead|architect'))) {
    return _LetterTone(
      opening:
          'I enjoy turning unclear requirements into reliable software, partnering closely with stakeholders while keeping quality, performance, and maintainability in mind.',
      body:
          'In recent work, I shipped features end-to-end—from discovery and design alignment through implementation, testing, and release. I’m comfortable owning outcomes, reviewing code thoughtfully, and collaborating across disciplines to deliver stable releases on tight timelines.',
    );
  }

  if (has(RegExp(
      r'data\s*scientist|data\s*analyst|machine\s*learning|ml\b|analytics|bi\b|business\s*intelligence'))) {
    return _LetterTone(
      opening:
          'I am passionate about using data to drive decisions—framing the right questions, validating assumptions, and communicating findings clearly to stakeholders.',
      body:
          'Recently, I focused on building trustworthy analyses and dashboards, improving measurement where it mattered, and partnering with teams to translate insights into action. I’m comfortable working across messy datasets while staying rigorous about methodology and reproducibility.',
    );
  }

  if (has(RegExp(
      r'\bpm\b|product\s*manager|product\s*owner|program\s*manager|project\s*manager'))) {
    return _LetterTone(
      opening:
          'I thrive at the intersection of users, business goals, and delivery—prioritizing outcomes, reducing ambiguity, and helping teams ship the right work at the right time.',
      body:
          'I’ve led discovery conversations, shaped roadmaps, and partnered with engineering and design to break initiatives into clear milestones. I’m comfortable saying “no” with evidence, aligning stakeholders, and keeping execution disciplined without slowing momentum.',
    );
  }

  if (has(RegExp(
      r'designer|ux|ui|graphic|creative|figma|brand|visual|product\s*design'))) {
    return _LetterTone(
      opening:
          'I care deeply about clarity, craft, and user-centered design—balancing aesthetics with usability and aligning creative direction with business goals.',
      body:
          'My recent work involved iterating quickly from sketches to polished deliverables, collaborating with product and engineering, and using feedback loops to improve usability. I’m comfortable presenting rationale clearly and refining details until the experience feels intentional.',
    );
  }

  if (has(RegExp(
      r'sales|business\s*development|\bbd\b|account\s*executive|account\s*manager|revenue|growth'))) {
    return _LetterTone(
      opening:
          'I enjoy building trust quickly, uncovering real needs, and moving conversations toward clear next steps that create value for both the customer and the business.',
      body:
          'In prior roles, I focused on pipeline discipline—qualifying opportunities, tailoring messaging, and following up with consistency. I’m comfortable handling objections, coordinating with internal teams, and keeping momentum through the full sales cycle.',
    );
  }

  if (has(RegExp(
      r'marketing|growth|seo|sem|content|social|campaign|brand\s*marketing|performance'))) {
    return _LetterTone(
      opening:
          'I love building narratives that resonate—testing messaging, learning from performance signals, and iterating campaigns until they convert.',
      body:
          'Recently, I partnered cross-functionally to launch initiatives, tighten targeting, and improve reporting so decisions were grounded in outcomes. I’m comfortable owning experiments, writing crisp copy, and coordinating launches end-to-end.',
    );
  }

  if (has(RegExp(
      r'finance|accounting|controller|audit|tax|fp&a|financial|bookkeeping'))) {
    return _LetterTone(
      opening:
          'I bring a detail-oriented approach to financial work—balancing accuracy, controls, and clear communication so stakeholders can act with confidence.',
      body:
          'My experience includes reconciliations, reporting, and process improvements that reduced errors and saved time. I’m comfortable partnering with operations and leadership to explain variances, support planning, and keep documentation audit-ready.',
    );
  }

  if (has(RegExp(
      r'hr\b|human\s*resources|recruiter|talent|people\s*ops|people\s*operations'))) {
    return _LetterTone(
      opening:
          'I am motivated by helping teams hire thoughtfully, onboard smoothly, and build inclusive environments where people can do their best work.',
      body:
          'I’ve supported stakeholders through structured processes—screening thoughtfully, coordinating interviews, and improving candidate experience. I’m comfortable balancing empathy with consistency, maintaining confidentiality, and partnering with managers on practical solutions.',
    );
  }

  if (has(RegExp(
      r'customer\s*success|customer\s*support|help\s*desk|service\s*desk|call\s*center|client\s*services'))) {
    return _LetterTone(
      opening:
          'I take pride in resolving issues quickly, communicating with empathy, and turning frustrated moments into loyal relationships.',
      body:
          'I’ve handled high-volume tickets while maintaining quality, documenting learnings, and escalating when needed. I’m comfortable learning new products fast, collaborating with product teams on recurring issues, and representing the customer voice clearly.',
    );
  }

  if (has(RegExp(
      r'operations|supply\s*chain|logistics|procurement|warehouse|inventory'))) {
    return _LetterTone(
      opening:
          'I enjoy improving operational reliability—reducing waste, tightening processes, and making execution predictable at scale.',
      body:
          'My recent work involved coordinating across teams, tracking KPIs, and implementing practical improvements that reduced delays and cost. I’m comfortable working under pressure, communicating status clearly, and solving problems with a bias toward action.',
    );
  }

  if (has(RegExp(
      r'teacher|educator|professor|lecturer|tutor|academic|school|classroom'))) {
    return _LetterTone(
      opening:
          'I am passionate about helping learners build confidence, clarity, and skills through structured instruction and supportive feedback.',
      body:
          'I’ve prepared lessons, adapted materials for different levels, and used assessments to guide improvement. I’m comfortable collaborating with colleagues, communicating with families/stakeholders, and maintaining a positive, organized classroom environment.',
    );
  }

  if (has(RegExp(
      r'nurse|clinical|healthcare|medical|patient|hospital|pharmacy|care\s*assistant'))) {
    return _LetterTone(
      opening:
          'I am committed to safe, compassionate care—following protocols, communicating clearly, and staying attentive to patient needs.',
      body:
          'My experience includes working in fast-paced environments where accuracy and teamwork matter. I’m comfortable coordinating with multidisciplinary teams, documenting thoroughly, and maintaining professionalism under pressure.',
    );
  }

  if (has(RegExp(r'legal|paralegal|compliance|counsel|attorney'))) {
    return _LetterTone(
      opening:
          'I bring strong attention to detail, discretion, and structured thinking—supporting teams with clear documentation and risk-aware judgment.',
      body:
          'I’ve supported matter coordination, research, and process improvements that reduced ambiguity and improved turnaround. I’m comfortable managing deadlines, communicating precisely, and partnering with stakeholders on sensitive topics.',
    );
  }

  // Default: still explicitly anchored to the role title the user entered.
  return _LetterTone(
    opening:
        'I am excited about the opportunity to contribute in the $position capacity, combining strong execution with clear communication and a collaborative mindset.',
    body:
        'Across recent roles, I focused on delivering dependable outcomes, learning quickly, and partnering with stakeholders to clarify priorities. I’m comfortable taking ownership, improving processes where it helps the team move faster, and adapting as needs evolve.',
  );
}
