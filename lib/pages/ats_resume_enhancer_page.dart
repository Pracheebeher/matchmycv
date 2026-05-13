import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_ats_service.dart';
import '../services/pdf_service.dart';
import 'ats_uploaded_pdf_text_editor_page.dart';
import 'pdf_preview_page.dart';
import '../widgets/app_toast.dart';
import '../widgets/uniform_app_bar.dart';

enum _DownloadExportKind {
  /// Same bytes as the uploaded file — preserves layout, fonts, and design.
  originalPdf,
  /// AI-enhanced plain text rendered with a simple PDF layout (not your template).
  enhancedTextPdf,
}

class ATSResumeEnhancerPage extends StatefulWidget {
  final String originalText;
  final String enhancedText;
  final String atsFeedback;
  final File? uploadedPdf;

  const ATSResumeEnhancerPage({
    super.key,
    required this.originalText,
    required this.enhancedText,
    required this.atsFeedback,
    this.uploadedPdf,
  });

  @override
  State<ATSResumeEnhancerPage> createState() => _ATSResumeEnhancerPageState();
}

class _ATSResumeEnhancerPageState extends State<ATSResumeEnhancerPage> {
  late final TextEditingController _enhancedController;
  late final TextEditingController _originalController;
  bool _downloading = false;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _enhancedController = TextEditingController(text: widget.enhancedText);
    _originalController = TextEditingController(text: widget.originalText);
  }

  @override
  void dispose() {
    _enhancedController.dispose();
    _originalController.dispose();
    super.dispose();
  }

  List<String> _feedbackBullets() {
    final raw = widget.atsFeedback.trim();
    if (raw.isEmpty) return const [];
    final lines = raw
        .split(RegExp(r'[\n•\-]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.length >= 3) return lines.take(24).toList();
    // Fallback: split sentences.
    return raw
        .split(RegExp(r'\.\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(24)
        .toList();
  }

  Future<void> _reEnhance() async {
    final resumeText = _originalController.text.trim();
    if (resumeText.isEmpty) {
      AppToast.validation(
        context,
        AppLocalizations.of(context).resumeTextRequiredShort,
      );
      return;
    }
    try {
      final enhanced = await AIATSService.enhanceResume(
        resumeText: resumeText,
        atsFeedback: widget.atsFeedback,
      );
      if (!mounted) return;
      _enhancedController.text = enhanced;
      AppToast.success(
        context,
        AppLocalizations.of(context).enhancementUpdatedShort,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        AppLocalizations.of(context).atsCheckerErrorShort,
      );
    }
  }

  String _basenameWithoutExtension(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    if (name.endsWith('.pdf')) {
      return name.substring(0, name.length - 4);
    }
    return name;
  }

  String _defaultExportBaseName() {
    final uploaded = widget.uploadedPdf?.path;
    if (uploaded != null && uploaded.trim().isNotEmpty) {
      return '${_basenameWithoutExtension(uploaded)}_enhanced';
    }
    return 'enhanced_resume';
  }

  /// Base name for exporting the original upload (no "_enhanced" suffix).
  String _defaultOriginalBaseName() {
    final uploaded = widget.uploadedPdf?.path;
    if (uploaded != null && uploaded.trim().isNotEmpty) {
      return _basenameWithoutExtension(uploaded);
    }
    return 'resume';
  }

  String _sanitizeFileBaseName(String raw) {
    var s = raw.trim();
    if (s.toLowerCase().endsWith('.pdf')) {
      s = s.substring(0, s.length - 4).trim();
    }
    s = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) s = 'enhanced_resume';
    if (s.length > 96) s = s.substring(0, 96).trim();
    return s;
  }

  Future<String?> _promptExportFileName(String initial) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          title: const Text(
            'Save as',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'File name (without .pdf)',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF60A5FA)),
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
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF60A5FA),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null) return null;
    final cleaned = _sanitizeFileBaseName(name);
    return cleaned;
  }

  Future<void> _download() async {
    final text = _enhancedController.text.trim();
    if (text.isEmpty) {
      AppToast.validation(
        context,
        AppLocalizations.of(context).resumeTextRequiredShort,
      );
      return;
    }

    final chosen = await _promptExportFileName(_defaultExportBaseName());
    if (chosen == null) return;

    setState(() => _downloading = true);
    try {
      final file = await PdfService.buildResumePdfFromTextFile(
        text: text,
        fileName: chosen,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: '$chosen.pdf')],
        text: 'Enhanced resume',
      );
      if (!mounted) return;
      AppToast.success(
        context,
        AppLocalizations.of(context).successfullyDownloaded,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        AppLocalizations.of(context).downloadCouldNotComplete,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openPreview() async {
    final text = _enhancedController.text.trim();
    if (text.isEmpty) {
      AppToast.validation(
        context,
        AppLocalizations.of(context).resumeTextRequiredShort,
      );
      return;
    }

    setState(() => _previewLoading = true);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = await PdfService.buildResumePdfFromTextFile(
        text: text,
        fileName: "enhanced_resume_preview_$stamp",
      );
      final exists = await file.exists();
      if (!exists) {
        throw StateError("Preview file was not created.");
      }
      final bytes = await file.length();
      if (bytes <= 0) {
        throw StateError("Preview PDF is empty.");
      }
      if (!mounted) return;
      setState(() => _previewLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewPage(
            file: file,
            title: AppLocalizations.of(context)!.resumePreviewTitle,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _previewLoading = false);
      AppToast.error(
        context,
        AppLocalizations.of(context).atsCheckerErrorShort,
      );
    }
  }

  /// Exact uploaded PDF + text-only editing (extracted content). Updates enhancement when text changes.
  Future<void> _openPdfTextEditor() async {
    if (widget.uploadedPdf == null) {
      AppToast.validation(
        context,
        AppLocalizations.of(context).noPdfAttachedSession,
      );
      return;
    }

    final updated = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AtsUploadedPdfTextEditorPage(
          pdf: widget.uploadedPdf!,
          initialText: _originalController.text,
        ),
      ),
    );

    if (!mounted || updated == null) return;
    if (updated == _originalController.text) return;

    _originalController.text = updated;
    await _reEnhance();
  }

  Widget _buildPdfEditorTab() {
    if (widget.uploadedPdf == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No PDF on this session. Use AI & text to edit and export.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              height: 1.35,
            ),
          ),
        ),
      );
    }
    final path = widget.uploadedPdf!.path;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your uploaded resume (exact PDF)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      path.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).printOrSavePdfTooltip,
                onPressed: () async {
                  final t = AppLocalizations.of(context);
                  try {
                    final r = await PdfService.presentSystemPrintForPdf(
                      widget.uploadedPdf!,
                      name: path.split('/').last,
                    );
                    if (!mounted) return;
                    if (r == null) {
                      AppToast.error(context, t.printingUnavailable);
                    }
                  } catch (_) {
                    if (!mounted) return;
                    AppToast.error(context, t.printingFailed);
                  }
                },
                icon: const Icon(Icons.print_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: 'Full screen',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PdfPreviewPage(
                        file: widget.uploadedPdf!,
                        title: 'Uploaded resume',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_full_rounded),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: Colors.white,
                child: PDFView(
                  key: ValueKey(path),
                  filePath: path,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  fitPolicy: FitPolicy.BOTH,
                  onError: (e) {
                    AppToast.error(
                      context,
                      AppLocalizations.of(context).pdfOpenFailed,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pinch and scroll to review. Use the Visual editor tab to edit text next to this PDF.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualEditorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: _glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withOpacity(0.10),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: const Icon(
                    Icons.design_services_rounded,
                    color: Color(0xFF60A5FA),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PDF text editor',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Opens your exact uploaded PDF above an editable text area. '
                        'Only the text is editable; the PDF preview stays your original file.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openPdfTextEditor,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text(
                'Open visual resume editor',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiTextTab(List<String> bullets) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _glass(
              padding: EdgeInsets.zero,
              child: TabBar(
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withOpacity(0.10),
                ),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.65),
                tabs: const [
                  Tab(text: 'Suggestions'),
                  Tab(text: 'Enhanced'),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TabBarView(
                children: [
                  _glass(
                    child: bullets.isEmpty
                        ? Text(
                            'No suggestions available.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              height: 1.35,
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: bullets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final s = bullets[i];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF34D399),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      s,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.86),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  _glass(
                    child: TextField(
                      controller: _enhancedController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Edit your enhanced resume text…',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final bullets = _feedbackBullets();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: UniformAppBar.material(
        t.resumeEnhancerTitle,
        actions: [
          IconButton(
            tooltip: 'PDF text editor',
            icon: const Icon(Icons.article_outlined),
            onPressed: _openPdfTextEditor,
          ),
        ],
      ),
      body: Stack(
        children: [
          const _EnhancerBackground(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: _glass(
                            padding: EdgeInsets.zero,
                            child: TabBar(
                              isScrollable: true,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.white.withOpacity(0.10),
                              ),
                              dividerColor: Colors.transparent,
                              labelColor: Colors.white,
                              unselectedLabelColor:
                                  Colors.white.withOpacity(0.65),
                              tabs: const [
                                Tab(text: 'Original PDF'),
                                Tab(text: 'Visual editor'),
                                Tab(text: 'AI & text'),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildPdfEditorTab(),
                              _buildVisualEditorTab(),
                              _buildAiTextTab(bullets),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 88),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: _glass(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _previewLoading ? null : _openPreview,
                        icon: _previewLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.visibility_rounded),
                        label: Text(_previewLoading ? "Opening…" : "Preview"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.18),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _downloading ? null : _download,
                        icon: _downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(_downloading ? "Saving…" : "Download"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF60A5FA),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _glass({
  required Widget child,
  EdgeInsets? padding,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    ),
  );
}

class _EnhancerBackground extends StatelessWidget {
  const _EnhancerBackground();

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
          child: _blob(const Color(0xFFA78BFA)),
        ),
        Positioned(
          bottom: -110,
          right: -70,
          child: _blob(const Color(0xFF60A5FA)),
        ),
        Positioned(
          top: 180,
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

class ATSResumeTextPreviewPage extends StatelessWidget {
  final String text;

  const ATSResumeTextPreviewPage({super.key, required this.text});

  List<String> _paginateByLayout({
    required String input,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
  }) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return const [""];

    final pages = <String>[];
    var remaining = cleaned;

    while (remaining.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(text: remaining, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      var endIndex = painter
          .getPositionForOffset(Offset(maxWidth, maxHeight))
          .offset;

      // If even one line can't fit (extremely small constraints), force progress.
      if (endIndex <= 0) {
        endIndex = remaining.length.clamp(0, 200);
      }

      // Try not to cut mid-paragraph/word when possible.
      if (endIndex < remaining.length) {
        final lookbackStart = (endIndex - 200).clamp(0, endIndex);
        final slice = remaining.substring(lookbackStart, endIndex);
        final lastPara = slice.lastIndexOf("\n\n");
        final lastLine = slice.lastIndexOf("\n");
        final lastSpace = slice.lastIndexOf(" ");
        final cut = [lastPara, lastLine, lastSpace].reduce((a, b) => a > b ? a : b);
        if (cut > 0) {
          endIndex = lookbackStart + cut;
        }
      }

      final pageText = remaining.substring(0, endIndex).trimRight();
      pages.add(pageText);

      remaining = remaining.substring(endIndex).trimLeft();
    }

    return pages.isEmpty ? const [""] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: UniformAppBar.material(t.resumePreviewTitle),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const outerMargin = 16.0;
          const innerPad = 24.0;
          const a4Ratio = 1 / 1.414;

          final maxCardWidth =
              (constraints.maxWidth - outerMargin * 2).clamp(260.0, 620.0);
          final pageHeight = maxCardWidth / a4Ratio;

          final maxTextWidth = maxCardWidth - innerPad * 2;
          final maxTextHeight = pageHeight - innerPad * 2 - 18; // footer space

          const textStyle = TextStyle(
            fontSize: 12,
            height: 1.35,
            color: Colors.black,
          );

          final pages = _paginateByLayout(
            input: text,
            style: textStyle,
            maxWidth: maxTextWidth,
            maxHeight: maxTextHeight,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Center(
              child: Column(
                children: [
                  for (var i = 0; i < pages.length; i++) ...[
                    if (i > 0) const SizedBox(height: 20),
                    SizedBox(
                      width: maxCardWidth + outerMargin * 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: outerMargin,
                        ),
                        child: AspectRatio(
                          aspectRatio: a4Ratio,
                          child: Material(
                            color: Colors.white,
                            elevation: 6,
                            child: Padding(
                              padding: const EdgeInsets.all(innerPad),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Text(
                                      pages[i],
                                      style: textStyle,
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Text(
                                      "Page ${i + 1} of ${pages.length}",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

