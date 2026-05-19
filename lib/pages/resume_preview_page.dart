import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/resume_model.dart';
import '../services/ai_resume_parser.dart';
import '../services/resume_layout_engine.dart';
import '../utils/resume_theme.dart';
import '../utils/resume_typography.dart';
import '../utils/experience_display.dart';
import '../utils/resume_preview_layout_metrics.dart';
import '../utils/template1_layout_metrics.dart';
import '../utils/category_entry_display.dart';
import '../l10n/app_localizations.dart';
import '../widgets/paste_input_extras.dart';
import '../widgets/uniform_app_bar.dart';
import 'home_builder_page.dart';
import '../services/ai_job_tailoring_service.dart';
import '../services/pdf_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/resume_pdf_post_export_sheet.dart';

/// Matches [TemplateSelectionPage] template id `"2"` (`thumb` field).
const String _template2SelectionThumbAsset = 'assets/templates/template2.png';

/// Fixed banner slot on template-1 page 1 (must match pagination reserve).
const double _kTemplate1BannerHeight = 108.0;

/// Tracks work-experience progress across template-1 pages (jobs flow continuously).
class _T1ExperiencePageState {
  int jobIndex = 0;
  int bulletIndex = 0;
  bool showWorkHeading = true;
}

class _T1ExperienceFillResult {
  final List<Experience> items;
  final int endJobIndex;
  final int endBulletIndex;
  final bool showWorkHeadingOnPage;
  final bool showWorkHeadingAfter;
  final bool singleItemShowJobHeader;
  final bool allExperienceComplete;
  final double measuredHeight;

  const _T1ExperienceFillResult({
    required this.items,
    required this.endJobIndex,
    required this.endBulletIndex,
    required this.showWorkHeadingOnPage,
    required this.showWorkHeadingAfter,
    required this.singleItemShowJobHeader,
    required this.allExperienceComplete,
    required this.measuredHeight,
  });
}

