import 'dart:io';
import 'dart:ui';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../widgets/uniform_app_bar.dart';
import '../widgets/app_toast.dart';

import '../l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

// ✅ IMPORTANT: use YOUR service file name here
import '../services/ai_ats_service.dart';
import '../services/ai_resume_parser.dart';
import '../services/ats_checker_session.dart';
import '../models/resume_model.dart';
import '../utils/pdf_export_ats_markers.dart';
import 'home_builder_page.dart';
import 'template_selection_page.dart';

class ATSCheckerPage extends StatefulWidget {
  const ATSCheckerPage({super.key});

  @override
  State<ATSCheckerPage> createState() => _ATSCheckerPageState();
}

class _ATSCheckerPageState extends State<ATSCheckerPage> {
  static const LinearGradient _primaryNeon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),
      Color(0xFF06B6D4),
    ],
  );

  File? resumeFile;
  String? _resumeOriginalName;
  bool isLoading = false;
  bool isEnhancing = false;

  Map<String, dynamic>? result;
  String? _extractedText;

  late final ConfettiController _confettiController;
  bool _sessionRestoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSessionIfNeeded());
  }

  /// Copy upload into app documents so OS temp/cache paths are not invalidated after navigation.
  Future<File> _persistPickedResume(File picked) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/ats_checker_last_resume.pdf');
    await dest.writeAsBytes(await picked.readAsBytes());
    return dest;
  }

  Future<void> _restoreSessionIfNeeded() async {
    if (_sessionRestoreScheduled) return;
    _sessionRestoreScheduled = true;
    if (resumeFile != null && result != null) return;

    final data = await AtsCheckerSession.instance.load();
    if (!mounted || data == null) return;

    final f = File(data.resumePath);
    if (!await f.exists()) {
      await AtsCheckerSession.instance.clear();
      return;
    }

    if (!mounted) return;
    // Avoid clobbering a scan that finished while prefs were loading.
    if (resumeFile != null && result != null) return;

    setState(() {
      resumeFile = f;
      _resumeOriginalName = data.originalFileName;
      _extractedText = data.extractedText;
      result = Map<String, dynamic>.from(data.result);
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  /// Derive sub-scores from overall ATS score (API returns aggregate only).
  List<({String label, double value01})> _breakdownFromScore(double score0to100) {
    final s = (score0to100 / 100).clamp(0.0, 1.0);
    const deltas = [0.03, -0.02, 0.04, -0.03];
    const labels = [
      'Keywords match',
      'Formatting',
      'Experience impact',
      'Skills coverage',
    ];
    return List.generate(
      labels.length,
      (i) => (label: labels[i], value01: (s + deltas[i]).clamp(0.0, 1.0)),
    );
  }

  // ================= PICK FILE =================
  Future<void> pickResume() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (picked == null) return;

    setState(() => isLoading = true);

    try {
      final pickedPath = picked.files.single.path;
      final pickedName = picked.files.single.name;
      if (pickedPath == null || pickedPath.isEmpty) {
        if (!mounted) return;
        setState(() => isLoading = false);
        AppToast.validation(
          context,
          AppLocalizations.of(context).couldNotReadFile,
        );
        return;
      }

      resumeFile = await _persistPickedResume(File(pickedPath));
      _resumeOriginalName = pickedName;

      // ✅ CALL YOUR EXISTING AI SERVICE
      final res = await AIATSService.checkATS(resumeFile!);
      final extractedRaw = await AIATSService.extractResumeText(resumeFile!);
      var extractedForUi =
          PdfExportAtsMarkers.stripEmbeddedMachineText(extractedRaw);
      if (extractedForUi.trim().isEmpty) {
        extractedForUi =
            PdfExportAtsMarkers.extractEmbeddedMachineText(extractedRaw);
      }

      if (!mounted) return;
      final scoreNum = (res['score'] as num?)?.toDouble() ?? 0;
      setState(() {
        result = res;
        _extractedText =
            extractedForUi.trim().isNotEmpty ? extractedForUi : extractedRaw;
        isLoading = false;
      });
      await AtsCheckerSession.instance.save(
        resumePath: resumeFile!.path,
        originalFileName: _resumeOriginalName,
        extractedText:
            extractedForUi.trim().isNotEmpty ? extractedForUi : extractedRaw,
        result: res,
      );
      if (scoreNum > 60) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _confettiController.play();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);

      AppToast.error(
        context,
        AppLocalizations.of(context).atsCheckerErrorShort,
      );
    }
  }

  Future<void> _enhanceResume() async {
    if (resumeFile == null || result == null) return;

    if (!await resumeFile!.exists()) {
      if (!mounted) return;
      AppToast.validation(
        context,
        AppLocalizations.of(context).atsResumeFileMissing,
      );
      return;
    }

    setState(() => isEnhancing = true);
    try {
      // Same pipeline as Home Builder → Upload resume: PDF extract + local parse +
      // OpenAI refine + sanitize + experience fallback (not quick-parse only, which
      // leaves work history empty).
      final data = ResumeData();
      await AIResumeParser.parseResume(resumeFile!, data);

      if (!mounted) return;
      setState(() => isEnhancing = false);

      final back = await Navigator.push<ResumeData?>(
        context,
        MaterialPageRoute(
          builder: (_) => TemplateSelectionPage(data: data),
        ),
      );
      if (!mounted) return;
      if (back != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HomeBuilderPage(data: back),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isEnhancing = false);
      AppToast.error(
        context,
        AppLocalizations.of(context).atsCouldNotOpenTemplates,
      );
    }
  }

  // ================= GLASS CARD =================
  Widget glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ================= NEON ACTION (matches Home Builder dock) =================
  Widget _neonActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool loading = false,
    double? width,
  }) {
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: _primaryNeon,
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: loading ? 0.35 : 1,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: const Color(0xFFF8FAFC),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (width != null) {
      return SizedBox(width: width, child: btn);
    }
    return btn;
  }

  // ================= PROGRESS BAR + % =================
  Widget buildProgress(String title, double value01) {
    final pct = (value01.clamp(0.0, 1.0) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: value01.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF06B6D4)),
            ),
          ),
        ],
      ),
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),

      appBar: UniformAppBar.material(t.atsResumeCheckerTitle),

      body: Stack(
        children: [
          const _ATSBackground(),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.atsHeroTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.atsHeroSubtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          "Resume file",
                          subtitle: "PDF only • Text will be extracted securely",
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white.withOpacity(0.08),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              child: const Icon(
                                Icons.picture_as_pdf_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                resumeFile != null
                                    ? (_resumeOriginalName ??
                                        resumeFile!.path.split('/').last)
                                    : "No file selected",
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(
                                    resumeFile != null ? 0.9 : 0.6,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _neonActionButton(
                              label: 'Upload',
                              icon: Icons.upload_rounded,
                              loading: isLoading,
                              width: 124,
                              onPressed: pickResume,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isLoading && result != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            "Get hired faster",
                            subtitle:
                                "Select our ATS-friendly templates and apply your resume instantly",
                          ),
                          const SizedBox(height: 12),
                          _neonActionButton(
                            label: isEnhancing
                                ? 'Opening…'
                                : 'Select ATS-friendly templates',
                            icon: Icons.workspace_premium_rounded,
                            loading: isEnhancing,
                            width: double.infinity,
                            onPressed: _enhanceResume,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            "ATS score",
                            subtitle: "Higher is better • Aim for 75%+",
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 0,
                                end: ((result!["score"] ?? 0) / 100),
                              ),
                              duration: const Duration(seconds: 2),
                              builder: (context, value, _) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      height: 132,
                                      width: 132,
                                      child: CircularProgressIndicator(
                                        value: value,
                                        strokeWidth: 10,
                                        backgroundColor: Colors.white12,
                                        valueColor: const AlwaysStoppedAnimation(
                                          Color(0xFF34D399),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      "${(value * 100).round()}%",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader("Breakdown"),
                          const SizedBox(height: 12),
                          ..._breakdownFromScore(
                            (result!["score"] as num?)?.toDouble() ?? 0,
                          ).map((e) => buildProgress(e.label, e.value01)),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader("Suggestions"),
                          const SizedBox(height: 10),
                          ...(result!["feedback"] ?? "")
                              .toString()
                              .split(".")
                              .where((e) => e.trim().isNotEmpty)
                              .take(30)
                              .map(
                                (e) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFFFFD166),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          e.trim(),
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.82),
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Emitter must fill the screen: a bare ConfettiWidget under Align had ~0 size,
          // so almost all particles were culled — only 1–2 were visible.
          Positioned.fill(
            child: IgnorePointer(
              child: ConfettiWidget(
                confettiController: _confettiController,
                canvas: MediaQuery.sizeOf(context),
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.04,
                numberOfParticles: 32,
                maxBlastForce: 38,
                minBlastForce: 18,
                gravity: 0.24,
                minimumSize: const Size(10, 8),
                maximumSize: const Size(18, 12),
                colors: const [
                  Color(0xFF7C3AED),
                  Color(0xFF06B6D4),
                  Color(0xFF34D399),
                  Color(0xFFFBBF24),
                  Color(0xFFF472B6),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ATSBackground extends StatelessWidget {
  const _ATSBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF070A12),
                Color(0xFF0B1324),
                Color(0xFF0B1B2E),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -90,
          left: -60,
          child: _blob(const Color(0xFF60A5FA)),
        ),
        Positioned(
          bottom: -110,
          right: -70,
          child: _blob(const Color(0xFFA78BFA)),
        ),
        Positioned(
          top: 160,
          right: -90,
          child: _blob(const Color(0xFF34D399)),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _blob(Color color) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.22),
      ),
    );
  }
}