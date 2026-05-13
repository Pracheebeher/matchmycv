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
import '../services/resume_layout_engine.dart';
import '../utils/resume_theme.dart';
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
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Suggested summary',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.suggestedSummary.isEmpty ? '—' : r.suggestedSummary,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          height: 1.35,
                          fontSize: 13,
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
                          fontSize: 13,
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
                          fontSize: 13,
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
      fontSize: 10,
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
                          fontSize: 11,
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
                            child: Text('Georgia', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                          DropdownMenuItem(
                            value: 'Times New Roman',
                            child: Text('Times', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                          DropdownMenuItem(
                            value: 'Palatino',
                            child: Text('Palatino', style: TextStyle(color: Colors.white, fontSize: 11)),
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
                          fontSize: 11,
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
                            child: Text('Roboto', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                          DropdownMenuItem(
                            value: 'Helvetica',
                            child: Text('Helvetica', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                          DropdownMenuItem(
                            value: 'Arial',
                            child: Text('Arial', style: TextStyle(color: Colors.white, fontSize: 11)),
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
                                        fontSize: 14,
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
                            fontSize: 13.0,
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
                            fontSize: 11.0,
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
                                      fontSize: 14,
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
          final pages = _paginate(
            layout,
            pageHeight: pageHeight,
            rightWidth: rightWidth,
            templateId: templateId,
            l10n: AppLocalizations.of(context),
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

          final mainContentPadding = templateId == "2"
              ? const EdgeInsets.fromLTRB(30, 26, 30, 22)
              : const EdgeInsets.fromLTRB(26, 26, 26, 26);

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
                                                        height: 100.0,
                                                        child:
                                                            _template1TopBanner(
                                                          accent,
                                                        ),
                                                      ),
                                                    SizedBox(
                                                      height: pageHeight -
                                                          pageFooterBar -
                                                          (i == 0 ? 100.0 : 0),
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
                                                                    const ClampingScrollPhysics(),
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
                                                            fontSize: 9.5,
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
                                                                          "2"
                                                                      ? const NeverScrollableScrollPhysics()
                                                                      : const ClampingScrollPhysics(),
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
                                                            fontSize: 9.5,
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

  /// Height model for one template-1 experience slice (must stay in sync with [_buildSection]).
  double _estimateTemplate1ExperienceSliceHeight({
    required bool showWorkHeading,
    required bool showJobHeader,
    required int bulletCount,
    bool includeTargetBanner = false,
  }) {
    var h = 0.0;
    h += showWorkHeading ? 46 : 6;
    h += showJobHeader ? 48 : 6;
    if (includeTargetBanner) h += 44;
    h += bulletCount * 14.9;
    h += 12;
    return h;
  }

  /// Breaks large jobs into multiple [experience] sections so pagination can move overflow to the next page.
  List<Map<String, dynamic>> _expandTemplate1ExperienceSlices(
    List<Map<String, dynamic>> right,
    double maxSliceHeight,
  ) {
    final out = <Map<String, dynamic>>[];
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
          showNextWorkHeading = false;
          continue;
        }

        var showJobHeader = true;
        var bi = 0;
        while (bi < bullets.length) {
          var lo = bi + 1;
          var hi = bullets.length;
          var bestEnd = bi + 1;
          while (lo <= hi) {
            final mid = (lo + hi) ~/ 2;
            final chunkLen = mid - bi;
            final includeJd =
                jdStr.isNotEmpty && showNextWorkHeading && !jdAttached;
            final est = _estimateTemplate1ExperienceSliceHeight(
              showWorkHeading: showNextWorkHeading,
              showJobHeader: showJobHeader,
              bulletCount: chunkLen,
              includeTargetBanner: includeJd,
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

      // Rough height model per job; tuned to match preview widgets (non-template-1).
      double jobH(Experience e) {
        final n = e.description.where((b) => b.trim().isNotEmpty).length;
        // role/company/dates row(s)
        var h = 50.0;
        // bullets
        h += n * 18.0;
        // spacing between jobs
        h += 10.0;
        return h;
      }

      const headingH = 54.0;
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

        String? intro;
        var bulletLines = <String>[];
        if (bullets.isNotEmpty) {
          if (bullets.length >= 2 &&
              (bullets.first.length > 140 ||
                  bullets.first.contains('.'))) {
            intro = bullets.first;
            bulletLines = bullets.skip(1).toList();
          } else {
            bulletLines = bullets;
          }
        } else {
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

  List<_ResumePreviewPageData> _paginate(
    List<Map<String, dynamic>> layout, {
    required double pageHeight,
    required double rightWidth,
    required String templateId,
    required AppLocalizations l10n,
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
    const t1FirstPageHeaderReserve = 100.0;
    const t1ContinuationReserve = 26.0;
    const t1SliceSlack = 12.0;

    if (templateId == "1") {
      // Split long jobs into slices that fit under the header + footer so bullets
      // continue on the next page instead of clipping.
      final maxExpSlice = math.max(
        120.0,
        rightInnerHeight - t1FirstPageHeaderReserve - t1SliceSlack,
      );
      right = _expandTemplate1ExperienceSlices(right, maxExpSlice);
    } else {
      // Other templates: split very large experience sections by job so page 1
      // doesn't become "SUMMARY only" when experience is long.
      final maxChunk = math.max(180.0, rightInnerHeight - 32.0);
      right = _expandExperienceJobChunks(
        right,
        maxChunk,
        templateId: templateId,
      );
      if (templateId == "2") {
        final sliceH = math.max(160.0, rightInnerHeight - 48.0);
        right = _expandTemplate2ExperienceBulletSlices(right, sliceH);
      }
    }

    // Template 1 is full-width: skills/education/languages live in [right], not the
    // sidebar. Never wait on sidebar slice indices for that template or take* stays 0
    // forever and this loop never terminates (OOM / Scudo "Lost connection").
    final singleColumn = templateId == "1";
    final packSidebar = !singleColumn;

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

      // Template 1: page 1 needs a realistic header reserve (not too large or page 1
      // looks empty). Continuation pages need extra pessimism or the packer puts one
      // section too many and the preview column scrolls inside the card.
      final rightAvailHeight = (pages.isEmpty && templateId == "1")
          ? (rightInnerHeight - t1FirstPageHeaderReserve)
              .clamp(96.0, rightInnerHeight)
          : (templateId == "1"
              ? (rightInnerHeight - t1ContinuationReserve)
                  .clamp(96.0, rightInnerHeight)
              : templateId == "2"
                  ? (rightInnerHeight - 40.0).clamp(120.0, rightInnerHeight)
                  : rightInnerHeight);
      final rightCap = _PreviewMetrics.rightSectionCapacity(
        availableHeight: rightAvailHeight,
        availableWidth: rightWidth,
        sections: right.sublist(rightIndex),
        templateId: templateId,
      );
      var takeRight = math.min(rightCap, right.length - rightIndex);
      if (takeRight == 0 && rightIndex < right.length) {
        takeRight = 1;
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
          rightSections: right.sublist(rightIndex, rightIndex + takeRight),
        ),
      );

      skillIndex += takeSkills;
      educationIndex += takeEducation;
      languageIndex += takeLangs;
      otherIndex += takeOther;
      rightIndex += takeRight;
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
            style: TextStyle(
              color: style.sidebarOnColor,
              fontSize: compact ? 15 : 16,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (role.trim().isNotEmpty) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              role,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.sidebarOnColor.withOpacity(0.8),
                fontSize: compact ? 9.5 : 10,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    color: style.sidebarOnColor.withOpacity(0.92),
                    fontSize: 8.35,
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
            fontSize: 9.75,
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
                  fontSize: 8.85,
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
                  fontSize: 8.25,
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
                  fontSize: 8.25,
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
                  fontSize: 8.1,
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
                            fontSize: 8.35,
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
                    fontSize: 8.35,
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
                    fontSize: 8.25,
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
              fontSize: 10,
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
    // Austin Bronson reference: left photo block + ABOUT ME + SKILLS bars.
    final compact = sidebarWidth < 180;
    final photoH = compact ? 150.0 : 190.0;
    final showPhoto = page.showDetails;

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
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ABOUT ME",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 10),
                if (data.summary.trim().isNotEmpty)
                  Text(
                    data.summary.trim(),
                    maxLines: null,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 9.5,
                      height: 1.35,
                    ),
                  ),
                const SizedBox(height: 18),
                Text(
                  "SKILLS",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 10),
                for (final s in page.skills.take(8)) ...[
                  _skillBar(s, const _TemplateStyle(
                    id: "4x",
                    sidebarGradient: null,
                    sidebarSolidColor: null,
                    sidebarOnColor: Color(0xFFEFEFEF),
                    accent: Color(0xFFF3C300),
                    titleStyle: _TitleStyle.underline,
                    sidebarPlacement: _SidebarPlacement.left,
                  )),
                  const SizedBox(height: 8),
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
                  fontSize: 8.5,
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
          fontSize: 9.25,
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
                fontSize: 10,
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
          if (page.showDetails) ...[
            panelTitle(Icons.person, "ABOUT"),
            const SizedBox(height: 8),
            Text(
              data.summary.trim().isEmpty ? " " : data.summary.trim(),
              maxLines: null,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 9,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                fontSize: 11,
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
              children: page.skills
                  .take(10)
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.sidebarOnColor.withOpacity(0.88),
              fontSize: 9,
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
              fontSize: 8.5,
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
        style: TextStyle(
          color: style.sidebarOnColor.withOpacity(0.9),
          fontSize: 11,
          fontWeight: FontWeight.w800,
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
          fontSize: 9,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _skillBar(String label, _TemplateStyle style) {
    final base = (label.hashCode % 50) + 45; // 45..94
    final value = base / 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: style.sidebarOnColor.withOpacity(0.85),
            fontSize: 8,
            height: 1.0,
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

  Widget _template1SkillValueWrap(String raw, TextStyle chipStyle) {
    final t = raw.trim();
    final parts = t.isEmpty
        ? const <String>[]
        : (_splitSkillListValue(t).isNotEmpty ? _splitSkillListValue(t) : <String>[t]);
    const bg = Color(0xFFF1F5F9); // slate-100
    final border = const Color(0xFF0F172A).withOpacity(0.12);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final part in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFFFFF),
                  bg,
                ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              part,
              style: chipStyle.copyWith(
                fontSize: 8.6,
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: 0.1,
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
    final bodyStyle = ResumeTheme.body.copyWith(
      fontSize: 10.25,
      height: 1.35,
      color: const Color(0xFF0F172A),
      fontFamily: _bodyFf,
    );
    final bodyStyleLight = ResumeTheme.body.copyWith(
      fontSize: 10.0,
      height: 1.35,
      color: Colors.black.withOpacity(0.70),
      fontFamily: _bodyFf,
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

        // Template 4 puts summary on the left ("ABOUT ME"), so hide profile.
        if (style.id == "4" &&
            section["title"].toString().toLowerCase().contains("profile")) {
          return const SizedBox.shrink();
        }

        final sectionPadBottom = style.id == "1" ? 12.0 : 18.0;
        final titleLower = section["title"].toString().toLowerCase();
        final isProfileSummary = titleLower.contains("profile") ||
            titleLower.contains("summary") ||
            titleLower.contains("about");
        return Padding(
          padding: EdgeInsets.only(bottom: sectionPadBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (style.id == "2")
                _contentTitleTemplate2(section["title"].toString(), style)
              else
                _contentTitle(
                  style.id == "3"
                      ? section["title"].toString().toUpperCase()
                      : section["title"].toString(),
                  style,
                ),
              SizedBox(height: style.id == "1" ? 8 : 10),
              Text(
                contentStr,
                textAlign: (style.id == "2" || style.id == "1")
                    ? TextAlign.justify
                    : TextAlign.start,
                maxLines: (style.id == "1" || !isProfileSummary) ? null : 8,
                overflow: (style.id == "1" || !isProfileSummary)
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: style.id == "1"
                    ? bodyStyle.copyWith(fontSize: 9.9, height: 1.34)
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
                : (style.id == "6"
                    ? "Work Experience"
                    : "Employment History");

        final t1ShowWorkHeading = (style.id == "1" || style.id == "2")
            ? (section["t1_show_work_heading"] as bool? ?? true)
            : true;
        final t1ShowJobHeader = (style.id == "1" || style.id == "2")
            ? (section["t1_show_job_header"] as bool? ?? true)
            : true;

        final expBlockPadBottom = style.id == "1" ? 12.0 : 18.0;
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
                final bullets = exp.description
                    .map((b) => b.trim())
                    .where((b) => b.isNotEmpty)
                    .toList();
                if (style.id == "1") {
                  final t1Body = TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: 10.0,
                    height: 1.34,
                    color: const Color(0xFF111111),
                  );
                  final t1Muted = TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: 8.75,
                    color: Colors.black.withOpacity(0.55),
                  );
                  final company =
                      exp.company.trim().isNotEmpty ? exp.company.trim() : "";
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: t1ShowJobHeader ? 12 : 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t1ShowJobHeader) ...[
                          if (company.isNotEmpty) ...[
                            Text(
                              company,
                              style: TextStyle(
                                fontFamily: _bodyFf,
                                fontSize: 10.25,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111111),
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  exp.role,
                                  style: t1Muted.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                exp.duration,
                                style: t1Muted,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ] else
                          const SizedBox(height: 2),
                        if (bullets.isNotEmpty)
                          ...bullets.map(
                            (b) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 12, bottom: 3),
                              child: Text("• $b", style: t1Body),
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (style.id == "2") {
                  final role = exp.role.trim();
                  final company = exp.company.trim();
                  final when = exp.duration.trim();
                  final companyLine = company.isNotEmpty ? company : "";

                  String? intro;
                  final bulletLines = <String>[];
                  if (bullets.isNotEmpty) {
                    if (t1ShowJobHeader &&
                        bullets.length >= 2 &&
                        (bullets.first.length > 140 ||
                            bullets.first.contains('.'))) {
                      intro = bullets.first;
                      bulletLines.addAll(bullets.skip(1));
                    } else {
                      bulletLines.addAll(bullets);
                    }
                  }

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
                                    fontSize: 10.5,
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
                                    fontSize: 8.75,
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
                                fontSize: 9.1,
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
                                fontSize: 10.0,
                                height: 1.35,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ],
                        if (bulletLines.isNotEmpty) ...[
                          SizedBox(height: intro == null ? 8 : 6),
                          for (final b in bulletLines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                "• $b",
                                textAlign: TextAlign.justify,
                                style: bodyStyleLight.copyWith(
                                  fontFamily: _bodyFf,
                                  fontSize: 10.0,
                                  color: const Color(0xFF374151),
                                  height: 1.35,
                                ),
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
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: Color(0xFF0B2230),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${exp.company}  |  ${exp.duration}",
                          style: TextStyle(
                            fontSize: 8.75,
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
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    exp.duration,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      letterSpacing: 1.0,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                exp.company,
                                style: TextStyle(
                                  fontSize: 9.5,
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
                        "${exp.role}, ${exp.company}",
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        exp.duration,
                        style: TextStyle(
                          fontSize: 8.5,
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
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _contentTitle("EDUCATION", style),
                const SizedBox(height: 6),
                ...eduItems.map<Widget>((e) {
                  final ed = e as Education;
                  final deg = ed.degree.trim();
                  final inst = ed.institution.trim();
                  final yr = ed.year.trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (deg.isNotEmpty)
                          Text(
                            deg,
                            style: TextStyle(
                              fontFamily: _bodyFf,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: const Color(0xFF111111),
                            ),
                          ),
                        if (inst.isNotEmpty) ...[
                          if (deg.isNotEmpty) const SizedBox(height: 2),
                          Text(
                            inst,
                            style: TextStyle(
                              fontFamily: _bodyFf,
                              fontSize: 9.25,
                              height: 1.3,
                              color: Colors.black.withOpacity(0.72),
                            ),
                          ),
                        ],
                        if (yr.isNotEmpty) ...[
                          if (deg.isNotEmpty || inst.isNotEmpty)
                            const SizedBox(height: 2),
                          Text(
                            yr,
                            style: TextStyle(
                              fontFamily: _bodyFf,
                              fontSize: 8.85,
                              height: 1.2,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        ],
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle(style.id == "1" ? "PROJECT" : "PROJECTS", style),
              const SizedBox(height: 10),
              for (final line in proj)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    "• $line",
                    style: style.id == "1"
                        ? const TextStyle(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Color(0xFF111111),
                          )
                        : bodyStyle,
                  ),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle(style.id == "1" ? "COURSES" : "COURSES", style),
              const SizedBox(height: 10),
              for (final line in items)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    "• $line",
                    style: style.id == "1"
                        ? const TextStyle(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Color(0xFF111111),
                          )
                        : bodyStyle,
                  ),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle(style.id == "1" ? "LANGUAGE" : "LANGUAGES", style),
              const SizedBox(height: 10),
              for (final line in items)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    "• $line",
                    style: style.id == "1"
                        ? const TextStyle(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Color(0xFF111111),
                          )
                        : bodyStyle,
                  ),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (style.id == "2")
                _contentTitleTemplate2("CERTIFICATIONS", style)
              else
                _contentTitle(
                  style.id == "1" ? "CERTIFICATION" : "CERTIFICATIONS",
                  style,
                ),
              const SizedBox(height: 10),
              for (final line in items)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    "• $line",
                    style: style.id == "1"
                        ? const TextStyle(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Color(0xFF111111),
                          )
                        : bodyStyle,
                  ),
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
          fontSize: 8.85,
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
                _template1SkillValueWrap(items.join(", "), chipStyle)
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
          fontSize: 8.85,
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
                          style: TextStyle(
                            fontFamily: _bodyFf,
                            fontSize: style.id == "1" ? 9.1 : 9.5,
                            fontWeight: FontWeight.w800,
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle(
                style.id == "1" ? "ACHIEVEMENT" : "ACHIEVEMENTS",
                style,
              ),
              const SizedBox(height: 10),
              for (final line in ach)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    "• ${CategoryEntryDisplay.formatAchievementLine(line)}",
                    style: style.id == "1"
                        ? const TextStyle(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Color(0xFF111111),
                          )
                        : bodyStyle,
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
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF374151),
                  ),
                ),
                if (lines.length > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    lines[1],
                    style: TextStyle(
                      fontSize: 9,
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
                        fontSize: 8.25,
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
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contentTitle(
                style.id == "2" ? "REFERENCE" : "REFERENCES",
                style,
              ),
              const SizedBox(height: 10),
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
              style: TextStyle(
                fontFamily: _bodyFf,
                fontSize: 9.75,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: titleOnWhite(style.accent),
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
            style: TextStyle(
              fontFamily: _bodyFf,
              fontSize: 10,
              fontWeight: FontWeight.w900,
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
              style: TextStyle(
                fontFamily: _bodyFf,
                fontSize: 11,
                fontWeight: FontWeight.w900,
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
          style: TextStyle(
            fontFamily: _bodyFf,
            fontSize: 10,
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
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: accent,
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
                style: TextStyle(
                  fontFamily: _nameFf,
                  fontSize: 18.8,
                  fontWeight: FontWeight.w900,
                  color: onAccent,
                  height: 1.05,
                ),
              ),
              if (role.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  role,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _bodyFf,
                    fontSize: 9.0,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: onAccentMuted,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
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
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: _bodyFf,
              fontSize: 8.3,
              fontWeight: FontWeight.w800,
              height: 1.1,
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
                fontSize: 8.25,
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
              fontSize: 20,
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
                  fontSize: 11,
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
              fontSize: 20,
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
                  fontSize: 10.5,
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
                  fontSize: 9.2,
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
              fontSize: 17.8,
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
                  fontSize: 10.2,
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
                  fontSize: 9.1,
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
                    fontSize: 20,
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
                  fontSize: 10.2,
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
                  fontSize: 9.1,
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
              fontSize: 26,
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
              fontSize: 10.5,
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                    fontSize: 22,
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
                      fontSize: 10.5,
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
                      fontSize: 9.5,
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
    // Matches the "Austin Bronson" vibe: bold name + yellow rule.
    final role =
        data.experiences.isNotEmpty ? data.experiences.first.role : "";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 6,
            width: 150,
            color: style.accent,
          ),
          const SizedBox(height: 10),
          Text(
            (data.name.isNotEmpty ? data.name : "Your Name").toUpperCase(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: Color(0xFF111827),
              height: 1.0,
            ),
          ),
          if (role.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                role.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.55),
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
                    fontSize: 24,
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
                        fontSize: 11,
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data.name.isNotEmpty ? data.name : "Your Name")
                      .toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
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
                      fontSize: 9.5,
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
                          fontSize: 18,
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
                              fontSize: 10,
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
            child: Row(
              children: [
                _miniContactChip(Icons.email, data.email),
                const SizedBox(width: 10),
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
                      fontSize: 18,
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
                        fontSize: 10,
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
                        fontSize: 16,
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
                          fontSize: 9,
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
    return Expanded(
      child: _tappableContactRow(
        uri: uri,
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.95)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  decoration: uri == null ? null : TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
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

  static int rightSectionCapacity({
    required double availableHeight,
    required double availableWidth,
    required List<Map<String, dynamic>> sections,
    String templateId = "",
  }) {
    // Rough height model to avoid overflow. Packs as many sections as fit.
    double used = 0;
    int count = 0;

    // Chars per line: slightly tighter than 5.2px/char with compact preview fonts.
    final charsPerLine = math.max(24, (availableWidth / 4.95).floor());
    final t1 = templateId == "1";

    for (final s in sections) {
      final type = s["type"];
      double h = 0;

      if (type == "section") {
        final title = (s["title"] ?? "").toString().toLowerCase();
        final isProfileSummary =
            title.contains("profile") || title.contains("summary");
        final content = (s["content"] ?? "").toString();
        var lines = (content.length / charsPerLine).ceil();
        // Prevent long summaries from consuming an entire first page in preview.
        // This keeps page 1 showing Experience/Education like real ATS resumes.
        if (!t1 && isProfileSummary) lines = math.min(lines, 8);
        h = 46 +
            lines *
                (t1
                    ? 13.6
                    : (templateId == "2" ? 16.4 : 15.0));
        if (t1) h += 2;
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
            if (bullets.length >= 2 &&
                (bullets.first.length > 140 ||
                    bullets.first.contains('.'))) {
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
          // Slightly optimistic for template 1 so pages 1–2 pack like page 3; clip is rare.
          h = t1wh ? 46 : 8;
          for (var i = 0; i < items.length; i++) {
            final exp = items[i] as Experience;
            final n =
                exp.description.where((b) => b.trim().isNotEmpty).length;
            h += (t1jh ? 48 : 10) + n * (t1 ? 14.8 : 17.0);
          }
          h += t1 ? 14 : 18;
        }
      } else if (type == "education") {
        final items = (s["items"] as List?) ?? const [];
        h = t1 ? 44 + items.length * 34.0 : 52 + items.length * 44.0;
      } else if (type == "skills_categorized") {
        final groups = (s["groups"] as List?) ?? const [];
        h = t1 ? 44 : 52;
        for (final g in groups) {
          final value = (g is Map && g["value"] != null)
              ? g["value"].toString()
              : "";
          if (t1) {
            final parts = _splitSkillListValue(value).length;
            final approxChipsPerRow =
                math.max(1, (availableWidth / 72).floor());
            final chipRows = math.max(1, (parts / approxChipsPerRow).ceil());
            h += 22 + chipRows * 26.0;
          } else {
            h += 20;
            h += (value.length / charsPerLine).ceil() * 15.0;
          }
        }
      } else if (type == "projects") {
        final items = (s["items"] as List?) ?? const [];
        h = 52 + items.length * 22.0;
      } else if (type == "courses" || type == "certifications") {
        final items = (s["items"] as List?) ?? const [];
        h = t1 ? 44 : 52;
        for (final it in items) {
          final line = it.toString();
          final wrapped = math.max(1, (line.length / charsPerLine).ceil());
          h += (t1 ? 15.8 : 17.0) * wrapped + (t1 ? 5.0 : 6.0);
        }
      } else if (type == "skills") {
        final items = (s["items"] as List?) ?? const [];
        final joined = items.map((e) => e.toString()).join(", ");
        final lines = math.max(1, (joined.length / charsPerLine).ceil());
        h = (t1 ? 44 : 52) + lines * (t1 ? 15.0 : 16.0);
      } else if (type == "achievement") {
        final items = (s["items"] as List?) ?? const [];
        h = 52 + items.length * 18.0;
      } else if (type == "references") {
        final items = (s["items"] as List?) ?? const [];
        h = 56 + items.length * 42.0;
      } else {
        // Unknown section types: assume small.
        h = 56;
      }

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