/// Splits comma/semicolon-separated skill dumps for readable chips in template 1.
List<String> _splitSkillListValue(String raw) {
  return raw
      .split(RegExp(r'[,;•\n|]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

String _firstCategoryLine(ResumeData data, String key) {
  for (final s in data.categories[key] ?? const <String>[]) {
    final t = s.trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

/// Single contact line for templates: prefers [City] + [Country], else legacy [Location].
String _resumeGeoDisplayLine(ResumeData data) {
  final city = _firstCategoryLine(data, 'City');
  final country = _firstCategoryLine(data, 'Country');
  if (city.isNotEmpty || country.isNotEmpty) {
    if (city.isEmpty) return country;
    if (country.isEmpty) return city;
    return '$city, $country';
  }
  return _firstCategoryLine(data, 'Location');
}

String _experienceWhenDisplay(Experience exp) {
  return AIResumeParser.formatExperienceDurationDisplay(
    exp.duration.trim().isNotEmpty
        ? exp.duration
        : (AIResumeParser.experiencePeriodFromFreeText(
              '${exp.role} ${exp.company}',
            ) ??
            ''),
  );
}

List<String> _experienceBulletsDisplay(Experience exp) {
  final when = _experienceWhenDisplay(exp);
  return AIResumeParser.stripDuplicateDurationBullets(
    exp.description.map((b) => b.trim()).where((b) => b.isNotEmpty).toList(),
    when.isNotEmpty ? when : exp.duration,
  );
}

String _experienceCompanyDisplay(Experience exp) {
  final when = _experienceWhenDisplay(exp);
  return AIResumeParser.companyForExperienceDisplay(
    exp.company,
    when.isNotEmpty ? when : exp.duration,
  );
}

class ResumePreviewPage extends StatefulWidget {
  final ResumeData data;
  final String templateId;

  const ResumePreviewPage({
    super.key,
    required this.data,
    required this.templateId,
  });

  @override
  State<ResumePreviewPage> createState() => _ResumePreviewPageState();
}

class _ResumePreviewPageState extends State<ResumePreviewPage> {
  static const List<Color> _t2HeaderPresets = [
    Color(0xFF0F1F33),
    Color(0xFF111827),
    Color(0xFF1B2A4A),
    Color(0xFF0B2230),
    Color(0xFF1F2937),
  ];

  static const List<Color> _t2GoldPresets = [
    Color(0xFFC5B358),
    Color(0xFFB8A978),
    Color(0xFFD6C56A),
    Color(0xFFE7D08A),
    Color(0xFFF1E3B4),
  ];

  late Color _t2HeaderColor;
  late Color _t2GoldColor;
  late Color _accentColor;

  String _bodyFontFamily = 'Roboto';
  String _nameFontFamily = 'Georgia';
  /// True while a resume PDF export is running (guards double-tap). Does not
  /// drive the download tile spinner — progress is shown only in the export sheet.
  bool _resumePdfExportInProgress = false;
  bool _tailoringAi = false;
  final GlobalKey _downloadExportTileKey = GlobalKey();
  List<GlobalKey> _exportPageBoundaryKeys = const [];
  final ScrollController _previewScrollController = ScrollController();

  void _mergeSkillsFromCsv(String csv) {
    final parts = csv
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final p in parts) {
      final exists = widget.data.skills.any(
        (e) => e.toLowerCase() == p.toLowerCase(),
      );
      if (!exists) {
        widget.data.skills.add(p);
      }
    }
  }

  Future<String?> _promptJobDescriptionIfMissing() async {
    final existing = widget.data.targetJobDescription.trim();
    if (existing.isNotEmpty) return existing;

    final c = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0B1220),
            title: const Text(
              'Job description',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                controller: c,
                maxLines: null,
                minLines: 5,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                contextMenuBuilder: (_, state) => buildPasteContextMenu(
                  editableTextState: state,
                  controller: c,
                  pasteLabel: AppLocalizations.of(ctx).pasteFromClipboard,
                ),
                style: const TextStyle(color: Colors.white, height: 1.35),
                decoration: InputDecoration(
                  hintText: 'Paste the job posting (used for AI tailoring)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white.withOpacity(0.75)),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
      if (result != null && result.trim().isNotEmpty) {
        widget.data.targetJobDescription = result.trim();
      }
      return result;
    } finally {
      c.dispose();
    }
  }

  Future<void> _openResumeJobTailoring() async {
    final jd = await _promptJobDescriptionIfMissing();
    if (!mounted) return;
    if (jd == null) return;
    if (jd.trim().isEmpty) {
      AppToast.validation(
        context,
        AppLocalizations.of(context).jobDescriptionRequiredTailor,
      );
      return;
    }

    setState(() => _tailoringAi = true);
    try {
      final r = await AIJobTailoringService.tailorResumeToJob(
        data: widget.data,
        jobDescription: jd.trim(),
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0B1220),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.72,
                minChildSize: 0.45,
                maxChildSize: 0.95,
                builder: (_, scroll) {
                  return ListView(
                    controller: scroll,
                    children: [
                      const Text(
                        'AI tailoring',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r.matchNotes.isEmpty ? '—' : r.matchNotes,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          height: 1.35,
                          fontSize: ResumeTypography.heading,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Suggested summary',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: ResumeTypography.heading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.suggestedSummary.isEmpty ? '—' : r.suggestedSummary,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          height: 1.35,
                          fontSize: ResumeTypography.heading,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: r.suggestedSummary.trim().isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                final s = r.suggestedSummary.trim();
                                setState(() {
                                  final cur = widget.data.summary.trim();
                                  widget.data.summary = cur.isEmpty
                                      ? s
                                      : '$cur\n\n$s';
                                });
                                AppToast.success(
                                  context,
                                  AppLocalizations.of(context)
                                      .summarySuggestionAdded,
                                );
                              },
                        child: const Text('Add suggested summary'),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Skills to consider adding',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: ResumeTypography.heading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.suggestedSkillsAddCsv.isEmpty
                            ? '—'
                            : r.suggestedSkillsAddCsv,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          height: 1.35,
                          fontSize: ResumeTypography.heading,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: r.suggestedSkillsAddCsv.trim().isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _mergeSkillsFromCsv(r.suggestedSkillsAddCsv);
                                });
                                AppToast.success(
                                  context,
                                  AppLocalizations.of(context).skillsMergedShort,
                                );
                              },
                        child: const Text('Add suggested skills'),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        AppLocalizations.of(context).tailoringCouldNotComplete,
      );
    } finally {
      if (mounted) setState(() => _tailoringAi = false);
    }
  }

  @override
  void initState() {
    super.initState();
    AIResumeParser.sanitizeExtractedData(widget.data);
    _t2HeaderColor = _t2HeaderPresets.first;
    _t2GoldColor = _t2GoldPresets.first;
    // For Template 1, default to the first curated swatch (user requested "second color first").
    _accentColor = widget.templateId == '1'
        ? _accentSwatches().first
        : _TemplateStyles.forId(widget.templateId).accent;
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  List<Color> _accentSwatches() {
    final base = _TemplateStyles.forId(widget.templateId).accent;

    // Template 1: curated matte dark accents (blue + green).
    if (widget.templateId == '1') {
      return [
        // Matte blues (darker / less saturated)
        const Color(0xFF0F2A5F), // deep navy
        const Color(0xFF0B1F3A), // midnight navy
        const Color(0xFF1E3A8A), // indigo-900
        const Color(0xFF1E40AF), // indigo-800
        const Color(0xFF1D4ED8), // indigo-700

        // Matte greens / teals (dark, shuttle-ish)
        const Color(0xFF064E3B), // emerald-900
        const Color(0xFF065F46), // emerald-800
        const Color(0xFF0F766E), // teal-700
        const Color(0xFF115E59), // teal-800
        const Color(0xFF134E4A), // teal-900
      ];
    }

    // Other templates: saturated accents on white paper.
    const vivid = <Color>[
      Color(0xFF2563EB),
      Color(0xFF0891B2),
      Color(0xFF7C3AED),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
      Color(0xFF16A34A),
      Color(0xFFCA8A04),
      Color(0xFFE11D48),
    ];
    return <Color>{base, ...vivid}.toList();
  }

  static const double _previewSwatchSize = 22;

  Widget _themePanel(BuildContext context) {
    const labelStyle = TextStyle(
      color: Colors.white70,
      fontSize: ResumeTypography.body,
      fontWeight: FontWeight.w700,
    );
    const ddDecoration = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      labelText: '',
      floatingLabelBehavior: FloatingLabelBehavior.never,
    );

    Widget swatchCircle(Color c, bool selected) {
      return Container(
        width: _previewSwatchSize,
        height: _previewSwatchSize,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.templateId == '2')
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Header', style: labelStyle),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in _t2HeaderPresets)
                                  GestureDetector(
                                    onTap: () => setState(() => _t2HeaderColor = c),
                                    child: swatchCircle(c, c == _t2HeaderColor),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Gold', style: labelStyle),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in _t2GoldPresets)
                                  GestureDetector(
                                    onTap: () => setState(() => _t2GoldColor = c),
                                    child: swatchCircle(c, c == _t2GoldColor),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  const Text('Accent', style: labelStyle),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in _accentSwatches())
                        GestureDetector(
                          onTap: () => setState(() => _accentColor = c),
                          child: swatchCircle(c, c == _accentColor),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        isDense: true,
                        value: _nameFontFamily,
                        dropdownColor: const Color(0xFF0B1220),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: ResumeTypography.body,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: ddDecoration.copyWith(
                          labelText: 'Name font',
                          labelStyle: labelStyle,
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Georgia',
                            child: Text('Georgia', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                          DropdownMenuItem(
                            value: 'Times New Roman',
                            child: Text('Times', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                          DropdownMenuItem(
                            value: 'Palatino',
                            child: Text('Palatino', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _nameFontFamily = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        isDense: true,
                        value: _bodyFontFamily,
                        dropdownColor: const Color(0xFF0B1220),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: ResumeTypography.body,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: ddDecoration.copyWith(
                          labelText: 'Body font',
                          labelStyle: labelStyle,
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Roboto',
                            child: Text('Roboto', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                          DropdownMenuItem(
                            value: 'Helvetica',
                            child: Text('Helvetica', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                          DropdownMenuItem(
                            value: 'Arial',
                            child: Text('Arial', style: TextStyle(color: Colors.white, fontSize: ResumeTypography.body)),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _bodyFontFamily = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect? _shareOriginForExport() {
    final box =
        _downloadExportTileKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final o = box.localToGlobal(Offset.zero);
      return Rect.fromLTWH(o.dx, o.dy, box.size.width, box.size.height);
    }
    final sz = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Rect.fromLTWH(12, sz.height - pad.bottom - 4, sz.width - 24, 1);
  }

  /// Download uses the styled (WYSIWYG) PDF that matches the preview, then the
  /// “PDF ready” sheet (share vs print). For ATS text PDF use the editor Download.
  Future<void> _startResumeDownloadExport() async {
    if (_resumePdfExportInProgress) return;
    HapticFeedback.selectionClick();
    await _runResumeExport(_ResumeExportKind.styledPreview);
  }

  Future<void> _runResumeExport(_ResumeExportKind kind) async {
    if (!mounted || _resumePdfExportInProgress) return;
    _resumePdfExportInProgress = true;
    final t = AppLocalizations.of(context)!;
    final nav = Navigator.of(context, rootNavigator: true);
    final status = ValueNotifier<String>(t.resumeExportPreparing);
    final accent = kind == _ResumeExportKind.styledPreview
        ? _previewActionCyan
        : const Color(0xFF22C55E);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.42),
      builder: (dialogCtx) {
        final bottomPad =
            MediaQuery.paddingOf(dialogCtx).bottom + 102;
        return ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, msg, _) {
            return PopScope(
              canPop: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPad),
                  child: Material(
                    color: const Color(0xFF0B1220),
                    elevation: 24,
                    shadowColor: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: math.min(400, MediaQuery.sizeOf(dialogCtx).width - 36),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.white.withOpacity(0.08),
                              color: accent,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: accent,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      msg,
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.94),
                                        fontWeight: FontWeight.w700,
                                        fontSize: ResumeTypography.heading,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;

    ResumePdfExport? built;
    try {
      switch (kind) {
        case _ResumeExportKind.styledPreview:
          final pagePngs = await _renderVisiblePreviewPagesToPngs(
            onProgress: (done, total) {
              status.value = t.resumeExportRenderingPage(done, total);
            },
          );
          status.value = t.resumeExportBuildingPdf;
          built = await PdfService.exportTemplatePreviewPdfToTemp(
            pagePngBytes: pagePngs,
            data: widget.data,
          );
          break;
        case _ResumeExportKind.atsText:
          status.value = t.resumeExportBuildingPdf;
          built = await PdfService.exportResumePdfToTemp(data: widget.data);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final detail = e is StateError ? e.message : null;
      AppToast.error(
        context,
        detail != null && detail.isNotEmpty
            ? '${t.downloadCouldNotComplete} $detail'
            : t.downloadCouldNotComplete,
      );
    } finally {
      status.dispose();
      _resumePdfExportInProgress = false;
      if (mounted) {
        nav.pop();
      }
    }

    if (built == null || !mounted) return;

    final origin = _shareOriginForExport();
    final choice = await showResumePdfPostExportSheet(
      context,
      strings: t,
    );
    if (!mounted) return;

    switch (choice) {
      case ResumePdfPostExportChoice.share:
        await Share.shareXFiles(
          [
            XFile(
              built.file.path,
              mimeType: 'application/pdf',
              name: built.displayName,
            ),
          ],
          subject: 'Resume',
          sharePositionOrigin: origin,
        );
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        AppToast.success(context, t.resumePdfExportShareHint);
        break;
      case ResumePdfPostExportChoice.print:
        final pr = await PdfService.presentSystemPrintForPdf(
          built.file,
          name: built.displayName,
        );
        if (!mounted) return;
        if (pr == null) {
          AppToast.error(context, t.printingUnavailable);
        } else if (pr) {
          HapticFeedback.mediumImpact();
          AppToast.success(context, t.resumeExportPrintComplete);
        }
        break;
      case null:
        break;
    }
  }

  Future<List<Uint8List>> _renderVisiblePreviewPagesToPngs({
    void Function(int done, int total)? onProgress,
  }) async {
    // Wait until the preview has published stable repaint keys for all pages.
    for (var attempt = 0; attempt < 30; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (_exportPageBoundaryKeys.isNotEmpty) break;
    }

    final keys = _exportPageBoundaryKeys;
    if (keys.isEmpty) {
      throw StateError('Preview pages are not ready yet. Scroll once and try again.');
    }

    final pngs = <Uint8List>[];
    final restoreOffset =
        _previewScrollController.hasClients ? _previewScrollController.offset : null;
    for (final k in keys) {
      final ctx = k.currentContext;
      if (ctx == null) {
        throw StateError('Export page boundary missing.');
      }

      // Force the page into view so it gets painted (otherwise toImage() may
      // only work for the currently visible page).
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.0,
      );
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Export page boundary missing.');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError('Failed to encode PNG.');
      }
      pngs.add(byteData.buffer.asUint8List());
      onProgress?.call(pngs.length, keys.length);
    }
    if (restoreOffset != null && _previewScrollController.hasClients) {
      try {
        _previewScrollController.jumpTo(restoreOffset);
      } catch (_) {
        // Best-effort: if layout changed during export, ignore.
      }
    }
    return pngs;
  }

  static const Color _previewActionViolet = Color(0xFF7C3AED);
  static const Color _previewActionCyan = Color(0xFF06B6D4);

  Widget _previewActionTile({
    Key? tileKey,
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return KeyedSubtree(
      key: tileKey,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Material(
          color: Colors.white.withOpacity(0.06),
          child: InkWell(
            onTap: busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withOpacity(0.28),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: accent,
                      ),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.14),
                            Colors.white.withOpacity(0.06),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withOpacity(0.16)),
                      ),
                      child: Icon(icon, color: accent, size: 18),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: ResumeTypography.heading,
                            height: 1.1,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontWeight: FontWeight.w600,
                            fontSize: ResumeTypography.body,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _jobTailorAndDownloadStrip(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _previewActionTile(
              accent: _previewActionViolet,
              icon: Icons.auto_awesome_rounded,
              title: t.resumePreviewTailorActionTitle,
              subtitle: t.resumePreviewTailorActionSubtitle,
              busy: _tailoringAi,
              onTap: _openResumeJobTailoring,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _previewActionTile(
              tileKey: _downloadExportTileKey,
              accent: _previewActionCyan,
              icon: Icons.download_rounded,
              title: t.resumePreviewDownloadActionTitle,
              subtitle: t.resumePreviewDownloadActionSubtitle,
              busy: false,
              onTap: _startResumeDownloadExport,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: UniformAppBar.material(
        t.resumePreviewTitle,
      ),
      body: Stack(
        children: [
          const _ATSLikeBackground(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HomeBuilderPage(
                                  data: widget.data,
                                  expandAllSectionsForEdit: true,
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.18)),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _accentColor.withOpacity(0.38),
                                  _accentColor.withOpacity(0.16),
                                  Colors.white.withOpacity(0.04),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accentColor.withOpacity(0.28),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.08),
                                  blurRadius: 22,
                                  offset: const Offset(0, 0),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withOpacity(0.22),
                                        Colors.white.withOpacity(0.08),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.edit_note_rounded,
                                    color: Color(0xFFE2E8F0),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    t.resumePreviewEditResume,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE2E8F0),
                                      fontWeight: FontWeight.w900,
                                      fontSize: ResumeTypography.heading,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _themePanel(context),
              Expanded(
                child: _ResumePreviewBody(
                  data: widget.data,
                  templateId: widget.templateId,
                  t2HeaderColor: _t2HeaderColor,
                  t2GoldColor: _t2GoldColor,
                  accentColor: _accentColor,
                  nameFontFamily: _nameFontFamily,
                  bodyFontFamily: _bodyFontFamily,
                  scrollController: _previewScrollController,
                  exportPageBoundaryKeys: _exportPageBoundaryKeys,
                  onExportKeysReady: (keys) {
                    if (!mounted) return;
                    if (_exportPageBoundaryKeys.length == keys.length &&
                        _exportPageBoundaryKeys.isNotEmpty) {
                      return;
                    }
                    setState(() => _exportPageBoundaryKeys = keys);
                  },
                ),
              ),
              SafeArea(
                top: false,
                minimum: EdgeInsets.zero,
                child: _jobTailorAndDownloadStrip(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _ResumePreviewBody extends StatelessWidget {
  final ResumeData data;
  final String templateId;
  final Color? t2HeaderColor;
  final Color? t2GoldColor;
  final Color accentColor;
  final String? nameFontFamily;
  final String? bodyFontFamily;
  final ScrollController? scrollController;
  final List<GlobalKey>? exportPageBoundaryKeys;
  final ValueChanged<List<GlobalKey>>? onExportKeysReady;

  const _ResumePreviewBody({
    required this.data,
    required this.templateId,
    this.t2HeaderColor,
    this.t2GoldColor,
    required this.accentColor,
    this.nameFontFamily,
    this.bodyFontFamily,
    this.scrollController,
    this.exportPageBoundaryKeys,
    this.onExportKeysReady,
  });

  /// Resolves nullable font pickers (no extra packages; works on Flutter 3.16).
  String get _bodyFf {
    final b = bodyFontFamily ?? 'Roboto';
    if (b == 'Helvetica' || b == 'Arial') return 'monospace';
    return b;
  }

  String get _nameFf => nameFontFamily ?? 'Georgia';

  @override
  Widget build(BuildContext context) {
    final layout = ResumeLayoutEngine.build(data, templateId: templateId);
    final baseStyle = _TemplateStyles.forId(templateId);
    final accent =
        templateId == "2" && t2GoldColor != null ? t2GoldColor! : accentColor;
    final style = baseStyle.copyWithAccent(accent);

    return LayoutBuilder(
        builder: (context, constraints) {
          const outerMargin = 16.0;
          final layoutMaxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final availableWidth =
              (layoutMaxW - outerMargin * 2).clamp(260.0, layoutMaxW);
          // Render at a fixed “paper” width, then uniformly scale to fit the phone width.
          // Using FittedBox avoids the “tiny thumbnail” effect that can happen with
          // Transform.scale + outer sizing mismatches.
          final paperWidth = _PreviewMetrics.pageWidth;
          final placement = style.sidebarPlacement;
          final isSingleColumn = placement == _SidebarPlacement.none;
          // Keep sidebar at ~1/3, with a safe minimum so it doesn't collapse
          // on small screens (which causes wrapping/overflow).
          final maxSidebar = paperWidth * 0.40;
          var minSidebar = 150.0;
          if (minSidebar > maxSidebar) minSidebar = maxSidebar;
          final sidebarWidth = isSingleColumn
              ? 0.0
              : (paperWidth / 3).clamp(minSidebar, maxSidebar);
          // Match ISO A4 exactly so PNG export matches [PdfService.styledTemplateExportPageFormat].
          final pageHeight =
              paperWidth * PdfService.styledTemplateExportPageFormat.height /
                  PdfService.styledTemplateExportPageFormat.width;
          const pageFooterBar = 28.0;
          final rightWidth = isSingleColumn
              ? math.max(120.0, paperWidth - 26 * 2)
              : math.max(120.0, paperWidth - sidebarWidth - 26 * 2);
          final t1BannerHeight = templateId == '1'
              ? _measureTemplate1BannerHeight(paperWidth)
              : _kTemplate1BannerHeight;
          final pages = _paginate(
            layout,
            pageHeight: pageHeight,
            rightWidth: rightWidth,
            templateId: templateId,
            l10n: AppLocalizations.of(context),
            bodyFontFamily: _bodyFf,
            template1BannerHeight: t1BannerHeight,
          );

          final keysOk = exportPageBoundaryKeys != null &&
              exportPageBoundaryKeys!.length == pages.length;
          if (!keysOk && onExportKeysReady != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onExportKeysReady!(
                List<GlobalKey>.generate(pages.length, (_) => GlobalKey()),
              );
            });
          }
          final keys = keysOk ? exportPageBoundaryKeys! : null;

          final mainContentPadding = switch (templateId) {
            "2" => const EdgeInsets.fromLTRB(30, 26, 30, 22),
            "4" => const EdgeInsets.fromLTRB(28, 22, 28, 24),
            "7" => const EdgeInsets.fromLTRB(26, 10, 26, 24),
            "8" => const EdgeInsets.fromLTRB(24, 20, 24, 24),
            _ => const EdgeInsets.fromLTRB(26, 26, 26, 26),
          };

          List<Widget> mainColumnChildren(int i) {
            return <Widget>[
              if (i == 0 && templateId == "3")
                _templateHeaderRibbon(style),
              if (i == 0 && templateId == "4")
                _templateHeaderBlackYellow(style),
              if (i == 0 && templateId == "5")
                _templateHeaderGreyOverlap(style),
              if (i == 0 && templateId == "6") _templateHeaderClassic(style),
              if (i == 0 && templateId == "7")
                _templateHeaderSlateHero(style),
              if (i == 0 && templateId == "8")
                _templateHeaderModernCards(style),
              if (i == 0 && templateId == "9")
                _templateHeaderGoldHeader(style),
              if (i == 0 && templateId == "10")
                _templateHeaderMobileCard(style),
              if (i == 0 && templateId == "11")
                _templateHeaderAtsPro(style),
              if (i == 0 && templateId == "12")
                _templateHeaderExecutiveMono(style),
              if (i == 0 && templateId == "13")
                _templateHeaderCompactModern(style),
              ...pages[i]
                  .rightSections
                  .map((s) => _buildSection(context, s, style)),
            ];
          }

          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            child: Center(
              child: Column(
                children: [
                  for (var i = 0; i < pages.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final bannerHeight =
                            (templateId == "2" && i == 0) ? 82.0 : 0.0;
                        return SizedBox(
                          width: layoutMaxW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: outerMargin,
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: availableWidth,
                                child: Builder(
                                  builder: (_) {
                                    final fitted = FittedBox(
                                      fit: BoxFit.fitWidth,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: paperWidth,
                                        height: pageHeight,
                                        child: Material(
                                          elevation: 2,
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            clipBehavior: Clip.antiAlias,
                                            child: templateId == "1"
                                                ? Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (i == 0)
                                                      SizedBox(
                                                        height: t1BannerHeight,
                                                        child:
                                                            _template1TopBanner(
                                                          accent,
                                                        ),
                                                      ),
                                                    SizedBox(
                                                      height: pageHeight -
                                                          pageFooterBar -
                                                          (i == 0
                                                              ? t1BannerHeight
                                                              : 0),
                                                      child: Padding(
                                                        padding:
                                                            i == 0
                                                                ? mainContentPadding
                                                                    .copyWith(top: 12)
                                                                : mainContentPadding,
                                                        child: ClipRect(
                                                          clipBehavior:
                                                              Clip.hardEdge,
                                                          child: LayoutBuilder(
                                                            builder: (ctx, c) {
                                                              // Tight horizontal width: `minWidth`-only ConstrainedBox lets the
                                                              // scroll child Column shrink to intrinsic width, so content sits
                                                              // on the left with empty white on the right (preview + PDF PNG).
                                                              return SingleChildScrollView(
                                                                physics:
                                                                    const NeverScrollableScrollPhysics(),
                                                                child: SizedBox(
                                                                  width: c.maxWidth,
                                                                  child: Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize.min,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .stretch,
                                                                    children:
                                                                        mainColumnChildren(
                                                                            i),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: pageFooterBar,
                                                      child: Center(
                                                        child: Text(
                                                          AppLocalizations.of(
                                                                  context)
                                                              .pageIndicator(
                                                            i + 1,
                                                            pages.length,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: ResumeTypography.body,
                                                            color: Colors.grey
                                                                .shade600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Column(
                                                  mainAxisSize:
                                                      MainAxisSize.max,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (bannerHeight > 0)
                                                      SizedBox(
                                                        height: bannerHeight,
                                                        child:
                                                            _template2TopBanner(),
                                                      ),
                                                    SizedBox(
                                                      height: pageHeight -
                                                          bannerHeight -
                                                          pageFooterBar,
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          if (placement ==
                                                              _SidebarPlacement
                                                                  .left)
                                                            SizedBox(
                                                              width:
                                                                  sidebarWidth,
                                                              child: ClipRect(
                                                                clipBehavior: Clip
                                                                    .hardEdge,
                                                                child: _sidebar(
                                                                  pages[i],
                                                                  sidebarWidth:
                                                                      sidebarWidth,
                                                                  style: style,
                                                                ),
                                                              ),
                                                            ),
                                                          Expanded(
                                                            child:
                                                                LayoutBuilder(
                                                              builder: (ctx2, c2) {
                                                                // Template 2: fixed “paper” height — inner scroll fights the outer
                                                                // preview scroll and feels broken; pagination should bound content.
                                                                return SingleChildScrollView(
                                                                  physics: templateId ==
                                                                          "1"
                                                                      ? const ClampingScrollPhysics()
                                                                      : const NeverScrollableScrollPhysics(),
                                                                  padding:
                                                                      EdgeInsets.zero,
                                                                  child: SizedBox(
                                                                    width: c2.maxWidth,
                                                                    child: Padding(
                                                                      padding:
                                                                          mainContentPadding,
                                                                      child: ClipRect(
                                                                        clipBehavior:
                                                                            Clip.hardEdge,
                                                                        child: Column(
                                                                          mainAxisSize:
                                                                              MainAxisSize.min,
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.stretch,
                                                                          children:
                                                                              mainColumnChildren(i),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                          if (placement ==
                                                              _SidebarPlacement
                                                                  .right)
                                                            SizedBox(
                                                              width:
                                                                  sidebarWidth,
                                                              child: ClipRect(
                                                                clipBehavior: Clip
                                                                    .hardEdge,
                                                                child: _sidebar(
                                                                  pages[i],
                                                                  sidebarWidth:
                                                                      sidebarWidth,
                                                                  style: style,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: pageFooterBar,
                                                      child: Center(
                                                        child: Text(
                                                          AppLocalizations.of(
                                                                  context)
                                                              .pageIndicator(
                                                            i + 1,
                                                            pages.length,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: ResumeTypography.body,
                                                            color: Colors.grey
                                                                .shade600,
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
                                    if (keys == null) return fitted;
                                    return RepaintBoundary(
                                      key: keys[i],
                                      child: fitted,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
  }

  /// Height model for one template-1 experience slice (uses same math as pagination).
  double _estimateTemplate1ExperienceSliceHeight({
    required Experience exp,
    required bool showWorkHeading,
    required bool showJobHeader,
    required String bodyFontFamily,
    double availableWidth = _PreviewMetrics.pageWidth - 52,
  }) {
    return Template1LayoutMetrics.sectionHeight(
      {
        'type': 'experience',
        'items': <Experience>[exp],
        't1_show_work_heading': showWorkHeading,
        't1_show_job_header': showJobHeader,
      },
      contentWidth: availableWidth,
      fontFamily: bodyFontFamily,
    );
  }

  /// Splits multi-item list sections so pagination can place more on each page.
  List<Map<String, dynamic>> _splitTemplate1ListSections(
    List<Map<String, dynamic>> right,
  ) {
    const splittable = <String>{
      'education',
      'projects',
      'courses',
      'certifications',
      'achievement',
    };
    const headingKey = 't1_show_section_heading';

    final out = <Map<String, dynamic>>[];
    for (final s in right) {
      final type = s['type']?.toString() ?? '';
      if (!splittable.contains(type)) {
        out.add(s);
        continue;
      }
      final items = (s['items'] as List?) ?? const [];
      if (items.length <= 1) {
        out.add(Map<String, dynamic>.from(s)..[headingKey] = true);
        continue;
      }
      var showHeading = true;
      for (final item in items) {
        out.add({
          ...Map<String, dynamic>.from(s),
          'items': <dynamic>[item],
          headingKey: showHeading,
        });
        showHeading = false;
      }
    }
    return out;
  }

  double _template1StackedHeight(
    List<Map<String, dynamic>> sections,
    double contentWidth,
    String bodyFontFamily,
  ) {
    return Template1LayoutMetrics.stackedSectionsHeight(
      sections: sections,
      contentWidth: contentWidth,
      fontFamily: bodyFontFamily,
    );
  }

  double _template1SectionHeight(
    Map<String, dynamic> section,
    double contentWidth,
    String bodyFontFamily,
  ) {
    return Template1LayoutMetrics.sectionHeight(
      section,
      contentWidth: contentWidth,
      fontFamily: bodyFontFamily,
    );
  }

  bool _sameTemplate1Job(Experience a, Experience b) {
    return a.role.trim() == b.role.trim() &&
        a.company.trim() == b.company.trim() &&
        a.duration.trim() == b.duration.trim();
  }

  List<Experience> _appendJobBulletsToPageItems(
    List<Experience> pageItems,
    Experience job,
    List<String> bullets,
    int from,
    int to,
  ) {
    final chunk = bullets.sublist(from, to);
    final out = List<Experience>.from(pageItems);
    if (out.isNotEmpty && _sameTemplate1Job(out.last, job)) {
      final merged = <String>[
        ...out.last.description,
        ...chunk,
      ];
      out[out.length - 1] = Experience(
        role: job.role,
        company: job.company,
        duration: job.duration,
        description: merged,
      );
    } else {
      out.add(
        Experience(
          role: job.role,
          company: job.company,
          duration: job.duration,
          description: chunk,
        ),
      );
    }
    return out;
  }

  Map<String, dynamic> _template1ExperienceSectionMap({
    required List<Experience> items,
    required bool showWorkHeading,
    required bool singleItemShowJobHeader,
  }) {
    return {
      'type': 'experience',
      'items': items,
      't1_show_work_heading': showWorkHeading,
      't1_show_job_header': singleItemShowJobHeader,
    };
  }

  double _measureExperienceSection(
    List<Experience> items,
    bool showWorkHeading,
    bool showJobHeaders,
    double contentWidth,
    String bodyFontFamily,
    String templateId,
  ) {
    if (templateId == '1') {
      return Template1LayoutMetrics.sectionHeight(
        _template1ExperienceSectionMap(
          items: items,
          showWorkHeading: showWorkHeading,
          singleItemShowJobHeader: showJobHeaders,
        ),
        contentWidth: contentWidth,
        fontFamily: bodyFontFamily,
      );
    }
    return ResumePreviewLayoutMetrics.sectionHeight(
      _template1ExperienceSectionMap(
        items: items,
        showWorkHeading: showWorkHeading,
        singleItemShowJobHeader: showJobHeaders,
      ),
      contentWidth: contentWidth,
      fontFamily: bodyFontFamily,
      templateId: templateId,
    );
  }

  bool _template1ShowJobHeadersForMeasure(List<Experience> items, int bulletFrom) {
    return items.length > 1 || bulletFrom == 0;
  }

  /// Fills the current page with as much work history as fits — jobs continue on the
  /// same page when space remains (no forced page break per role).
  _T1ExperienceFillResult _fillExperienceForPage({
    required List<Experience> jobs,
    required int startJob,
    required int startBullet,
    required bool showWorkHeading,
    required double maxHeight,
    required double contentWidth,
    required String bodyFontFamily,
    required String templateId,
  }) {
    var ji = startJob;
    var bi = startBullet;
    var wh = showWorkHeading;
    final pageItems = <Experience>[];

    while (ji < jobs.length) {
      final job = jobs[ji];
      final bullets = job.description
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();

      if (bi >= bullets.length) {
        ji++;
        bi = 0;
        continue;
      }

      if (bullets.isEmpty) {
        final trial = List<Experience>.from(pageItems)..add(job);
        final h = _measureExperienceSection(
          trial,
          wh,
          _template1ShowJobHeadersForMeasure(trial, 0),
          contentWidth,
          bodyFontFamily,
          templateId,
        );
        if (pageItems.isNotEmpty && h > maxHeight) break;
        pageItems
          ..clear()
          ..addAll(trial);
        ji++;
        bi = 0;
        wh = false;
        if (h > maxHeight) break;
        continue;
      }

      var bestEnd = bi;
      for (var tryEnd = bi + 1; tryEnd <= bullets.length; tryEnd++) {
        final trial = _appendJobBulletsToPageItems(
          pageItems,
          job,
          bullets,
          bi,
          tryEnd,
        );
        final h = _measureExperienceSection(
          trial,
          wh,
          _template1ShowJobHeadersForMeasure(trial, bi),
          contentWidth,
          bodyFontFamily,
          templateId,
        );
        if (h <= maxHeight) {
          bestEnd = tryEnd;
        } else {
          break;
        }
      }

      if (bestEnd <= bi) {
        if (pageItems.isEmpty && bi < bullets.length) {
          final lone = _appendJobBulletsToPageItems(
            pageItems,
            job,
            bullets,
            bi,
            bi + 1,
          );
          final loneH = _measureExperienceSection(
            lone,
            wh,
            _template1ShowJobHeadersForMeasure(lone, bi),
            contentWidth,
            bodyFontFamily,
            templateId,
          );
          if (loneH <= maxHeight) {
            bestEnd = bi + 1;
          } else {
            break;
          }
        } else {
          break;
        }
      }

      final trial = _appendJobBulletsToPageItems(
        pageItems,
        job,
        bullets,
        bi,
        bestEnd,
      );
      final trialH = _measureExperienceSection(
        trial,
        wh,
        _template1ShowJobHeadersForMeasure(trial, bi),
        contentWidth,
        bodyFontFamily,
        templateId,
      );
      if (pageItems.isNotEmpty && trialH > maxHeight) break;

      pageItems
        ..clear()
        ..addAll(trial);
      bi = bestEnd;
      wh = false;

      if (bi >= bullets.length) {
        ji++;
        bi = 0;
        final usedNow = _measureExperienceSection(
          pageItems,
          showWorkHeading,
          true,
          contentWidth,
          bodyFontFamily,
          templateId,
        );
        if (usedNow >= maxHeight || ji >= jobs.length) {
          break;
        }
        continue;
      }
      break;
    }

    if (pageItems.isEmpty) {
      return _T1ExperienceFillResult(
        items: const [],
        endJobIndex: ji,
        endBulletIndex: bi,
        showWorkHeadingOnPage: showWorkHeading,
        showWorkHeadingAfter: showWorkHeading,
        singleItemShowJobHeader: true,
        allExperienceComplete: ji >= jobs.length,
        measuredHeight: 0,
      );
    }

    final showWhOnPage = showWorkHeading;
    final singleItemShowJobHeader =
        pageItems.length > 1 || startBullet == 0;
    final measured = _measureExperienceSection(
      pageItems,
      showWhOnPage,
      singleItemShowJobHeader,
      contentWidth,
      bodyFontFamily,
      templateId,
    );

    return _T1ExperienceFillResult(
      items: pageItems,
      endJobIndex: ji,
      endBulletIndex: bi,
      showWorkHeadingOnPage: showWhOnPage,
      showWorkHeadingAfter: false,
      singleItemShowJobHeader: singleItemShowJobHeader,
      allExperienceComplete: ji >= jobs.length,
      measuredHeight: measured,
    );
  }

  /// Builds one page's main column; work experience continues across pages (templates 1 & 2).
  ({List<Map<String, dynamic>> sections, int nextIndex}) _takeTemplatePageRightSections({
    required List<Map<String, dynamic>> right,
    required int startIndex,
    required double availHeight,
    required double contentWidth,
    required String bodyFontFamily,
    required _T1ExperiencePageState expState,
    required String templateId,
  }) {
    final limit = templateId == '1'
        ? availHeight - Template1LayoutMetrics.renderSafetyMargin
        : availHeight -
            ResumePreviewLayoutMetrics.renderSafetyMargin +
            ResumePreviewLayoutMetrics.packBudgetFor(templateId);
    final out = <Map<String, dynamic>>[];
    var used = 0.0;
    var i = startIndex;

    while (i < right.length) {
      final s = right[i];
      if (s['type'] == 'experience') {
        final jobs =
            (s['items'] as List?)?.cast<Experience>() ?? const <Experience>[];
        final remaining = limit - used;
        if (remaining < 40) break;

        final fill = _fillExperienceForPage(
          jobs: jobs,
          startJob: expState.jobIndex,
          startBullet: expState.bulletIndex,
          showWorkHeading: expState.showWorkHeading,
          maxHeight: remaining,
          contentWidth: contentWidth,
          bodyFontFamily: bodyFontFamily,
          templateId: templateId,
        );

        if (fill.items.isEmpty) break;

        out.add(
          _template1ExperienceSectionMap(
            items: fill.items,
            showWorkHeading: fill.showWorkHeadingOnPage,
            singleItemShowJobHeader: fill.singleItemShowJobHeader,
          ),
        );

        used += fill.measuredHeight;
        expState.jobIndex = fill.endJobIndex;
        expState.bulletIndex = fill.endBulletIndex;
        expState.showWorkHeading = fill.showWorkHeadingAfter;

        if (fill.allExperienceComplete) {
          i++;
        } else {
          break;
        }
        continue;
      }

      final h = templateId == '1'
          ? Template1LayoutMetrics.sectionHeight(
              s,
              contentWidth: contentWidth,
              fontFamily: bodyFontFamily,
            )
          : ResumePreviewLayoutMetrics.sectionHeight(
              s,
              contentWidth: contentWidth,
              fontFamily: bodyFontFamily,
              templateId: templateId,
            );
      if (used + h > limit) break;
      out.add(s);
      used += h;
      i++;
    }

    if (out.isEmpty && i < right.length) {
      final s = right[i];
      out.add(s);
      i++;
    }

    return (sections: out, nextIndex: i);
  }

  /// Breaks large jobs into multiple [experience] sections so pagination can move overflow to the next page.
  List<Map<String, dynamic>> _expandTemplate1ExperienceSlices(
    List<Map<String, dynamic>> right,
    double maxFirstSliceHeight,
    double maxContinuationSliceHeight, {
    required String bodyFontFamily,
    double availableWidth = _PreviewMetrics.pageWidth - 52,
  }) {
    final out = <Map<String, dynamic>>[];
    var firstExperienceSlice = true;
    for (final s in right) {
      if (s["type"] != "experience") {
        out.add(Map<String, dynamic>.from(s));
        continue;
      }
      final rawItems = (s["items"] as List?) ?? const <dynamic>[];
      if (rawItems.isEmpty) continue;

      final jdStr = (s["target_jd"] ?? "").toString().trim();
      var jdAttached = false;

      var showNextWorkHeading = true;

      for (final raw in rawItems) {
        final e = raw as Experience;
        final bullets = e.description
            .map((b) => b.trim())
            .where((b) => b.isNotEmpty)
            .toList();

        if (bullets.isEmpty) {
          final m = <String, dynamic>{
            "type": "experience",
            "items": <Experience>[e],
            "t1_show_work_heading": showNextWorkHeading,
            "t1_show_job_header": true,
          };
          if (jdStr.isNotEmpty && showNextWorkHeading && !jdAttached) {
            m["target_jd"] = jdStr;
            jdAttached = true;
          }
          out.add(m);
          firstExperienceSlice = false;
          showNextWorkHeading = false;
          continue;
        }

        var showJobHeader = true;
        var bi = 0;
        while (bi < bullets.length) {
          final maxSliceHeight = firstExperienceSlice
              ? maxFirstSliceHeight
              : maxContinuationSliceHeight;
          var lo = bi + 1;
          var hi = bullets.length;
          var bestEnd = bi + 1;
          while (lo <= hi) {
            final mid = (lo + hi) ~/ 2;
            final chunk = bullets.sublist(bi, mid);
            final est = _estimateTemplate1ExperienceSliceHeight(
              exp: Experience(
                role: e.role,
                company: e.company,
                duration: e.duration,
                description: chunk,
              ),
              showWorkHeading: showNextWorkHeading,
              showJobHeader: showJobHeader,
              bodyFontFamily: bodyFontFamily,
              availableWidth: availableWidth,
            );
            if (est <= maxSliceHeight) {
              bestEnd = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }
          if (bestEnd <= bi) bestEnd = bi + 1;
          final chunk = bullets.sublist(bi, bestEnd);
          final m = <String, dynamic>{
            "type": "experience",
            "items": <Experience>[
              Experience(
                role: e.role,
                company: e.company,
                duration: e.duration,
                description: chunk,
              ),
            ],
            "t1_show_work_heading": showNextWorkHeading,
            "t1_show_job_header": showJobHeader,
          };
          if (jdStr.isNotEmpty && showNextWorkHeading && !jdAttached) {
            m["target_jd"] = jdStr;
            jdAttached = true;
          }
          out.add(m);
          firstExperienceSlice = false;
          showNextWorkHeading = false;
          showJobHeader = false;
          bi = bestEnd;
        }
      }
    }
    return out;
  }

  /// Splits large multi-job experience sections into smaller chunks so earlier pages
  /// can still show some experience (instead of pushing the whole section to page 2+).
  ///
  /// Template 1 uses bullet-level slicing; other templates slice at the job level.
  List<Map<String, dynamic>> _expandExperienceJobChunks(
    List<Map<String, dynamic>> right,
    double maxChunkHeight, {
    required String templateId,
    required double contentWidth,
    required String bodyFontFamily,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final s in right) {
      if (s["type"] != "experience") {
        out.add(s);
        continue;
      }
      final items = (s["items"] as List?) ?? const [];
      if (items.isEmpty) {
        out.add(s);
        continue;
      }

      final jd = (s["target_jd"] ?? "").toString().trim();
      final base = Map<String, dynamic>.from(s)..remove("target_jd");
      var jdAttached = false;

      double jobH(Experience e) {
        return ResumePreviewLayoutMetrics.sectionHeight(
          {
            'type': 'experience',
            'items': <Experience>[e],
            't1_show_work_heading': false,
            't1_show_job_header': true,
          },
          contentWidth: contentWidth,
          fontFamily: bodyFontFamily,
          templateId: templateId,
        );
      }

      final headingH = ResumePreviewLayoutMetrics.sectionHeight(
        {
          'type': 'experience',
          'items': const <Experience>[],
          't1_show_work_heading': true,
          't1_show_job_header': false,
        },
        contentWidth: contentWidth,
        fontFamily: bodyFontFamily,
        templateId: templateId,
      );
      var buf = <Experience>[];
      var used = headingH;

      void flush() {
        if (buf.isEmpty) return;
        final m = <String, dynamic>{
          ...base,
          "items": List<Experience>.from(buf),
        };
        if (!jdAttached && jd.isNotEmpty) {
          m["target_jd"] = jd;
          jdAttached = true;
        }
        out.add(m);
        buf = <Experience>[];
        used = headingH;
      }

      for (final raw in items) {
        if (raw is! Experience) continue;
        final h = jobH(raw);
        if (buf.isEmpty) {
          buf.add(raw);
          used += h;
          continue;
        }
        if (used + h > maxChunkHeight) {
          flush();
          buf.add(raw);
          used += h;
        } else {
          buf.add(raw);
          used += h;
        }
      }
      flush();
    }

    return out;
  }

  /// Further splits template-2 experience so each chunk fits [maxChunkHeight], moving
  /// overflow to later pages instead of relying on a scrollable right column.
  List<Map<String, dynamic>> _expandTemplate2ExperienceBulletSlices(
    List<Map<String, dynamic>> right,
    double maxChunkHeight,
  ) {
    double chunkHeight({
      required bool workHeading,
      required bool jobHeading,
      required bool hasIntro,
      required int bulletCount,
    }) {
      var h = 0.0;
      if (workHeading) h += 52;
      if (jobHeading) {
        h += 56;
        if (hasIntro) h += 46;
      } else {
        h += 10;
      }
      if (bulletCount > 0) {
        h += 10;
        h += bulletCount * 23.0;
      } else if (hasIntro) {
        h += 10;
      }
      h += 20;
      return h;
    }

    final out = <Map<String, dynamic>>[];
    for (final s in right) {
      if (s["type"] != "experience") {
        out.add(s);
        continue;
      }
      final jd = (s["target_jd"] ?? "").toString().trim();
      final base = Map<String, dynamic>.from(s)
        ..remove("target_jd")
        ..remove("items");
      final items = (s["items"] as List?) ?? const [];
      if (items.isEmpty) {
        out.add(s);
        continue;
      }

      var jdAttached = false;
      var firstInSourceSection = true;

      for (final raw in items) {
        if (raw is! Experience) continue;
        final exp = raw;
        final bullets = exp.description
            .map((b) => b.trim())
            .where((b) => b.isNotEmpty)
            .toList();

        final split = ExperienceDisplay.splitIntroFromBullets(
          bullets,
          allowIntro: true,
        );
        var intro = split.intro;
        var bulletLines = split.bullets;
        if (bullets.isEmpty) {
          final m = <String, dynamic>{
            ...base,
            "type": "experience",
            "items": <Experience>[exp],
            "t1_show_work_heading": firstInSourceSection,
            "t1_show_job_header": true,
          };
          if (!jdAttached && jd.isNotEmpty) {
            m["target_jd"] = jd;
            jdAttached = true;
          }
          out.add(m);
          firstInSourceSection = false;
          continue;
        }

        var introDone = intro == null;
        var bi = 0;
        var firstForJob = true;
        var guard = 0;

        while ((!introDone || bi < bulletLines.length) && guard < 400) {
          guard++;
          final workHead = firstInSourceSection;
          final jobHead = firstForJob;
          final useIntro = jobHead && intro != null && !introDone;

          var take = 0;
          final maxTake = bulletLines.length - bi;
          for (var k = 0; k <= maxTake; k++) {
            if (chunkHeight(
                  workHeading: workHead,
                  jobHeading: jobHead,
                  hasIntro: useIntro,
                  bulletCount: k,
                ) <=
                maxChunkHeight) {
              take = k;
            } else {
              break;
            }
          }
          if (take == 0 && bi < bulletLines.length) {
            take = 1;
          }

          final desc = <String>[];
          if (useIntro) {
            desc.add(intro!);
            introDone = true;
          }
          desc.addAll(bulletLines.sublist(bi, bi + take));
          bi += take;

          final sub = Experience(
            role: exp.role,
            company: exp.company,
            duration: exp.duration,
            description: desc,
          );
          final m = <String, dynamic>{
            ...base,
            "type": "experience",
            "items": <Experience>[sub],
            "t1_show_work_heading": workHead,
            "t1_show_job_header": jobHead,
          };
          if (!jdAttached && jd.isNotEmpty) {
            m["target_jd"] = jd;
            jdAttached = true;
          }
          out.add(m);

          firstInSourceSection = false;
          firstForJob = false;
        }
      }
    }

    return out;
  }

  double _mainColumnAvailHeight({
    required int pageIndex,
    required String templateId,
    required double pageHeight,
    required double rightInnerHeight,
    required double template1BannerHeight,
  }) {
    if (templateId == '1') {
      return pageIndex == 0
          ? _PreviewMetrics.template1Page1RightHeight(
              pageHeight,
              bannerHeight: template1BannerHeight,
            )
          : _PreviewMetrics.template1ContinuationRightHeight(pageHeight);
    }
    var h = rightInnerHeight;
    if (pageIndex == 0) {
      h -= ResumePreviewLayoutMetrics.page1MainHeaderReserve(templateId);
    }
    return h.clamp(120.0, rightInnerHeight);
  }

  double _measureTemplate1BannerHeight(double paperWidth) {
    double paintH(String text, TextStyle style, double maxW, {int maxLines = 2}) {
      final t = text.trim();
      if (t.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: maxW);
      return painter.height;
    }

    const padV = 13.0 + 11.0;
    var h = padV;
    final innerW = paperWidth - 40;
    final nameStyle = TextStyle(
      fontFamily: _nameFf,
      fontSize: ResumeTypography.name,
      fontWeight: FontWeight.w900,
      height: 1.08,
    );
    final roleStyle = TextStyle(
      fontFamily: _bodyFf,
      fontSize: ResumeTypography.body,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final name = data.name.trim().isNotEmpty ? data.name.trim() : 'Your Name';
    h += paintH(name, nameStyle, innerW);
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role.trim() : '';
    if (role.isNotEmpty) {
      h += 5 + paintH(role, roleStyle, innerW, maxLines: 1);
    }
    h += 7;
    final geo = _resumeGeoDisplayLine(data);
    final contacts = <String>[
      if (data.email.trim().isNotEmpty) data.email.trim(),
      if (data.phone.trim().isNotEmpty) data.phone.trim(),
      if (geo.isNotEmpty) geo,
    ];
    if (contacts.isNotEmpty) {
      const rowH = ResumeTypography.body * 1.15 + 6;
      var rowW = 0.0;
      var rows = 1.0;
      for (final c in contacts) {
        final w = math.min(innerW * 0.92, c.length * 6.2 + 28);
        if (rowW > 0 && rowW + 10 + w > innerW) {
          rows += 1;
          rowW = w;
        } else {
          rowW += rowW > 0 ? 10 + w : w;
        }
      }
      h += rows * rowH + (rows - 1) * 5;
    }
    return h.clamp(_kTemplate1BannerHeight, 132.0);
  }

  List<_ResumePreviewPageData> _paginate(
    List<Map<String, dynamic>> layout, {
    required double pageHeight,
    required double rightWidth,
    required String templateId,
    required AppLocalizations l10n,
    String? bodyFontFamily,
    double template1BannerHeight = _kTemplate1BannerHeight,
  }) {
    // Right content (sections)
    var right = layout
        .where((s) => s["type"] != "header")
        .toList();

    final skills = data.skills.where((s) => s.trim().isNotEmpty).toList();
    final languagesRaw =
        (data.categories["Languages"] ?? const <String>[])
            .where((s) => s.trim().isNotEmpty)
            .toList();
    final languages = languagesRaw
        .map(CategoryEntryDisplay.normalizeLanguageStorage)
        .where((s) => s.trim().isNotEmpty)
        .map(
          (s) => CategoryEntryDisplay.formatLanguage(
            s,
            l10n.languageProficiencyLabel,
          ),
        )
        .toList();
    final links =
        (data.categories["Links"] ?? const <String>[])
            .where((s) => s.trim().isNotEmpty)
            .toList();
    final education = data.educationList
        .where((e) =>
            e.degree.trim().isNotEmpty ||
            e.institution.trim().isNotEmpty ||
            e.year.trim().isNotEmpty)
        .toList();
    final sidebarCategoryExclude = <String>{
      "Languages",
      "Links",
      if (templateId == "1") ...{
        "Projects",
        "Achievements",
        "City",
        "Country",
        "Location",
        "Frameworks",
        "Cloud/Databases/Tech-Stack",
        "Cloud",
        "Databases",
        "Courses",
        "Certifications",
        "References",
      },
      if (templateId == "2") ...{
        "References",
        "Certifications",
        "City",
        "Country",
        "Location",
      },
    };
    final otherLines = <String>[
      for (final entry in data.categories.entries)
        if (!sidebarCategoryExclude.contains(entry.key) &&
            entry.value.isNotEmpty)
          for (final v in entry.value)
            if (v.trim().isNotEmpty) "${entry.key}: $v",
    ];

    // We keep DETAILS + LINKS only on the first page like the reference.
    // SKILLS/EDUCATION/LANGUAGES/OTHER continue across pages.
    int skillIndex = 0;
    int educationIndex = 0;
    int languageIndex = 0;
    int otherIndex = 0;
    int rightIndex = 0;

    final pages = <_ResumePreviewPageData>[];

    // Keep the heuristics tied to the actual rendered page height.
    final sidebarPadTop = templateId == "2" ? 18.0 : 22.0;
    final sidebarPadBottom = templateId == "2" ? 16.0 : 18.0;
    const rightPadTop = 26.0;
    const rightPadBottom = 26.0;
    // Page badge sits in a fixed strip below the main Row (inside the white card).
    const pageFooterBar = 28.0;
    final bannerReserve = (templateId == "2" && pages.isEmpty) ? 82.0 : 0.0;
    final contentRegionHeight =
        pageHeight - bannerReserve - pageFooterBar;

    final sidebarInnerHeight =
        contentRegionHeight - sidebarPadTop - sidebarPadBottom;
    final rightInnerHeight =
        contentRegionHeight - rightPadTop - rightPadBottom;

    // Template 1 page 1: [_templateHeaderMinimalClassic] lives inside the same
    // ListView as sections — reserve ~its height, not an oversized guess, or pages
    // under-pack and show large empty bands.
    // Must match the actual rendered Template 1 top banner height (see build).
    final layoutFf = bodyFontFamily ?? 'Roboto';

    if (templateId == "1") {
      right = _splitTemplate1ListSections(right);
    } else if (templateId != "2") {
      final firstPageMainH = _mainColumnAvailHeight(
        pageIndex: 0,
        templateId: templateId,
        pageHeight: pageHeight,
        rightInnerHeight: rightInnerHeight,
        template1BannerHeight: template1BannerHeight,
      );
      final maxChunk = math.max(160.0, firstPageMainH - 20.0);
      right = _expandExperienceJobChunks(
        right,
        maxChunk,
        templateId: templateId,
        contentWidth: rightWidth,
        bodyFontFamily: layoutFf,
      );
    }

    // Template 1 is full-width: skills/education/languages live in [right], not the
    // sidebar. Never wait on sidebar slice indices for that template or take* stays 0
    // forever and this loop never terminates (OOM / Scudo "Lost connection").
    final singleColumn = templateId == "1";
    final packSidebar = !singleColumn;
    final t1ExpState =
        (templateId == "1" || templateId == "2") ? _T1ExperiencePageState() : null;

    while ((packSidebar && skillIndex < skills.length) ||
        (packSidebar && educationIndex < education.length) ||
        (packSidebar && languageIndex < languages.length) ||
        (packSidebar && otherIndex < otherLines.length) ||
        rightIndex < right.length ||
        pages.isEmpty) {
      // Sidebar packing (height-based) to prevent overflow on smaller screens.
      // These constants match the sidebar widget's paddings/spacings.
      final headerHeight = templateId == "2"
          ? 0.0
          : (110 + 16 + 22 + 10 + 18).toDouble();
      final detailsHeader = templateId == "2" ? 0.0 : 18.0;
      final detailsLine = templateId == "2" ? 20.0 : 16.0;
      final sectionHeader = templateId == "2" ? 22.0 : 20.0;
      final skillItem = templateId == "2" ? 18.0 : 22.0;
      final educationItem = templateId == "2" ? 62.0 : 48.0;
      final otherItem = 24.0;
      final safety = templateId == "2" ? 12.0 : 18.0;

      var remaining = sidebarInnerHeight - headerHeight - safety;
      if (pages.isEmpty && packSidebar && templateId != "2") {
        final visibleLinks = math.min(3, links.length);
        remaining -= detailsHeader;
        remaining -= detailsLine * (2 + visibleLinks);
        remaining -= 16; // spacer
      }

      if (packSidebar && templateId == "2" && pages.isEmpty) {
        // First-page sidebar only: photo + contact rows (not repeated on page 2+).
        remaining -= 78.0;
        var contactRows = 0;
        if (data.email.trim().isNotEmpty) contactRows++;
        if (data.phone.trim().isNotEmpty) contactRows++;
        final city = _firstCategoryLine(data, 'City');
        final country = _firstCategoryLine(data, 'Country');
        if (city.isEmpty && country.isEmpty) {
          if (_firstCategoryLine(data, 'Location').isNotEmpty) {
            contactRows++;
          }
        } else {
          if (city.isNotEmpty) contactRows++;
          if (country.isNotEmpty) contactRows++;
        }
        var linkedIn = false;
        for (final l in links) {
          if (l.toLowerCase().contains("linkedin")) {
            linkedIn = true;
            break;
          }
        }
        if (linkedIn) contactRows++;
        remaining -= detailsLine * contactRows;
        remaining -= 10;
      }

      int takeSkills = 0;
      int takeEducation = 0;
      int takeLangs = 0;
      int takeOther = 0;

      // Order: Skills, Education, Languages, Other (certifications are in the main column for template 2).
      // Template 2 page 1: fill vertically with as many skills as fit first; only add
      // education on page 1 once every skill fits on this page. If skills spill to
      // page 2+, education waits until those remaining skills are placed (then it
      // appears on the next page with leftover space, typically page 2).
      if (packSidebar &&
          skills.length > skillIndex &&
          remaining > sectionHeader + 8 + skillItem) {
        remaining -= sectionHeader + 8; // SKILLS header
        takeSkills = math.min(
          skills.length - skillIndex,
          math.max(0, (remaining / skillItem).floor()),
        );
        remaining -= takeSkills * skillItem;
        remaining -= 8;
      }

      if (packSidebar &&
          education.length > educationIndex &&
          remaining > sectionHeader + educationItem) {
        // Only defer when this page actually consumed at least one skill line but
        // not the full list (long list → fill page 1 with skills, education next page).
        // If even one skill line does not fit (`takeSkills == 0`), do not defer or
        // sidebar indices never advance.
        final t2Page1SkillsStillRemain = templateId == "2" &&
            pages.isEmpty &&
            takeSkills > 0 &&
            (skillIndex + takeSkills < skills.length);
        if (!t2Page1SkillsStillRemain) {
          remaining -= sectionHeader + 8;
          takeEducation = math.min(
            education.length - educationIndex,
            math.max(0, (remaining / educationItem).floor()),
          );
          remaining -= takeEducation * educationItem;
          remaining -= 8;
        }
      }

      if (packSidebar &&
          languages.length > languageIndex &&
          remaining > sectionHeader + 8 + skillItem) {
        remaining -= sectionHeader + 8; // LANGUAGES header
        takeLangs = math.min(
          languages.length - languageIndex,
          math.max(0, (remaining / skillItem).floor()),
        );
        remaining -= takeLangs * skillItem;
        remaining -= 8;
      }

      if (packSidebar &&
          otherLines.length > otherIndex &&
          remaining > sectionHeader + otherItem) {
        remaining -= sectionHeader + 8;
        takeOther = math.min(
          otherLines.length - otherIndex,
          math.max(0, (remaining / otherItem).floor()),
        );
      }

      final rightAvailHeight = _mainColumnAvailHeight(
        pageIndex: pages.length,
        templateId: templateId,
        pageHeight: pageHeight,
        rightInnerHeight: rightInnerHeight,
        template1BannerHeight: template1BannerHeight,
      );
      final layoutFont = bodyFontFamily ?? 'Roboto';
      late final List<Map<String, dynamic>> pageRightSections;
      late final int nextRightIndex;

      if (templateId == "1" || templateId == "2") {
        final taken = _takeTemplatePageRightSections(
          right: right,
          startIndex: rightIndex,
          availHeight: rightAvailHeight,
          contentWidth: rightWidth,
          bodyFontFamily: layoutFont,
          expState: t1ExpState!,
          templateId: templateId,
        );
        pageRightSections = taken.sections;
        nextRightIndex = taken.nextIndex;
      } else {
        final rightCap = ResumePreviewLayoutMetrics.fitSectionCount(
          sections: right.sublist(rightIndex),
          availHeight: rightAvailHeight,
          contentWidth: rightWidth,
          fontFamily: layoutFont,
          templateId: templateId,
        );
        var takeRight = math.min(rightCap, right.length - rightIndex);
        if (takeRight == 0 && rightIndex < right.length) {
          takeRight = 1;
        }
        pageRightSections = right.sublist(rightIndex, rightIndex + takeRight);
        nextRightIndex = rightIndex + takeRight;
      }

      pages.add(
        _ResumePreviewPageData(
          showDetails: pages.isEmpty,
          links: pages.isEmpty ? links : const [],
          skills: skills.sublist(skillIndex, skillIndex + takeSkills),
          education:
              education.sublist(educationIndex, educationIndex + takeEducation),
          certifications: const <String>[],
          languages:
              languages.sublist(languageIndex, languageIndex + takeLangs),
          otherLines:
              otherLines.sublist(otherIndex, otherIndex + takeOther),
          rightSections: pageRightSections,
        ),
      );

      skillIndex += takeSkills;
      educationIndex += takeEducation;
      languageIndex += takeLangs;
      otherIndex += takeOther;
      rightIndex = nextRightIndex;
    }

    return pages;
  }

  Widget _sidebar(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Template-specific sidebars for photo-matching.
    if (style.id == "2") {
      return _sidebarTemplate2(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "3") {
      return _sidebarTemplate3(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "4") {
      return _sidebarTemplate4(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "5") {
      return _sidebarTemplate5(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "6") {
      return _sidebarTemplate6(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "7") {
      return _sidebarTemplate7(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "8") {
      return _sidebarTemplate8(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "9") {
      return _sidebarTemplate9(page, sidebarWidth: sidebarWidth, style: style);
    }
    if (style.id == "10") {
      return _sidebarTemplate10(page, sidebarWidth: sidebarWidth, style: style);
    }

    final role = data.experiences.isNotEmpty ? data.experiences.first.role : "";
    final compact = sidebarWidth < 165;
    final avatar = compact ? 84.0 : 110.0;

    return Container(
      decoration: BoxDecoration(
        color: style.sidebarSolidColor,
        gradient: style.sidebarGradient,
      ),
      padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 18, compact ? 12 : 18, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            Container(
              width: avatar,
              height: avatar,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: style.sidebarOnColor.withOpacity(0.35)),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: (data.profileImage != null &&
                          File(data.profileImage!.path).existsSync())
                      ? Image.file(
                          File(data.profileImage!.path),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: style.sidebarOnColor.withOpacity(0.08),
                          child: Icon(
                            Icons.person,
                            color: style.sidebarOnColor,
                            size: 30,
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
          ],
          Text(
            data.name.isNotEmpty ? data.name : "Your Name",
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ResumeTypography.nameStyle(
              _nameFf,
              color: style.sidebarOnColor,
              height: 1.1,
            ),
          ),
          if (role.trim().isNotEmpty) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              role,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ResumeTypography.bodyStyle(
                _bodyFf,
                color: style.sidebarOnColor.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          SizedBox(height: compact ? 8 : 10),
          Container(
            width: 22,
            height: 1,
            color: style.sidebarOnColor.withOpacity(0.35),
          ),
          SizedBox(height: compact ? 14 : 18),
          if (page.showDetails) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _sideTitle(
                style.id == "2" || style.id == "6" ? "CONTACT" : "DETAILS",
                style,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _sideLine(data.email, style),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _sideLine(data.phone, style),
            ),
            for (final link in page.links)
              Align(
                alignment: Alignment.centerLeft,
                child: _sideLine(link, style),
              ),
            const SizedBox(height: 16),
          ],
          if (page.skills.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _sideTitle(
                style.id == "2" ? "EXPERTISE" : "SKILLS",
                style,
              ),
            ),
            const SizedBox(height: 8),
            for (final s in page.skills) ...[
              _skillBar(s, style),
              const SizedBox(height: 6),
            ],
          ],
          if (page.education.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _sideTitle("EDUCATION", style),
            ),
            for (final e in page.education) ...[
              _educationItem(e, style),
              const SizedBox(height: 10),
            ],
          ],
          if (page.languages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _sideTitle(
                style.id == "2" ? "LANGUAGE" : "LANGUAGES",
                style,
              ),
            ),
            const SizedBox(height: 8),
            for (final l in page.languages) ...[
              _skillBar(l, style),
              const SizedBox(height: 6),
            ],
          ],
          if (page.otherLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _sideTitle("OTHER", style),
            ),
            for (final line in page.otherLines)
              Align(
                alignment: Alignment.centerLeft,
                child: _sideLine(line, style),
              ),
          ],
        ],
      ),
    );
  }

  Widget _template2SidebarPhoto(_TemplateStyle style, {required bool compact}) {
    final size = compact ? 54.0 : 62.0;
    final hasUser = data.profileImage != null &&
        File(data.profileImage!.path).existsSync();
    final Widget image = hasUser
        ? Image.file(
            File(data.profileImage!.path),
            fit: BoxFit.cover,
          )
        : Image.asset(
            _template2SelectionThumbAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.grey.shade300),
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: style.accent.withOpacity(0.85), width: 2),
      ),
      child: ClipOval(child: image),
    );
  }

  Widget _sidebarTemplate2(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Emerson reference: white sidebar, gold circular icons, framed EDUCATION header.
    final compact = sidebarWidth < 170;
    final pad = compact ? 12.0 : 14.0;
    final city = _firstCategoryLine(data, 'City');
    final country = _firstCategoryLine(data, 'Country');
    final legacyGeo = (city.isEmpty && country.isEmpty)
        ? _firstCategoryLine(data, 'Location')
        : '';

    String? linkedInDisplay;
    String? linkedInUrl;
    for (final l in page.links) {
      final t = l.trim();
      if (t.toLowerCase().contains("linkedin")) {
        linkedInUrl = t;
        linkedInDisplay = t
            .replaceFirst(RegExp(r'^https?://(www\.)?linkedin\.com/in/', caseSensitive: false), '')
            .replaceAll('/', '');
        if (linkedInDisplay.trim().isEmpty) linkedInDisplay = t;
        break;
      }
    }

    Widget goldIcon(IconData icon) => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: style.accent.withOpacity(0.85), width: 1.2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 10, color: style.accent),
        );

    Widget contactRow(IconData icon, String text) {
      if (text.trim().isEmpty) return const SizedBox.shrink();
      final uri = _contactLaunchUri(icon, text);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _tappableContactRow(
          uri: uri,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              goldIcon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    color: style.sidebarOnColor.withOpacity(0.92),
                    fontSize: ResumeTypography.body,
                    height: 1.25,
                    decoration: uri == null ? null : TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget sectionTitle(String t) => Text(
          t.toUpperCase(),
          style: TextStyle(
            fontFamily: _bodyFf,
            color: style.sidebarOnColor.withOpacity(0.92),
            fontSize: ResumeTypography.heading,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
            height: 1.0,
          ),
        );

    Widget framedEducationTitle() => Row(
          children: [
            Expanded(child: Container(height: 1, color: const Color(0xFF9CA3AF))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: sectionTitle("EDUCATION"),
            ),
            Expanded(child: Container(height: 1, color: const Color(0xFF9CA3AF))),
          ],
        );

    Widget educationBlock(Education e) {
      final deg = e.degree.trim();
      final inst = e.institution.trim();
      final yr = e.year.trim();
      final pieces = deg
          .split(RegExp(r'[•\n;]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final concentration =
          pieces.length > 1 ? pieces.sublist(1).join(" • ") : "";

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pieces.isNotEmpty)
              Text(
                pieces.first.toUpperCase(),
                style: TextStyle(
                  fontFamily: _bodyFf,
                  color: style.sidebarOnColor,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  height: 1.15,
                ),
              ),
            if (concentration.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                concentration,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  color: style.sidebarOnColor.withOpacity(0.78),
                  fontSize: ResumeTypography.body,
                  height: 1.25,
                ),
              ),
            ],
            if (inst.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                inst,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  color: style.sidebarOnColor.withOpacity(0.78),
                  fontSize: ResumeTypography.body,
                  height: 1.2,
                ),
              ),
            ],
            if (yr.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                yr,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  color: style.sidebarOnColor.withOpacity(0.70),
                  fontSize: ResumeTypography.body,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      color: style.sidebarSolidColor ?? Colors.white,
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 14),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            Center(child: _template2SidebarPhoto(style, compact: compact)),
            const SizedBox(height: 10),
            if (data.email.trim().isNotEmpty)
              contactRow(Icons.email_outlined, data.email.trim()),
            if (data.phone.trim().isNotEmpty)
              contactRow(Icons.phone_outlined, data.phone.trim()),
            if (city.isNotEmpty) contactRow(Icons.home_outlined, city),
            if (country.isNotEmpty) contactRow(Icons.public_outlined, country),
            if (city.isEmpty &&
                country.isEmpty &&
                legacyGeo.isNotEmpty)
              contactRow(Icons.home_outlined, legacyGeo),
            if (linkedInDisplay != null && linkedInUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _tappableContactRow(
                  uri: () {
                    final raw = linkedInUrl!.trim();
                    final direct = Uri.tryParse(raw);
                    if (direct != null &&
                        direct.hasScheme &&
                        (direct.scheme == 'http' || direct.scheme == 'https')) {
                      return direct;
                    }
                    return Uri.tryParse('https://$raw');
                  }(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      goldIcon(Icons.link_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          linkedInDisplay,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: _bodyFf,
                            color: style.sidebarOnColor.withOpacity(0.92),
                            fontSize: ResumeTypography.body,
                            height: 1.25,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ] else ...[
            const SizedBox(height: 6),
          ],
          if (page.skills.isNotEmpty) ...[
            sectionTitle("SKILLS"),
            const SizedBox(height: 8),
            for (final s in page.skills)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  s,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    color: style.sidebarOnColor.withOpacity(0.88),
                    fontSize: ResumeTypography.body,
                    height: 1.2,
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (data.educationList.isNotEmpty) ...[
            framedEducationTitle(),
            const SizedBox(height: 10),
            if (page.education.isNotEmpty)
              for (final e in page.education) educationBlock(e),
          ],
          if (page.languages.isNotEmpty) ...[
            const SizedBox(height: 12),
            sectionTitle("LANGUAGES"),
            const SizedBox(height: 8),
            for (final l in page.languages)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  l,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    color: style.sidebarOnColor.withOpacity(0.86),
                    fontSize: ResumeTypography.body,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate3(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Larry Tibbetts reference: teal sidebar with icon contact + section pill headings.
    final compact = sidebarWidth < 175;
    final avatar = compact ? 64.0 : 78.0;
    final hobbies =
        (data.categories["Hobbies"] ?? const <String>[]).where((s) => s.trim().isNotEmpty).toList();

    Widget pill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: style.accent.withOpacity(0.7), width: 1.2),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: style.sidebarOnColor.withOpacity(0.9),
              fontSize: ResumeTypography.body,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(gradient: style.sidebarGradient),
      child: Stack(
        children: [
          // Gold outline circles (like the reference).
          Positioned(
            left: -46,
            top: 36,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: style.accent.withOpacity(0.55), width: 2),
              ),
            ),
          ),
          Positioned(
            left: -62,
            bottom: -32,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: style.accent.withOpacity(0.45), width: 2),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              16,
              compact ? 12 : 16,
              14,
            ),
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
          if (page.showDetails) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: avatar,
                height: avatar,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: style.accent.withOpacity(0.8), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: (data.profileImage != null &&
                          File(data.profileImage!.path).existsSync())
                      ? Image.file(File(data.profileImage!.path),
                          fit: BoxFit.cover)
                      : Container(color: Colors.white.withOpacity(0.08)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _iconLine(Icons.phone, data.phone, style),
            _iconLine(Icons.email, data.email, style),
            for (final link in page.links.take(1))
              _iconLine(Icons.link, link, style),
            const SizedBox(height: 12),
          ],
          if (page.skills.isNotEmpty) ...[
            Center(child: pill("SKILLS")),
            const SizedBox(height: 8),
            for (final s in page.skills.take(8)) _bulletLine(s, style),
            const SizedBox(height: 12),
          ],
          if (page.languages.isNotEmpty) ...[
            Center(child: pill("LANGUAGES")),
            const SizedBox(height: 8),
            for (final l in page.languages.take(5)) _bulletLine(l, style),
            const SizedBox(height: 12),
          ],
          if (hobbies.isNotEmpty) ...[
            Center(child: pill("HOBBIES")),
            const SizedBox(height: 8),
            for (final h in hobbies.take(4)) _bulletLine(h, style),
          ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarTemplate4(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Austin Bronson reference: left photo + skill bars; ABOUT ME lives on the right column.
    final compact = sidebarWidth < 180;
    final photoH = compact ? 150.0 : 190.0;
    final showPhoto = page.showDetails;
    const t4SidebarStyle = _TemplateStyle(
      id: "4x",
      sidebarGradient: null,
      sidebarSolidColor: null,
      sidebarOnColor: Color(0xFFEFEFEF),
      accent: Color(0xFFF3C300),
      titleStyle: _TitleStyle.underline,
      sidebarPlacement: _SidebarPlacement.left,
    );

    return Container(
      color: const Color(0xFF1C1C1C),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (showPhoto)
            SizedBox(
              height: photoH,
              width: double.infinity,
              child: (data.profileImage != null &&
                      File(data.profileImage!.path).existsSync())
                  ? Image.file(File(data.profileImage!.path), fit: BoxFit.cover)
                  : Container(color: Colors.white.withOpacity(0.06)),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 18,
              18,
              compact ? 14 : 18,
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.skills.isNotEmpty) ...[
                  Text(
                    "SKILLS",
                    style: ResumeTypography.headingStyle(
                      _bodyFf,
                      color: Colors.white.withOpacity(0.55),
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final s in page.skills.take(10))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _skillBar(s, t4SidebarStyle, maxLabelLines: 2),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Uri? _contactLaunchUri(IconData icon, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    // Already a URL / scheme.
    if (t.contains('://') || t.startsWith('mailto:') || t.startsWith('tel:')) {
      return Uri.tryParse(t);
    }

    if (t.contains('@')) {
      return Uri(scheme: 'mailto', path: t);
    }

    // Phone-ish
    if (icon == Icons.phone ||
        icon == Icons.phone_outlined ||
        RegExp(r'\+?\d[\d\s().-]{8,}').hasMatch(t)) {
      final digits = t.replaceAll(RegExp(r'[^\d+]'), '');
      if (digits.isEmpty) return null;
      return Uri(scheme: 'tel', path: digits);
    }

    // Web-ish
    if (icon == Icons.language ||
        icon == Icons.insert_link ||
        t.toLowerCase().contains('linkedin') ||
        t.toLowerCase().startsWith('www.')) {
      final normalized = t.startsWith('http') ? t : 'https://$t';
      return Uri.tryParse(normalized);
    }

    // Location-ish (best effort)
    if (icon == Icons.location_on_outlined ||
        icon == Icons.home_outlined ||
        icon == Icons.public_outlined) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t)}',
      );
    }

    return null;
  }

  Future<void> _launchUriMaybe(Uri? uri) async {
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ignore launch failures in preview.
    }
  }

  Widget _tappableContactRow({
    required Widget child,
    required Uri? uri,
  }) {
    if (uri == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _launchUriMaybe(uri),
        child: child,
      ),
    );
  }

  Widget _iconLine(IconData icon, String text, _TemplateStyle style) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final uri = _contactLaunchUri(icon, text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _tappableContactRow(
        uri: uri,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: style.sidebarOnColor.withOpacity(0.85)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.sidebarOnColor.withOpacity(0.78),
                  fontSize: ResumeTypography.body,
                  height: 1.25,
                  decoration: uri == null ? null : TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulletLine(String text, _TemplateStyle style) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 6),
      child: Text(
        "• $text",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: style.sidebarOnColor.withOpacity(0.82),
          fontSize: ResumeTypography.body,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _sidebarTemplate5(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Jonathan Patterson reference: light grey panel with EDUCATION/SKILLS/LANGUAGES/CONTACT.
    return Container(
      color: const Color(0xFFE5E5E5),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.55),
                  border: Border.all(color: Colors.white, width: 8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: (data.profileImage != null &&
                          File(data.profileImage!.path).existsSync())
                      ? Image.file(File(data.profileImage!.path),
                          fit: BoxFit.cover)
                      : Container(color: Colors.black.withOpacity(0.05)),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (page.education.isNotEmpty) ...[
            _sideTitle("EDUCATION", style),
            for (final e in page.education.take(3)) ...[
              _educationItem(e, style),
              const SizedBox(height: 10),
            ],
          ],
          if (page.skills.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sideTitle("SKILLS", style),
            for (final s in page.skills.take(10)) _bulletLine(s, style),
          ],
          if (page.languages.isNotEmpty) ...[
            const SizedBox(height: 10),
            _sideTitle("LANGUAGES", style),
            for (final l in page.languages.take(6)) _bulletLine(l, style),
          ],
          if (page.showDetails) ...[
            const SizedBox(height: 10),
            _sideTitle("CONTACT", style),
            _iconLine(Icons.phone, data.phone, style),
            _iconLine(Icons.email, data.email, style),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate6(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Richard Sanchez reference: teal left with CONTACT/EDUCATION/SKILLS/LANGUAGES.
    return Container(
      decoration: BoxDecoration(gradient: style.sidebarGradient),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: (data.profileImage != null &&
                          File(data.profileImage!.path).existsSync())
                      ? Image.file(File(data.profileImage!.path),
                          fit: BoxFit.cover)
                      : Container(color: Colors.white.withOpacity(0.08)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _sideTitle("CONTACT", style),
            _iconLine(Icons.phone, data.phone, style),
            _iconLine(Icons.email, data.email, style),
            for (final link in page.links.take(1))
              _iconLine(Icons.link, link, style),
            const SizedBox(height: 12),
          ],
          if (page.education.isNotEmpty) ...[
            _sideTitle("EDUCATION", style),
            for (final e in page.education.take(3)) ...[
              _educationItem(e, style),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
          if (page.skills.isNotEmpty) ...[
            _sideTitle("SKILLS", style),
            for (final s in page.skills.take(10)) _bulletLine(s, style),
            const SizedBox(height: 10),
          ],
          if (page.languages.isNotEmpty) ...[
            _sideTitle("LANGUAGES", style),
            for (final l in page.languages.take(6)) _bulletLine(l, style),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate7(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Martiens Pitters reference: dark panels with icon labels.
    Widget panelTitle(IconData icon, String t) => Row(
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 8),
            Text(
              t,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: ResumeTypography.body,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        );

    return Container(
      decoration: BoxDecoration(gradient: style.sidebarGradient),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.languages.isNotEmpty) ...[
            panelTitle(Icons.translate, "LANGUAGES"),
            const SizedBox(height: 8),
            for (final l in page.languages.take(5)) ...[
              _skillBar(l, style),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
          if (page.skills.isNotEmpty) ...[
            panelTitle(Icons.star, "SKILLS"),
            const SizedBox(height: 8),
            for (final s in page.skills.take(6)) ...[
              _skillBar(s, style),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate8(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Will Tribianni reference: clean left with contact bar feel.
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            Text(
              "CONTACT",
              style: TextStyle(
                fontSize: ResumeTypography.body,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 10),
            _iconLine(Icons.email, data.email, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            _iconLine(Icons.phone, data.phone, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            const SizedBox(height: 12),
          ],
          if (page.skills.isNotEmpty) ...[
            _sideTitle("HARD SKILLS", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.start,
              children: page.skills
                  .take(12)
                  .map((s) => _chip(s, style.accent))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (page.education.isNotEmpty) ...[
            _sideTitle("EDUCATION", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            for (final e in page.education.take(2)) ...[
              _educationItem(e, _TemplateStyle(
                id: style.id,
                sidebarGradient: null,
                sidebarSolidColor: null,
                sidebarOnColor: const Color(0xFF111827),
                accent: style.accent,
                titleStyle: style.titleStyle,
                sidebarPlacement: style.sidebarPlacement,
              )),
              const SizedBox(height: 10),
            ],
          ],
          if (page.languages.isNotEmpty) ...[
            _sideTitle("LANGUAGES", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            for (final l in page.languages.take(4)) _bulletLine(l, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate9(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Jessica Blakely reference: dark header style; keep sidebar minimal.
    return Container(
      decoration: BoxDecoration(gradient: style.sidebarGradient),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            _sideTitle("CONTACT", style),
            _iconLine(Icons.email, data.email, style),
            _iconLine(Icons.phone, data.phone, style),
            const SizedBox(height: 10),
          ],
          if (page.skills.isNotEmpty) ...[
            _sideTitle("SKILLS", style),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: page.skills
                  .take(12)
                  .map((s) => _chip(s, style.accent, on: style.sidebarOnColor))
                  .toList(),
            ),
          ],
          if (page.languages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sideTitle("LANGUAGES", style),
            for (final l in page.languages.take(4)) _bulletLine(l, style),
          ],
        ],
      ),
    );
  }

  Widget _sidebarTemplate10(
    _ResumePreviewPageData page, {
    required double sidebarWidth,
    required _TemplateStyle style,
  }) {
    // Mobile screenshot: light left panel with personal info/links/education/skills.
    return Container(
      color: const Color(0xFFE5E7EB),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (page.showDetails) ...[
            _sideTitle("Personal Info", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            _iconLine(Icons.email, data.email, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            _iconLine(Icons.phone, data.phone, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            const SizedBox(height: 10),
          ],
          if (page.links.isNotEmpty) ...[
            _sideTitle("Links", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            for (final l in page.links.take(2))
              _sideLine(l, _TemplateStyle(
                id: style.id,
                sidebarGradient: null,
                sidebarSolidColor: null,
                sidebarOnColor: const Color(0xFF111827),
                accent: style.accent,
                titleStyle: style.titleStyle,
                sidebarPlacement: style.sidebarPlacement,
              )),
            const SizedBox(height: 10),
          ],
          if (page.education.isNotEmpty) ...[
            _sideTitle("Education", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            for (final e in page.education.take(2)) ...[
              _educationItem(e, _TemplateStyle(
                id: style.id,
                sidebarGradient: null,
                sidebarSolidColor: null,
                sidebarOnColor: const Color(0xFF111827),
                accent: style.accent,
                titleStyle: style.titleStyle,
                sidebarPlacement: style.sidebarPlacement,
              )),
              const SizedBox(height: 10),
            ],
          ],
          if (page.skills.isNotEmpty) ...[
            _sideTitle("Skills", _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
            for (final s in page.skills.take(8)) _bulletLine(s, _TemplateStyle(
              id: style.id,
              sidebarGradient: null,
              sidebarSolidColor: null,
              sidebarOnColor: const Color(0xFF111827),
              accent: style.accent,
              titleStyle: style.titleStyle,
              sidebarPlacement: style.sidebarPlacement,
            )),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color accent, {Color? on}) {
    final fg = on ?? const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.visible,
        softWrap: true,
        style: TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: fg.withOpacity(0.85),
        ),
      ),
    );
  }

  Widget _educationItem(Education e, _TemplateStyle style) {
    final top = [
      if (e.degree.trim().isNotEmpty) e.degree.trim(),
      if (e.institution.trim().isNotEmpty) e.institution.trim(),
    ].join(", ");
    final year = e.year.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top.isNotEmpty)
          Text(
            top,
            maxLines: 4,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: _bodyFf,
              color: style.sidebarOnColor.withOpacity(0.88),
              fontSize: ResumeTypography.body,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (year.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            year,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.sidebarOnColor.withOpacity(0.70),
              fontSize: ResumeTypography.body,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _sideTitle(String text, _TemplateStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: ResumeTypography.headingStyle(
          _bodyFf,
          color: style.sidebarOnColor.withOpacity(0.9),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _sideLine(String text, _TemplateStyle style) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: style.sidebarOnColor.withOpacity(0.78),
          fontSize: ResumeTypography.body,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _skillBar(
    String label,
    _TemplateStyle style, {
    int maxLabelLines = 1,
  }) {
    final base = (label.hashCode % 50) + 45; // 45..94
    final value = base / 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: maxLabelLines,
          overflow: maxLabelLines > 1
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: _bodyFf,
            color: style.sidebarOnColor.withOpacity(0.85),
            fontSize: ResumeTypography.body,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 2.5,
            backgroundColor: style.sidebarOnColor.withOpacity(0.18),
            valueColor: AlwaysStoppedAnimation(style.sidebarOnColor.withOpacity(0.9)),
          ),
        ),
      ],
    );
  }

  /// Template 2: bullet, or labeled line (Client:, Defect Management Tool:, etc.).
  Widget _template2ExperienceLine(String line, TextStyle bodyStyle) {
    final t = line.trim();
    if (t.isEmpty) return const SizedBox.shrink();

    if (ExperienceDisplay.looksLikeResponsibilitiesHeading(t)) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          t.endsWith(':') ? t : '$t:',
          style: ResumeTypography.headingStyle(
            _bodyFf,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: const Color(0xFF111827),
            height: 1.2,
          ),
        ),
      );
    }

    final colon = t.indexOf(':');
    if (colon > 0 && colon < 48 && ExperienceDisplay.looksLikeMetaLine(t)) {
      final label = t.substring(0, colon + 1);
      final rest = t.substring(colon + 1).trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text.rich(
          TextSpan(
            style: bodyStyle,
            children: [
              TextSpan(
                text: label,
                style: bodyStyle.copyWith(fontWeight: FontWeight.w800),
              ),
              if (rest.isNotEmpty) TextSpan(text: ' $rest'),
            ],
          ),
          textAlign: TextAlign.justify,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        t.startsWith('•') ? t : '• $t',
        textAlign: TextAlign.justify,
        style: bodyStyle,
      ),
    );
  }

  /// Hanging-indent bullet row for template 1 body copy.
  Widget _template1Bullet(String text, TextStyle style) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5, right: 6),
            child: Text(
              '•',
              style: style.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              t,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _template1SkillValueWrap(
    String raw,
    TextStyle chipStyle, {
    Color? accent,
  }) {
    final t = raw.trim();
    final parts = t.isEmpty
        ? const <String>[]
        : (_splitSkillListValue(t).isNotEmpty ? _splitSkillListValue(t) : <String>[t]);
    const bg = Color(0xFFF1F5F9);
    final borderColor = (accent ?? const Color(0xFF1E40AF)).withOpacity(0.22);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final part in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: 0.75),
            ),
            child: Text(
              part,
              style: chipStyle.copyWith(
                fontSize: ResumeTypography.body,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: 0.05,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    Map<String, dynamic> section,
    _TemplateStyle style,
  ) {
    final bodyStyle = ResumeTypography.bodyStyle(
      _bodyFf,
      color: const Color(0xFF0F172A),
    );
    final bodyStyleLight = ResumeTypography.bodyStyle(
      _bodyFf,
      color: Colors.black.withOpacity(0.70),
      height: ResumeTypography.lineHeightTight,
    );
    switch (section["type"]) {
      case "header":
        // Header is handled by the sidebar in this template.
        return const SizedBox.shrink();

      case "section":
        final contentStr = (section["content"] ?? "").toString().trim();
        if (contentStr.isEmpty) {
          return const SizedBox.shrink();
        }

        // Template 3 shows summary in the header ribbon only.
        final titleLower = section["title"].toString().toLowerCase();
        if (style.id == "3" &&
            (titleLower.contains("profile") ||
                titleLower.contains("summary"))) {
          return const SizedBox.shrink();
        }

        final sectionPadBottom = style.id == "1" ? 12.0 : 18.0;
        final isProfileSummary = titleLower.contains("profile") ||
            titleLower.contains("summary") ||
            titleLower.contains("about");
        final displayTitle = style.id == "4" && isProfileSummary
            ? "ABOUT ME"
            : (style.id == "3"
                ? section["title"].toString().toUpperCase()
                : section["title"].toString());
        return Padding(
          padding: EdgeInsets.only(bottom: sectionPadBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (style.id == "2")
                _contentTitleTemplate2(section["title"].toString(), style)
              else
                _contentTitle(displayTitle, style),
              SizedBox(height: style.id == "1" ? 8 : 10),
              Text(
                contentStr,
                textAlign: (style.id == "2" || style.id == "1")
                    ? TextAlign.justify
                    : TextAlign.start,
                maxLines: null,
                overflow: TextOverflow.visible,
                style: style.id == "1"
                    ? bodyStyle
                    : (style.id == "5" ? bodyStyleLight : bodyStyle),
              ),
            ],
          ),
        );

      case "experience":
        final items = (section["items"] as List?) ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();

        final heading = style.id == "1"
            ? "WORK EXPERIENCE"
            : (style.id == "2")
                ? "PROFESSIONAL EXPERIENCE"
                : (style.id == "4")
                    ? "EMPLOYMENT HISTORY"
                    : (style.id == "6"
                        ? "Work Experience"
                        : "Employment History");

        final t1ShowWorkHeading = (style.id == "1" || style.id == "2")
            ? (section["t1_show_work_heading"] as bool? ?? true)
            : true;
        final t1ShowJobHeader = (style.id == "1" || style.id == "2")
            ? (section["t1_show_job_header"] as bool? ?? true)
            : true;

        final expBlockPadBottom = style.id == "1" ? 4.0 : 18.0;
        return Padding(
          padding: EdgeInsets.only(bottom: expBlockPadBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (t1ShowWorkHeading) ...[
                if (style.id == "2")
                  _contentTitleTemplate2(heading, style)
                else
                  _contentTitle(heading, style),
                SizedBox(height: style.id == "1" ? 8 : 10),
              ],
              ...items.asMap().entries.map<Widget>((entry) {
                final exp = entry.value as Experience;
                final expIsLast = entry.key == items.length - 1;
                final bullets = _experienceBulletsDisplay(exp);
                if (style.id == "1") {
                  final t1Body = TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: ResumeTypography.body,
                    height: ResumeTypography.lineHeightBody,
                    color: const Color(0xFF1F2937),
                  );
                  final t1Muted = TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: ResumeTypography.body,
                    height: ResumeTypography.lineHeightTight,
                    color: const Color(0xFF4B5563),
                  );
                  final company = _experienceCompanyDisplay(exp);
                  final role = exp.role.trim();
                  final when = _experienceWhenDisplay(exp);
                  return Padding(
                    padding: EdgeInsets.only(bottom: expIsLast ? 0 : 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (style.id == "1"
                            ? (items.length > 1 || t1ShowJobHeader)
                            : t1ShowJobHeader) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  role,
                                  style: TextStyle(
                                    fontFamily: _bodyFf,
                                    fontSize: ResumeTypography.heading,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ),
                              if (when.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    when,
                                    textAlign: TextAlign.right,
                                    style: t1Muted.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (company.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              company,
                              style: t1Muted.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                        ] else
                          const SizedBox(height: 2),
                        if (bullets.isNotEmpty)
                          ...bullets.map((b) => _template1Bullet(b, t1Body)),
                        if (!expIsLast) ...[
                          const SizedBox(height: 5),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.black.withOpacity(0.07),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                if (style.id == "2") {
                  final role = exp.role.trim();
                  final when = _experienceWhenDisplay(exp);
                  final companyLine = _experienceCompanyDisplay(exp);

                  final split = ExperienceDisplay.splitIntroFromBullets(
                    bullets,
                    allowIntro: t1ShowJobHeader,
                  );
                  final intro = split.intro;
                  final bulletLines = split.bullets;

                  return Padding(
                    padding: EdgeInsets.only(bottom: expIsLast ? 0 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t1ShowJobHeader) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  role.toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: _bodyFf,
                                    fontSize: ResumeTypography.heading,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    height: 1.1,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ),
                              if (when.isNotEmpty)
                                Text(
                                  when,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFamily: _bodyFf,
                                    fontSize: ResumeTypography.body,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF4B5563),
                                    height: 1.1,
                                  ),
                                ),
                            ],
                          ),
                          if (companyLine.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              companyLine,
                              style: TextStyle(
                                fontFamily: _bodyFf,
                                fontSize: ResumeTypography.body,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: const Color(0xFF374151),
                              ),
                            ),
                          ],
                          if (intro != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              intro,
                              textAlign: TextAlign.justify,
                              style: bodyStyle.copyWith(
                                fontFamily: _bodyFf,
                                fontSize: ResumeTypography.body,
                                height: 1.35,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ],
                        if (bulletLines.isNotEmpty) ...[
                          SizedBox(height: intro == null ? 8 : 6),
                          for (final b in bulletLines)
                            _template2ExperienceLine(
                              b,
                              bodyStyleLight.copyWith(
                                fontFamily: _bodyFf,
                                fontSize: ResumeTypography.body,
                                color: const Color(0xFF374151),
                                height: 1.35,
                              ),
                            ),
                        ],
                        if (!expIsLast) ...[
                          const SizedBox(height: 12),
                          Container(height: 1, color: const Color(0xFFE5E7EB)),
                        ],
                      ],
                    ),
                  );
                }

                if (style.id == "3") {
                  // Template 3: uppercase job title, compact bullets.
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exp.role,
                          style: const TextStyle(
                            fontSize: ResumeTypography.heading,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: Color(0xFF0B2230),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final when = _experienceWhenDisplay(exp);
                            final co = _experienceCompanyDisplay(exp);
                            if (co.isNotEmpty && when.isNotEmpty) {
                              return '$co  |  $when';
                            }
                            return when.isNotEmpty ? when : co;
                          }(),
                          style: TextStyle(
                            fontSize: ResumeTypography.body,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withOpacity(0.55),
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final b in bullets)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 12, bottom: 4),
                            child: Text("• $b", style: bodyStyle),
                          ),
                      ],
                    ),
                  );
                }

                if (style.id == "5") {
                  // Timeline-style experience (Jonathan Patterson reference).
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.55),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              Container(
                                width: 2,
                                height: 76,
                                color: Colors.black.withOpacity(0.15),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      exp.role.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: ResumeTypography.heading,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _experienceWhenDisplay(exp),
                                    style: TextStyle(
                                      fontSize: ResumeTypography.body,
                                      letterSpacing: 1.0,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _experienceCompanyDisplay(exp),
                                style: TextStyle(
                                  fontSize: ResumeTypography.body,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black.withOpacity(0.60),
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (bullets.isNotEmpty)
                                ...bullets.map(
                                  (b) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text("• $b", style: bodyStyle),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          final co = _experienceCompanyDisplay(exp);
                          return co.isEmpty
                              ? exp.role.trim()
                              : '${exp.role.trim()}, $co';
                        }(),
                        style: const TextStyle(
                          fontSize: ResumeTypography.heading,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _experienceWhenDisplay(exp),
                        style: TextStyle(
                          fontSize: ResumeTypography.body,
                          letterSpacing: 1.0,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (bullets.isNotEmpty)
                        ...bullets.map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              "• $b",
                              style: bodyStyle,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );

      case "education":
        final eduItems = (section["items"] as List?) ?? const [];
        if (eduItems.isEmpty) return const SizedBox.shrink();

        if (style.id == "1") {
          final showEduHeading =
              (section["t1_show_section_heading"] as bool?) ?? true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showEduHeading) ...[
                  _contentTitle("EDUCATION", style),
                  const SizedBox(height: 8),
                ],
                ...eduItems.map<Widget>((e) {
                  final ed = e as Education;
                  final deg = ed.degree.trim();
                  final inst = ed.institution.trim();
                  final yr = ed.year.trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (deg.isNotEmpty)
                                Text(
                                  deg,
                                  style: TextStyle(
                                    fontFamily: _bodyFf,
                                    fontSize: ResumeTypography.body,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              if (inst.isNotEmpty) ...[
                                if (deg.isNotEmpty) const SizedBox(height: 2),
                                Text(
                                  inst,
                                  style: TextStyle(
                                    fontFamily: _bodyFf,
                                    fontSize: ResumeTypography.body,
                                    height: 1.3,
                                    color: Colors.black.withOpacity(0.68),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (yr.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              yr,
                              style: TextStyle(
                                fontFamily: _bodyFf,
                                fontSize: ResumeTypography.body,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle("EDUCATION", style),
              const SizedBox(height: 10),
              ...eduItems.map<Widget>((e) {
                final ed = e as Education;
                final line = [
                  ed.degree,
                  ed.institution,
                  ed.year,
                ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(" — ");
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    line.isNotEmpty ? line : " ",
                    style: style.id == "5" ? bodyStyleLight : bodyStyle,
                  ),
                );
              }),
            ],
          ),
        );

      case "projects":
        String formatProjectLine(String raw) {
          final t = raw.trim();
          if (t.isEmpty) return '';
          if (!t.contains(CategoryEntryDisplay.sep)) return t;
          final parts = t
              .split(CategoryEntryDisplay.sep)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (parts.isEmpty) return '';
          final name = parts[0];
          final duration = parts.length >= 2 ? parts[1] : '';
          final details = parts.length >= 3 ? parts.sublist(2).join(' ') : '';
          if (duration.isNotEmpty && details.isNotEmpty) return '$name — $duration: $details';
          if (duration.isNotEmpty) return '$name — $duration';
          if (details.isNotEmpty) return '$name: $details';
          return name;
        }

        final proj = (section["items"] as List?)
                ?.map((e) => formatProjectLine(e.toString()))
                .where((s) => s.trim().isNotEmpty)
                .toList() ??
            const <String>[];
        if (proj.isEmpty) return const SizedBox.shrink();
        final showProjHeading = style.id != "1" ||
            ((section["t1_show_section_heading"] as bool?) ?? true);
        final t1ListBody = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.36,
          color: const Color(0xFF1F2937),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showProjHeading) ...[
                _contentTitle("PROJECTS", style),
                SizedBox(height: style.id == "1" ? 8 : 10),
              ],
              if (style.id == "1")
                ...proj.map((line) => _template1Bullet(line, t1ListBody))
              else
                for (final line in proj)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text("• $line", style: bodyStyle),
                  ),
            ],
          ),
        );

      case "courses":
        final items = (section["items"] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final showCoursesHeading = style.id != "1" ||
            ((section["t1_show_section_heading"] as bool?) ?? true);
        final t1ListBody = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.36,
          color: const Color(0xFF1F2937),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCoursesHeading) ...[
                _contentTitle("COURSES", style),
                SizedBox(height: style.id == "1" ? 8 : 10),
              ],
              if (style.id == "1")
                ...items.map((line) => _template1Bullet(line, t1ListBody))
              else
                for (final line in items)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text("• $line", style: bodyStyle),
                  ),
            ],
          ),
        );

      case "languages":
        final items = (section["items"] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final t1ListBody = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.36,
          color: const Color(0xFF1F2937),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle("LANGUAGES", style),
              SizedBox(height: style.id == "1" ? 8 : 10),
              if (style.id == "1")
                ...items.map((line) => _template1Bullet(line, t1ListBody))
              else
                for (final line in items)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text("• $line", style: bodyStyle),
                  ),
            ],
          ),
        );

      case "certifications":
        final items = (section["items"] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final showCertsHeading = style.id != "1" ||
            ((section["t1_show_section_heading"] as bool?) ?? true);
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCertsHeading) ...[
                if (style.id == "2")
                  _contentTitleTemplate2("CERTIFICATIONS", style)
                else
                  _contentTitle("CERTIFICATIONS", style),
                SizedBox(height: style.id == "1" ? 8 : 10),
              ],
              if (style.id == "1")
                ...items.map(
                  (line) => _template1Bullet(
                    line,
                    TextStyle(
                      fontFamily: _bodyFf,
                      fontSize: ResumeTypography.body,
                      height: 1.36,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                )
              else
                for (final line in items)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text("• $line", style: bodyStyle),
                  ),
            ],
          ),
        );

      case "skills":
        final items = (section["items"] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final chipStyle = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.22,
          color: const Color(0xFF111111),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle("SKILLS", style),
              SizedBox(height: style.id == "1" ? 6 : 10),
              if (style.id == "1")
                _template1SkillValueWrap(
                  items.join(", "),
                  chipStyle,
                  accent: style.accent,
                )
              else
                Text(items.join(", "), style: bodyStyle),
            ],
          ),
        );

      case "skills_categorized":
        final groups = (section["groups"] as List?) ?? const [];
        if (groups.isEmpty) return const SizedBox.shrink();
        final chipStyle = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.22,
          color: const Color(0xFF111111),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle("SKILLS", style),
              SizedBox(height: style.id == "1" ? 6 : 10),
              for (final g in groups)
                if (g is Map)
                  Padding(
                    padding: EdgeInsets.only(bottom: style.id == "1" ? 8 : 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (g["label"] ?? "").toString().toUpperCase(),
                          style: ResumeTypography.headingStyle(
                            _bodyFf,
                            height: 1.15,
                            letterSpacing: 0.4,
                            color: const Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(height: 5),
                        if (style.id == "1")
                          _template1SkillValueWrap(
                            (g["value"] ?? "").toString(),
                            chipStyle,
                            accent: style.accent,
                          )
                        else
                          Text.rich(
                            TextSpan(
                              style: bodyStyle,
                              children: [
                                TextSpan(
                                  text: "${g["label"]}: ",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: (g["value"] ?? "").toString(),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        );

      case "achievement":
        final ach =
            (section["items"] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ??
                const <String>[];
        if (ach.isEmpty) return const SizedBox.shrink();
        final showAchHeading = style.id != "1" ||
            ((section["t1_show_section_heading"] as bool?) ?? true);
        final t1ListBody = TextStyle(
          fontFamily: _bodyFf,
          fontSize: ResumeTypography.body,
          height: 1.36,
          color: const Color(0xFF1F2937),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAchHeading) ...[
                _contentTitle("ACHIEVEMENTS", style),
                SizedBox(height: style.id == "1" ? 8 : 10),
              ],
              if (style.id == "1")
                ...ach.map(
                  (line) => _template1Bullet(
                    CategoryEntryDisplay.formatAchievementLine(line),
                    t1ListBody,
                  ),
                )
              else
                for (final line in ach)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      "• ${CategoryEntryDisplay.formatAchievementLine(line)}",
                      style: bodyStyle,
                    ),
                  ),
            ],
          ),
        );

      case "references":
        final refItems = (section["items"] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        if (refItems.isEmpty) return const SizedBox.shrink();

        Widget refCard(String block) {
          final lines = block
              .split(RegExp(r'\r?\n'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (lines.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lines[0],
                  style: const TextStyle(
                    fontSize: ResumeTypography.body,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF374151),
                  ),
                ),
                if (lines.length > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    lines[1],
                    style: TextStyle(
                      fontSize: ResumeTypography.body,
                      height: 1.3,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                for (var i = 2; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        fontSize: ResumeTypography.body,
                        height: 1.3,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final leftCol = <Widget>[];
        final rightCol = <Widget>[];
        for (var i = 0; i < refItems.length; i++) {
          final w = refCard(refItems[i]);
          if (i.isEven) {
            leftCol.add(w);
          } else {
            rightCol.add(w);
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: style.id == "1" ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle("REFERENCES", style),
              SizedBox(height: style.id == "1" ? 8 : 10),
              if (style.id == "1")
                ...refItems.map((block) {
                  final lines = block
                      .split(RegExp(r'\r?\n'))
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  if (lines.isEmpty) return const SizedBox.shrink();
                  final body = lines.length > 1 ? lines.sublist(1).join(' · ') : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lines[0],
                          style: TextStyle(
                            fontFamily: _bodyFf,
                            fontSize: ResumeTypography.body,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            body,
                            style: TextStyle(
                              fontFamily: _bodyFf,
                              fontSize: ResumeTypography.body,
                              height: 1.3,
                              color: Colors.black.withOpacity(0.62),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                })
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: leftCol)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(children: rightCol)),
                  ],
                ),
            ],
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _contentTitle(String text, _TemplateStyle style) {
    Color titleOnWhite(Color accent) {
      final lum = accent.computeLuminance();
      if (lum > 0.78) return const Color(0xFF111111);
      if (lum < 0.12) return const Color(0xFF111111);
      return Color.lerp(accent, const Color(0xFF0B1220), 0.55)!;
    }

    switch (style.titleStyle) {
      case _TitleStyle.fullRule:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text.toUpperCase(),
              style: ResumeTypography.headingStyle(
                _bodyFf,
                color: titleOnWhite(style.accent),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: style.id == "1" ? 3.5 : 2,
              decoration: BoxDecoration(
                color: style.id == "1"
                    ? style.accent
                    : style.accent.withOpacity(0.85),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        );
      case _TitleStyle.pill:
        final isTemplate3 = style.id == "3";
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isTemplate3
                ? const Color(0xFFE5E7EB)
                : style.accent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isTemplate3
                  ? Colors.black.withOpacity(0.12)
                  : style.accent.withOpacity(0.35),
            ),
          ),
          child: Text(
            text.toUpperCase(),
            style: ResumeTypography.headingStyle(
              _bodyFf,
              letterSpacing: isTemplate3 ? 1.6 : 1.2,
              color: const Color(0xFF0F172A),
            ),
          ),
        );
      case _TitleStyle.underline:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: ResumeTypography.headingStyle(
                _bodyFf,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: style.id == "1" ? 40 : 26,
              height: style.id == "1" ? 3 : 2,
              decoration: BoxDecoration(
                color: style.accent.withOpacity(style.id == "1" ? 1.0 : 0.35),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        );
    }
  }

  Widget _contentTitleTemplate2(String text, _TemplateStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.toUpperCase(),
          style: ResumeTypography.headingStyle(
            _bodyFf,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.6,
            color: const Color(0xFF111827),
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: const Color(0xFF9CA3AF)),
      ],
    );
  }

  /// Short line under the name only (summary lives in PROFESSIONAL SUMMARY section).
  String _headerTaglineTemplate1() {
    final parts = <String>[];
    if (data.experiences.isNotEmpty) {
      final r = data.experiences.first.role.trim();
      if (r.isNotEmpty) parts.add(r);
    }
    if (data.educationList.isNotEmpty) {
      final e = data.educationList.first;
      final d = e.degree.trim();
      final inst = e.institution.trim();
      if (d.isNotEmpty) parts.add(d);
      if (inst.isNotEmpty) parts.add(inst);
    }
    return parts.join(" | ");
  }

  Widget _template1TopBanner(Color accent) {
    final name = data.name.trim().isNotEmpty ? data.name.trim() : "Your Name";
    final role = data.experiences.isNotEmpty ? data.experiences.first.role.trim() : '';
    final email = data.email.trim();
    final phone = data.phone.trim();
    final geo = _resumeGeoDisplayLine(data);
    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    String? linkedInDisplay;
    String? linkedInUrl;
    for (final l in links) {
      if (l.toLowerCase().contains("linkedin")) {
        linkedInDisplay = "LinkedIn";
        linkedInUrl = l;
        break;
      }
    }
    linkedInDisplay ??= links.isNotEmpty ? "Link" : null;
    linkedInUrl ??= links.isNotEmpty ? links.first : null;

    final onAccent = Colors.white.withOpacity(0.98);
    final onAccentMuted = Colors.white.withOpacity(0.82);

    return SizedBox(
      width: double.infinity,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 13, 20, 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent,
              Color.lerp(accent, const Color(0xFF0F172A), 0.18)!,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: _nameFf,
                  fontSize: ResumeTypography.name,
                  fontWeight: FontWeight.w900,
                  color: onAccent,
                  height: 1.08,
                ),
              ),
              if (role.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  role,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: ResumeTypography.body,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.35,
                    color: onAccentMuted,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 5,
                children: [
                  if (email.isNotEmpty)
                    _tappableContactRow(
                      uri: _contactLaunchUri(Icons.email_outlined, email),
                      child: _t1BannerContactItem(
                        Icons.email_outlined,
                        email,
                        onAccentMuted,
                      ),
                    ),
                  if (phone.isNotEmpty)
                    _tappableContactRow(
                      uri: _contactLaunchUri(Icons.phone_outlined, phone),
                      child: _t1BannerContactItem(
                        Icons.phone_outlined,
                        phone,
                        onAccentMuted,
                      ),
                    ),
                  if (geo.isNotEmpty)
                    _tappableContactRow(
                      uri: _contactLaunchUri(
                        Icons.location_on_outlined,
                        geo,
                      ),
                      child: _t1BannerContactItem(
                        Icons.location_on_outlined,
                        geo,
                        onAccentMuted,
                      ),
                    ),
                  if (linkedInUrl != null && linkedInUrl!.trim().isNotEmpty)
                    _tappableContactRow(
                      uri: _contactLaunchUri(Icons.insert_link, linkedInUrl),
                      child: _t1BannerContactItem(
                        Icons.insert_link,
                        linkedInDisplay ?? "LinkedIn",
                        onAccentMuted,
                        underline: true,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _t1BannerContactItem(
    IconData icon,
    String text,
    Color onAccentMuted, {
    bool underline = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: onAccentMuted),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.visible,
            softWrap: true,
            style: TextStyle(
              fontFamily: _bodyFf,
              fontSize: ResumeTypography.body,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: Colors.white.withOpacity(0.95),
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: Colors.white.withOpacity(0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _template1ContactChips(Color accent) {
    final email = data.email.trim();
    final phone = data.phone.trim();
    final geo = _resumeGeoDisplayLine(data);
    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    String? linkedInDisplay;
    String? linkedInUrl;
    for (final l in links) {
      if (l.toLowerCase().contains("linkedin")) {
        linkedInDisplay = "LinkedIn";
        linkedInUrl = l;
        break;
      }
    }
    linkedInDisplay ??= links.isNotEmpty ? "Link" : null;
    linkedInUrl ??= links.isNotEmpty ? links.first : null;

    Widget chip(IconData icon, String text, {Uri? uri}) {
      final iconTint = Color.alphaBlend(
        accent.withOpacity(0.22),
        Colors.grey.shade700,
      );
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: iconTint),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _bodyFf,
                fontSize: ResumeTypography.body,
                height: 1.18,
                color: const Color(0xFF333333),
                decoration: uri == null ? null : TextDecoration.underline,
              ),
            ),
          ),
        ],
      );
      return _tappableContactRow(uri: uri, child: row);
    }

    final children = <Widget>[
      if (geo.isNotEmpty)
        chip(
          Icons.location_on_outlined,
          geo,
          uri: _contactLaunchUri(Icons.location_on_outlined, geo),
        ),
    ];

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 8,
        children: children,
      ),
    );
  }

  Widget _templateHeaderClassic(_TemplateStyle style) {
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.name.isNotEmpty ? data.name : "Your Name",
            style: const TextStyle(
              fontSize: ResumeTypography.name,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              height: 1.05,
            ),
          ),
          if (role.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                role,
                style: TextStyle(
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: const Color(0xFF111827).withOpacity(0.65),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.black.withOpacity(0.10),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderAtsPro(_TemplateStyle style) {
    final name = data.name.trim().isNotEmpty ? data.name.trim() : "Your Name";
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role.trim() : "";
    final parts = <String>[];
    final email = data.email.trim();
    final phone = data.phone.trim();
    if (email.isNotEmpty) parts.add(email);
    if (phone.isNotEmpty) parts.add(phone);
    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (links.isNotEmpty) parts.add(links.first);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontFamily: _nameFf,
              fontSize: ResumeTypography.name,
              fontWeight: FontWeight.w900,
              height: 1.02,
              color: const Color(0xFF0B1220),
            ),
          ),
          if (role.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                role,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.heading,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.black.withOpacity(0.62),
                  height: 1.12,
                ),
              ),
            ),
          if (parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                parts.join(' | '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withOpacity(0.70),
                  height: 1.12,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.black.withOpacity(0.12),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderExecutiveMono(_TemplateStyle style) {
    final name = data.name.trim().isNotEmpty ? data.name.trim() : "Your Name";
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role.trim() : "";
    final geo = _resumeGeoDisplayLine(data);
    final meta = <String>[
      if (data.email.trim().isNotEmpty) data.email.trim(),
      if (data.phone.trim().isNotEmpty) data.phone.trim(),
      if (geo.isNotEmpty) geo,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontFamily: _bodyFf,
              fontSize: ResumeTypography.name,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              height: 1.02,
              color: const Color(0xFF0B1220),
            ),
          ),
          if (role.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                role,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2A44).withOpacity(0.85),
                  height: 1.12,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                meta.join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withOpacity(0.66),
                  height: 1.12,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            width: double.infinity,
            color: const Color(0xFF1F2A44).withOpacity(0.16),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderCompactModern(_TemplateStyle style) {
    final name = data.name.trim().isNotEmpty ? data.name.trim() : "Your Name";
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role.trim() : "";
    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final meta = <String>[
      if (data.email.trim().isNotEmpty) data.email.trim(),
      if (data.phone.trim().isNotEmpty) data.phone.trim(),
      if (links.isNotEmpty) links.first,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontFamily: _nameFf,
                    fontSize: ResumeTypography.name,
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                    color: const Color(0xFF052E2B),
                  ),
                ),
              ),
              Container(
                width: 84,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E7490),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
          if (role.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                role,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.62),
                  height: 1.12,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                meta.join(' | '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withOpacity(0.70),
                  height: 1.12,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            width: double.infinity,
            color: const Color(0xFF0E7490).withOpacity(0.18),
          ),
        ],
      ),
    );
  }

  Widget _template2TopBanner() {
    final header = t2HeaderColor ?? const Color(0xFF0F1F33);
    final gold = t2GoldColor ?? const Color(0xFFC5B358);
    final name = (data.name.trim().isNotEmpty ? data.name.trim() : "Your Name")
        .toUpperCase();
    final title = data.experiences.isNotEmpty
        ? data.experiences.first.role.trim().toUpperCase()
        : "PROFESSIONAL TITLE";

    return Container(
      width: double.infinity,
      color: header,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _nameFf,
              fontSize: ResumeTypography.name,
              height: 1.0,
              letterSpacing: 1.6,
              color: gold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _bodyFf,
              fontSize: ResumeTypography.heading,
              height: 1.0,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
              color: gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderRibbon(_TemplateStyle style) {
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E3A43),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data.name.isNotEmpty ? data.name : "Your Name").toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: ResumeTypography.name,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFEFEFEF),
                    height: 1.0,
                    letterSpacing: 2.2,
                  ),
                ),
                if (role.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ResumeTypography.heading,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: Colors.white.withOpacity(0.82),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (data.summary.trim().isNotEmpty)
                  Text(
                    data.summary.trim(),
                    maxLines: null,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: ResumeTypography.body,
                      height: 1.35,
                      color: Colors.white.withOpacity(0.88),
                    ),
                  ),
              ],
            ),
          ),
          // Gold ribbon accents (curved + shaded)
          Positioned(
            right: -26,
            top: 10,
            child: Transform.rotate(
              angle: -0.12,
              child: _RibbonWave(
                width: 190,
                height: 38,
                color: style.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderBlackYellow(_TemplateStyle style) {
    // Matches the "Austin Bronson" vibe: bold name + yellow rule (main column).
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 6,
            width: 150,
            decoration: BoxDecoration(
              color: style.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            (data.name.isNotEmpty ? data.name : "Your Name").toUpperCase(),
            style: ResumeTypography.nameStyle(
              _nameFf,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: const Color(0xFF111827),
              height: 1.0,
            ),
          ),
          if (role.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                role.toUpperCase(),
                style: ResumeTypography.bodyStyle(
                  _bodyFf,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.black.withOpacity(0.10),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderGreyOverlap(_TemplateStyle style) {
    // Matches the "Jonathan Patterson" feel: wide grey band + big name.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 64,
                color: const Color(0xFF6B6B6B),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data.name.isNotEmpty ? data.name : "Your Name")
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: ResumeTypography.name,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                if (role.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      role,
                      style: TextStyle(
                        fontSize: ResumeTypography.body,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderSlateHero(_TemplateStyle style) {
    // Matches Template 7 photo: dark hero banner + circular photo + name.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Banner
          Container(
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0B0F16),
                  const Color(0xFF1F2937).withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(104, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data.name.isNotEmpty ? data.name : "Your Name")
                      .toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  style: ResumeTypography.nameStyle(
                    _nameFf,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 1,
                  width: double.infinity,
                  color: Colors.white.withOpacity(0.25),
                ),
                if (role.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    role.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ResumeTypography.body,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Circular photo overlapping banner (like the reference).
          Positioned(
            left: 12,
            bottom: -14,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.85),
                border: Border.all(color: Colors.white, width: 6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: (data.profileImage != null &&
                        File(data.profileImage!.path).existsSync())
                    ? Image.file(
                        File(data.profileImage!.path),
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.black.withOpacity(0.05)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderModernCards(_TemplateStyle style) {
    // Matches photo: top header image + teal contact strip.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: (data.profileImage != null &&
                            File(data.profileImage!.path).existsSync())
                        ? Image.file(
                            File(data.profileImage!.path),
                            fit: BoxFit.cover,
                            color: Colors.black.withOpacity(0.15),
                            colorBlendMode: BlendMode.darken,
                          )
                        : Container(color: const Color(0xFF111827)),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.name.isNotEmpty ? data.name : "Your Name",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: ResumeTypography.name,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      if (role.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: ResumeTypography.body,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: style.accent.withOpacity(0.95),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.email.trim().isNotEmpty)
                  _miniContactChip(Icons.email, data.email),
                if (data.email.trim().isNotEmpty &&
                    data.phone.trim().isNotEmpty)
                  const SizedBox(height: 6),
                if (data.phone.trim().isNotEmpty)
                  _miniContactChip(Icons.phone, data.phone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateHeaderGoldHeader(_TemplateStyle style) {
    // Matches photo: dark header band + circular photo on right.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: const Color(0xFF0B2230),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 16,
              right: 96,
              top: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name.isNotEmpty ? data.name : "Your Name",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: ResumeTypography.name,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  if (role.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ResumeTypography.body,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    height: 2,
                    width: 110,
                    color: style.accent,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 10,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: style.accent, width: 4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: (data.profileImage != null &&
                          File(data.profileImage!.path).existsSync())
                      ? Image.file(File(data.profileImage!.path),
                          fit: BoxFit.cover)
                      : Container(color: Colors.white.withOpacity(0.08)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templateHeaderMobileCard(_TemplateStyle style) {
    // Matches the mobile screenshot: dark angled header with avatar.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 96,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: const Color(0xFF111827)),
              ),
              Positioned(
                left: -40,
                top: -40,
                child: Transform.rotate(
                  angle: -0.35,
                  child: Container(
                    width: 220,
                    height: 140,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 18,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: (data.profileImage != null &&
                            File(data.profileImage!.path).existsSync())
                        ? Image.file(File(data.profileImage!.path),
                            fit: BoxFit.cover)
                        : Container(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
              ),
              Positioned(
                left: 84,
                right: 12,
                top: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name.isNotEmpty ? data.name : "Your Name",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: ResumeTypography.name,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                    if (role.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        role.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ResumeTypography.body,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Colors.white.withOpacity(0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniContactChip(IconData icon, String value) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    final uri = _contactLaunchUri(icon, v);
    return _tappableContactRow(
        uri: uri,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.95)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                v,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: _bodyFf,
                  color: Colors.white,
                  fontSize: ResumeTypography.body,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  decoration: uri == null ? null : TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
    );
  }

}

/// Matches the ATS checker "insane UI" background (visual-only).
class _ATSLikeBackground extends StatelessWidget {
  const _ATSLikeBackground();

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
        // Subtle light falloff for a more "Canva" depth.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.2, -0.7),
                radius: 1.2,
                colors: [
                  Colors.white.withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
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
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
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

enum _TitleStyle { underline, pill, fullRule }

enum _SidebarPlacement { left, right, none }

class _RibbonWave extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _RibbonWave({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _RibbonWavePainter(color: color),
      ),
    );
  }
}

class _RibbonWavePainter extends CustomPainter {
  final Color color;
  const _RibbonWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final mainPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.95),
          color.withOpacity(0.70),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);

    Path path() {
      final w = size.width;
      final h = size.height;
      final r = h * 0.55;
      final p = Path()
        ..moveTo(r, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, h - r)
        ..quadraticBezierTo(w, h, w - r, h)
        ..quadraticBezierTo(w * 0.62, h * 0.92, w * 0.52, h * 0.70)
        ..quadraticBezierTo(w * 0.42, h * 0.45, w * 0.22, h * 0.58)
        ..quadraticBezierTo(w * 0.12, h * 0.66, 0, h * 0.48)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..close();
      return p;
    }

    final p = path();
    canvas.drawPath(p.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(p, mainPaint);

    // Highlight strip
    final highlight = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final hl = Path()
      ..moveTo(size.width * 0.12, size.height * 0.22)
      ..quadraticBezierTo(
          size.width * 0.55, size.height * 0.02, size.width * 0.92, size.height * 0.24);
    canvas.drawPath(hl, highlight);
  }

  @override
  bool shouldRepaint(covariant _RibbonWavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TemplateStyle {
  final String id;
  final LinearGradient? sidebarGradient;
  final Color? sidebarSolidColor;
  final Color sidebarOnColor;
  final Color accent;
  final _TitleStyle titleStyle;
  final _SidebarPlacement sidebarPlacement;

  const _TemplateStyle({
    required this.id,
    required this.sidebarGradient,
    required this.sidebarSolidColor,
    required this.sidebarOnColor,
    required this.accent,
    required this.titleStyle,
    required this.sidebarPlacement,
  });

  _TemplateStyle copyWithAccent(Color nextAccent) {
    return _TemplateStyle(
      id: id,
      sidebarGradient: sidebarGradient,
      sidebarSolidColor: sidebarSolidColor,
      sidebarOnColor: sidebarOnColor,
      accent: nextAccent,
      titleStyle: titleStyle,
      sidebarPlacement: sidebarPlacement,
    );
  }
}

class _TemplateStyles {
  static _TemplateStyle forId(String id) {
    switch (id) {
      // Minimal single-column (black & white, full-width rules).
      case "1":
        return const _TemplateStyle(
          id: "1",
          sidebarGradient: null,
          sidebarSolidColor: null,
          sidebarOnColor: Color(0xFF111111),
          accent: Color(0xFF2563EB),
          titleStyle: _TitleStyle.fullRule,
          sidebarPlacement: _SidebarPlacement.none,
        );

      // Emerson-style: white sidebar + gold accents; navy header is rendered separately.
      case "2":
        return const _TemplateStyle(
          id: "2",
          sidebarGradient: null,
          sidebarSolidColor: Color(0xFFFFFFFF),
          sidebarOnColor: Color(0xFF111827),
          accent: Color(0xFFC5B358),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Larry Tibbetts (teal + gold pill titles).
      case "3":
        return const _TemplateStyle(
          id: "3",
          sidebarGradient: LinearGradient(
            colors: [Color(0xFF0E3A43), Color(0xFF0A2D34)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          sidebarSolidColor: null,
          sidebarOnColor: Colors.white,
          accent: Color(0xFFB38A3B),
          titleStyle: _TitleStyle.pill,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Austin Bronson (black sidebar, yellow accent).
      case "4":
        return const _TemplateStyle(
          id: "4",
          sidebarGradient: LinearGradient(
            colors: [Color(0xFF222222), Color(0xFF121212)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          sidebarSolidColor: null,
          sidebarOnColor: Color(0xFFEFEFEF),
          accent: Color(0xFFF3C300),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Jonathan Patterson (light grey + minimalist).
      case "5":
        return const _TemplateStyle(
          id: "5",
          sidebarGradient: null,
          sidebarSolidColor: Color(0xFFE7E7E7),
          sidebarOnColor: Color(0xFF111827),
          accent: Color(0xFF111827),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Richard Sanchez (teal left, blue accent line).
      case "6":
        return const _TemplateStyle(
          id: "6",
          sidebarGradient: LinearGradient(
            colors: [Color(0xFF163C52), Color(0xFF0E2B3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          sidebarSolidColor: null,
          sidebarOnColor: Colors.white,
          accent: Color(0xFF163C52),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Martiens Pitters (dark slate, icon panels feel).
      case "7":
        return const _TemplateStyle(
          id: "7",
          sidebarGradient: LinearGradient(
            colors: [Color(0xFF2F3840), Color(0xFF20272D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          sidebarSolidColor: null,
          sidebarOnColor: Colors.white,
          accent: Color(0xFF2F3840),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // Will Tribianni (modern teal accent cards).
      case "8":
        return const _TemplateStyle(
          id: "8",
          sidebarGradient: null,
          sidebarSolidColor: Color(0xFFF3F4F6),
          sidebarOnColor: Color(0xFF111827),
          accent: Color(0xFF3A9CA5),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.right,
        );

      // Jessica Blakely (dark header + gold accent).
      case "9":
        return const _TemplateStyle(
          id: "9",
          sidebarGradient: LinearGradient(
            colors: [Color(0xFF0F2E3C), Color(0xFF0B2230)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          sidebarSolidColor: null,
          sidebarOnColor: Colors.white,
          accent: Color(0xFFC7A24B),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.right,
        );

      // Mobile-inspired (simple neutral).
      case "10":
        return const _TemplateStyle(
          id: "10",
          sidebarGradient: null,
          sidebarSolidColor: Color(0xFFE5E7EB),
          sidebarOnColor: Color(0xFF111827),
          accent: Color(0xFF6B7280),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.left,
        );

      // ATS Pro (single-column, high-contrast, full rules).
      case "11":
        return const _TemplateStyle(
          id: "11",
          sidebarGradient: null,
          sidebarSolidColor: null,
          sidebarOnColor: Color(0xFF111111),
          accent: Color(0xFF111111),
          titleStyle: _TitleStyle.fullRule,
          sidebarPlacement: _SidebarPlacement.none,
        );

      // Executive Mono (single-column, blue accent, understated rules).
      case "12":
        return const _TemplateStyle(
          id: "12",
          sidebarGradient: null,
          sidebarSolidColor: null,
          sidebarOnColor: Color(0xFF0B1220),
          accent: Color(0xFF1F2A44),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.none,
        );

      // Compact Modern (single-column, teal accent).
      case "13":
        return const _TemplateStyle(
          id: "13",
          sidebarGradient: null,
          sidebarSolidColor: null,
          sidebarOnColor: Color(0xFF052E2B),
          accent: Color(0xFF0E7490),
          titleStyle: _TitleStyle.underline,
          sidebarPlacement: _SidebarPlacement.none,
        );

      default:
        return forId("1");
    }
  }
}

class _PreviewMetrics {
  /// Logical “paper” width; page height uses [PdfService.styledTemplateExportPageFormat] ratio.
  static const double pageWidth = 600.0;

  /// Usable main-column height on template 1 page 1 (banner is outside this column).
  static double template1Page1RightHeight(
    double pageHeight, {
    double bannerHeight = _kTemplate1BannerHeight,
  }) {
    const pageFooterBar = 28.0;
    const page1TopPad = 12.0;
    const page1BottomPad = 26.0;
    return pageHeight -
        pageFooterBar -
        bannerHeight -
        page1TopPad -
        page1BottomPad;
  }

  /// Usable main-column height on template 1 pages 2+ (full-width, no top banner).
  static double template1ContinuationRightHeight(double pageHeight) {
    const pageFooterBar = 28.0;
    const padTop = 26.0;
    const padBottom = 26.0;
    return pageHeight - pageFooterBar - padTop - padBottom;
  }

  static int _charsPerLine(double availableWidth, {bool template1 = false}) =>
      math.max(
        24,
        (availableWidth / (template1 ? 6.15 : 5.1)).floor(),
      );

  static double stackedSectionsHeight({
    required List<Map<String, dynamic>> sections,
    required double availableWidth,
    required String templateId,
  }) {
    var total = 0.0;
    for (final s in sections) {
      total += sectionHeight(s, availableWidth: availableWidth, templateId: templateId);
    }
    return total;
  }

  static double sectionHeight(
    Map<String, dynamic> s, {
    required double availableWidth,
    required String templateId,
  }) {
    final type = s["type"];
    final t1 = templateId == "1";
    final charsPerLine = _charsPerLine(availableWidth, template1: t1);
    double h = 0;

    if (type == "section") {
      final title = (s["title"] ?? "").toString().toLowerCase();
      final isProfileSummary =
          title.contains("profile") || title.contains("summary");
      final content = (s["content"] ?? "").toString();
      var lines = (content.length / charsPerLine).ceil();
      if (!t1 && isProfileSummary) lines = math.min(lines, 8);
      h = (t1 ? 32 : 46) +
          6 +
          lines * (t1 ? 14.0 : (templateId == "2" ? 16.4 : 15.0));
    } else if (type == "experience") {
      final items = (s["items"] as List?) ?? const [];
      final t1wh = (s["t1_show_work_heading"] as bool?) ?? true;
      final t1jh = (s["t1_show_job_header"] as bool?) ?? true;
      if (templateId == "2") {
        h = t1wh ? 52 : 8;
        for (var i = 0; i < items.length; i++) {
          final exp = items[i] as Experience;
          final bullets = exp.description
              .map((b) => b.trim())
              .where((b) => b.isNotEmpty)
              .toList();
          var introExtra = 0.0;
          var n = bullets.length;
          if (bullets.isNotEmpty &&
              ExperienceDisplay.looksLikeSummaryIntro(bullets.first)) {
            introExtra = 46;
            n = bullets.length - 1;
          }
          h += (t1jh ? 56 : 10);
          h += introExtra;
          if (n > 0 || introExtra > 0) h += 10;
          h += n * 23.0;
          h += 18;
        }
        h += 20;
      } else {
        h = t1wh ? 32 + 6 : 4;
        for (var i = 0; i < items.length; i++) {
          final exp = items[i] as Experience;
          final bullets = exp.description
              .map((b) => b.trim())
              .where((b) => b.isNotEmpty)
              .toList();
          h += t1jh ? 36 : 6;
          for (final b in bullets) {
            final lines = math.max(1, (b.length / charsPerLine).ceil());
            h += lines * 14.0 + 4;
          }
          if (t1 && i < items.length - 1) h += 5;
        }
        h += t1 ? 4 : 18;
      }
    } else if (type == "education") {
      final items = (s["items"] as List?) ?? const [];
      h = t1 ? 32 + 6 + items.length * 28.0 : 52 + items.length * 44.0;
    } else if (type == "skills_categorized") {
      final groups = (s["groups"] as List?) ?? const [];
      h = t1 ? 32 + 6 : 52;
      for (final g in groups) {
        final value =
            (g is Map && g["value"] != null) ? g["value"].toString() : "";
        if (t1) {
          final parts = _splitSkillListValue(value).length;
          final approxChipsPerRow = math.max(1, (availableWidth / 72).floor());
          final chipRows = math.max(1, (parts / approxChipsPerRow).ceil());
          h += 18 + chipRows * 20.0;
        } else {
          h += 20;
          h += (value.length / charsPerLine).ceil() * 15.0;
        }
      }
    } else if (type == "projects") {
      final items = (s["items"] as List?) ?? const [];
      h = (t1 ? 32 + 6 : 52) + items.length * (t1 ? 16.0 : 22.0);
    } else if (type == "courses" || type == "certifications") {
      final items = (s["items"] as List?) ?? const [];
      h = t1 ? 32 + 6 : 52;
      for (final it in items) {
        final line = it.toString();
        final wrapped = math.max(1, (line.length / charsPerLine).ceil());
        h += (t1 ? 14.0 : 17.0) * wrapped + (t1 ? 4.0 : 6.0);
      }
    } else if (type == "skills") {
      final items = (s["items"] as List?) ?? const [];
      if (t1) {
        h = 32 + 6;
        final approxChipsPerRow = math.max(1, (availableWidth / 68).floor());
        final chipRows = math.max(1, (items.length / approxChipsPerRow).ceil());
        h += chipRows * 20.0;
      } else {
        final joined = items.map((e) => e.toString()).join(", ");
        final lines = math.max(1, (joined.length / charsPerLine).ceil());
        h = 52 + lines * 16.0;
      }
    } else if (type == "achievement") {
      final items = (s["items"] as List?) ?? const [];
      h = (t1 ? 32 + 6 : 52) + items.length * (t1 ? 15.0 : 18.0);
    } else if (type == "references") {
      final items = (s["items"] as List?) ?? const [];
      h = t1 ? 32 + 6 + items.length * 30.0 : 56 + items.length * 42.0;
    } else {
      h = 56;
    }
    return h;
  }

  static int rightSectionCapacity({
    required double availableHeight,
    required double availableWidth,
    required List<Map<String, dynamic>> sections,
    String templateId = "",
  }) {
    if (templateId == '1') {
      var count = 0;
      for (var i = 0; i < sections.length; i++) {
        final stacked = stackedSectionsHeight(
          sections: sections.sublist(0, i + 1),
          availableWidth: availableWidth,
          templateId: '1',
        );
        if (stacked <= availableHeight) {
          count = i + 1;
        } else {
          break;
        }
      }
      return math.max(1, count);
    }

    double used = 0;
    int count = 0;
    for (final s in sections) {
      final h = sectionHeight(
        s,
        availableWidth: availableWidth,
        templateId: templateId,
      );
      if (used + h > availableHeight) break;
      used += h;
      count++;
    }
    return math.max(1, count);
  }
}

enum _ResumeExportKind { styledPreview, atsText }

class _ResumePreviewPageData {
  final bool showDetails;
  final List<String> links;
  final List<String> skills;
  final List<Education> education;
  final List<String> certifications;
  final List<String> languages;
  final List<String> otherLines;
  final List<Map<String, dynamic>> rightSections;

  const _ResumePreviewPageData({
    required this.showDetails,
    required this.links,
    required this.skills,
    required this.education,
    this.certifications = const [],
    required this.languages,
    required this.otherLines,
    required this.rightSections,
  });
}
