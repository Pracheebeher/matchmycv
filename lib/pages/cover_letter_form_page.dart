import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ai_cover_letter_service.dart';
import '../services/ai_job_tailoring_service.dart';
import 'cover_letter_preview_page.dart';
import '../l10n/app_localizations.dart';
import '../widgets/paste_input_extras.dart';
import '../widgets/app_toast.dart';
import '../widgets/uniform_app_bar.dart';

class CoverLetterFormPage extends StatefulWidget {
  const CoverLetterFormPage({super.key});

  @override
  State<CoverLetterFormPage> createState() => _CoverLetterFormPageState();
}

class _CoverLetterFormPageState extends State<CoverLetterFormPage> {

  final nameController = TextEditingController();
  final company = TextEditingController();
  final position = TextEditingController();
  final skills = TextEditingController();
  final jobDescription = TextEditingController();
  bool _isGenerating = false;

  // 🔹 INPUT FIELD
  Widget inputField(
    TextEditingController c,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    final loc = AppLocalizations.of(context)!;
    return _GlassField(
      controller: c,
      hint: hint,
      icon: icon,
      maxLines: maxLines,
      pasteLabel: loc.pasteFromClipboard,
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    company.dispose();
    position.dispose();
    skills.dispose();
    jobDescription.dispose();
    super.dispose();
  }

  /// Job description stays optional; name, company, role, and skills are required.
  bool _validateCoverLetterForm(AppLocalizations t) {
    if (nameController.text.trim().isEmpty ||
        company.text.trim().isEmpty ||
        position.text.trim().isEmpty ||
        skills.text.trim().isEmpty) {
      AppToast.validation(context, t.coverLetterFormIncompleteMessage);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ FIX OVERFLOW
      backgroundColor: const Color(0xFF070A12),
      appBar: UniformAppBar.material(t.aiCoverLetterTitle),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.75),
            radius: 1.3,
            colors: [
              Color(0xFF1B2A4A),
              Color(0xFF070A12),
            ],
          ),
        ),

        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.coverLetterSubtitle,
                  style: TextStyle(
                    color: Color(0xFFB6C2D6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 18),

                // ✅ SCROLL FIX (NO OVERFLOW)
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.tellUsAboutJob,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.tailoredCoverLetterHint,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          inputField(
                            nameController,
                            t.nameLabel,
                            Icons.person_outline_rounded,
                          ),
                          inputField(company, t.companyName, Icons.business),
                          inputField(position, t.jobPosition, Icons.work),
                          inputField(
                            skills,
                            t.yourSkillsComma,
                            Icons.star,
                            maxLines: 2,
                          ),
                          inputField(
                            jobDescription,
                            'Job description (optional, for AI tailoring)',
                            Icons.article_outlined,
                            maxLines: 6,
                          ),

                          const SizedBox(height: 30),

                          // 🚀 GENERATE BUTTON
                          SizedBox(
                            width: double.infinity,
                            child: _PrimaryGradientButton(
                              icon: Icons.auto_awesome,
                              label: _isGenerating
                                  ? t.generating
                                  : t.generateWithAi,
                              loading: _isGenerating,
                              onPressed: _isGenerating
                                  ? null
                                  : () async {
                                      if (!_validateCoverLetterForm(t)) {
                                        return;
                                      }
                                      setState(() => _isGenerating = true);
                                      try {
                                        String letter;
                                        try {
                                          letter =
                                              await AIJobTailoringService
                                                  .generateCoverLetterTailored(
                                            company: company.text.trim(),
                                            position: position.text.trim(),
                                            skills: skills.text.trim(),
                                            applicantName:
                                                nameController.text.trim(),
                                            jobDescription:
                                                jobDescription.text.trim(),
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          AppToast.error(
                                            context,
                                            AppLocalizations.of(context)
                                                .coverLetterAiFallbackNotice,
                                          );
                                          letter =
                                              AICoverLetterService.generate(
                                            company: company.text.trim(),
                                            position: position.text.trim(),
                                            skills: skills.text.trim(),
                                            applicantName:
                                                nameController.text.trim(),
                                          );
                                        }

                                        if (!mounted) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CoverLetterPreviewPage(
                                              letter: letter,
                                            ),
                                          ),
                                        );
                                      } finally {
                                        if (mounted) {
                                          setState(() => _isGenerating = false);
                                        }
                                      }
                                    },
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String pasteLabel;

  const _GlassField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.maxLines,
    required this.pasteLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType:
            maxLines > 1 ? TextInputType.multiline : TextInputType.text,
        textInputAction:
            maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
        onTapOutside: (_) =>
            FocusManager.instance.primaryFocus?.unfocus(),
        onEditingComplete: maxLines > 1
            ? null
            : () => FocusManager.instance.primaryFocus?.unfocus(),
        contextMenuBuilder: (_, state) => buildPasteContextMenu(
          editableTextState: state,
          controller: controller,
          pasteLabel: pasteLabel,
        ),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.85)),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _PrimaryGradientButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}