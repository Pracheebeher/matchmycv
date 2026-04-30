import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pdf_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_toast.dart';
import '../widgets/uniform_app_bar.dart';

class CoverLetterPreviewPage extends StatefulWidget {
  final String letter;

  const CoverLetterPreviewPage({
    super.key,
    required this.letter,
  });

  @override
  State<CoverLetterPreviewPage> createState() => _CoverLetterPreviewPageState();
}

class _CoverLetterPreviewPageState extends State<CoverLetterPreviewPage> {
  bool _isDownloading = false;
  bool _isSharing = false;
  bool _isCopying = false;

  List<String> _paginateByLayout({
    required String input,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    int maxPages = 10,
  }) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return const [''];

    final pages = <String>[];
    var remaining = cleaned;

    while (remaining.isNotEmpty && pages.length < maxPages) {
      final painter = TextPainter(
        text: TextSpan(text: remaining, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      var endIndex = painter
          .getPositionForOffset(Offset(maxWidth, maxHeight))
          .offset;

      if (endIndex <= 0) {
        endIndex = remaining.length.clamp(0, 200);
      }

      if (endIndex < remaining.length) {
        final lookbackStart = (endIndex - 400).clamp(0, endIndex);
        final slice = remaining.substring(lookbackStart, endIndex);
        final lastPara = slice.lastIndexOf('\n\n');
        final lastLine = slice.lastIndexOf('\n');
        final lastSpace = slice.lastIndexOf(' ');
        final cut = [lastPara, lastLine, lastSpace].reduce((a, b) => a > b ? a : b);
        if (cut > 0) {
          endIndex = lookbackStart + cut;
        }
      }

      final pageText = remaining.substring(0, endIndex).trimRight();
      pages.add(pageText);
      remaining = remaining.substring(endIndex).trimLeft();
    }

    return pages.isEmpty ? const [''] : pages;
  }

  // 📝 FILE NAME DIALOG
  Future<String?> _askFileName(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final controller = TextEditingController(text: "cover_letter");

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.saveCoverLetter),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: t.fileNameHint),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(t.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final letter = widget.letter;
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      appBar: UniformAppBar.material(t.coverLetterTitle),
      body: Stack(
        children: [
          const _FuturisticBackdrop(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final maxW = c.maxWidth.clamp(280.0, 520.0);
                        final pageW = math.min(maxW, 520.0);
                        const a4Ratio = 1 / 1.414; // width / height
                        final pageH = pageW / a4Ratio;

                        // Inner page paddings should feel like a real cover letter.
                        const padL = 28.0;
                        const padT = 32.0;
                        const padR = 28.0;
                        const padB = 32.0;

                        const baseColor = Color(0xFF0F172A);
                        const lineHeight = 1.52;
                        var fontSize = 11.4;
                        List<String> pages = [];
                        TextStyle pageTextStyle = const TextStyle(
                          fontSize: 11.4,
                          height: lineHeight,
                          color: baseColor,
                        );

                        final maxTextW =
                            (pageW - padL - padR).clamp(120.0, pageW);
                        final maxTextH =
                            (pageH - padT - padB).clamp(120.0, pageH);

                        while (fontSize >= 8.0) {
                          pageTextStyle = TextStyle(
                            fontSize: fontSize,
                            height: lineHeight,
                            color: baseColor,
                          );
                          pages = _paginateByLayout(
                            input: letter,
                            style: pageTextStyle,
                            maxWidth: maxTextW,
                            maxHeight: maxTextH,
                          );
                          if (pages.length <= 1) break;
                          fontSize -= 0.22;
                        }
                        if (pages.length > 1) {
                          pages = [pages.first];
                        }

                        return Center(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                children: [
                                  for (var i = 0; i < pages.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 16),
                                    SizedBox(
                                      width: pageW,
                                      height: pageH,
                                      child: _PaperPreview(
                                        text: pages[i],
                                        bodyStyle: pageTextStyle,
                                        padding: const EdgeInsets.fromLTRB(
                                          padL,
                                          padT,
                                          padR,
                                          padB,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ActionDock(
                    isDownloading: _isDownloading,
                    isSharing: _isSharing,
                    isCopying: _isCopying,
                    onCopy: () async {
                      if (_isCopying) return;
                      setState(() => _isCopying = true);
                      try {
                        await Clipboard.setData(ClipboardData(text: letter));
                        if (!mounted) return;
                        AppToast.info(context, t.copiedToClipboard);
                      } finally {
                        if (mounted) setState(() => _isCopying = false);
                      }
                    },
                    onShare: () async {
                      if (_isSharing) return;
                      setState(() => _isSharing = true);
                      try {
                        await PdfService.shareCoverLetter(letter);
                      } finally {
                        if (mounted) setState(() => _isSharing = false);
                      }
                    },
                    onDownload: () async {
                      if (_isDownloading) return;
                      final fileName = await _askFileName(context);
                      if (fileName == null || fileName.isEmpty) return;
                      setState(() => _isDownloading = true);
                      try {
                        await PdfService.downloadCoverLetter(
                          text: letter,
                          fileName: fileName,
                        );
                        if (!mounted) return;
                        AppToast.success(
                          context,
                          t.successfullyDownloaded,
                        );
                      } finally {
                        if (mounted) setState(() => _isDownloading = false);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Futuristic UI bits (self-contained, no external deps) ---

class _FuturisticBackdrop extends StatelessWidget {
  const _FuturisticBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.65, -0.75),
                radius: 1.2,
                colors: [
                  Color(0xFF1B2A4A),
                  Color(0xFF070A12),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: -140,
          top: -140,
          child: _GlowOrb(color: const Color(0xFF7C3AED), size: 320),
        ),
        Positioned(
          right: -160,
          bottom: -180,
          child: _GlowOrb(color: const Color(0xFF06B6D4), size: 360),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.35),
            color.withOpacity(0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

class _PaperPreview extends StatelessWidget {
  final String text;
  final TextStyle bodyStyle;
  final EdgeInsets padding;
  const _PaperPreview({
    required this.text,
    required this.bodyStyle,
    this.padding = const EdgeInsets.fromLTRB(34, 38, 34, 38),
  });

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .trim()
        .split(RegExp(r'\n\s*\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: const Color(0xFFF8FAFC),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: padding,
                child: DefaultTextStyle(
                  style: bodyStyle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < paragraphs.length; i++) ...[
                        Text(paragraphs[i]),
                        if (i != paragraphs.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 8,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF7C3AED),
                      Color(0xFF06B6D4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionDock extends StatelessWidget {
  final bool isDownloading;
  final bool isSharing;
  final bool isCopying;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDownload;

  const _ActionDock({
    required this.isDownloading,
    required this.isSharing,
    required this.isCopying,
    required this.onCopy,
    required this.onShare,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final busy = isDownloading || isSharing || isCopying;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DockButton(
              label: t.copy,
              icon: Icons.content_copy,
              loading: isCopying,
              onTap: busy ? null : onCopy,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DockButton(
              label: t.share,
              icon: Icons.ios_share,
              loading: isSharing,
              onTap: busy ? null : onShare,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DockButton(
              label: t.download,
              icon: Icons.download,
              loading: isDownloading,
              onTap: busy ? null : onDownload,
              filled: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;
  final bool filled;

  const _DockButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled ? Colors.black : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: filled
                ? Colors.white
                : Colors.white.withOpacity(0.08),
            border: Border.all(
              color: filled
                  ? Colors.white.withOpacity(0.0)
                  : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(fg),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12,
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