import 'package:flutter/material.dart';

/// Bottom actions on the resume preview screen — **not** the resume canvas.
class ResumePreviewBottomActions extends StatelessWidget {
  const ResumePreviewBottomActions({
    super.key,
    required this.tailorTitle,
    required this.tailorSubtitle,
    required this.pdfTitle,
    required this.pdfSubtitle,
    required this.pdfBusyLabel,
    required this.pdfDockHint,
    required this.tailoringBusy,
    required this.pdfBusy,
    required this.onTailor,
    required this.onSavePdf,
  });

  final String tailorTitle;
  final String tailorSubtitle;
  final String pdfTitle;
  final String pdfSubtitle;
  final String pdfBusyLabel;
  final String pdfDockHint;
  final bool tailoringBusy;
  final bool pdfBusy;
  final VoidCallback onTailor;
  final VoidCallback onSavePdf;

  static const Color _surface = Color(0xFF020617);
  static const Color _surfaceEdge = Color(0xFF0F172A);
  static const Color _tailorStroke = Color(0xFF7C3AED);
  static const Color _pdfFill = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Material(
          elevation: 16,
          shadowColor: Colors.black.withOpacity(0.55),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          color: _surface,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_surfaceEdge, _surface],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    pdfSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _pdfFill,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _pdfFill.withOpacity(0.45),
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: pdfBusy ? null : onSavePdf,
                      icon: pdfBusy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white.withOpacity(0.95),
                              ),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 22),
                      label: Text(
                        pdfBusy ? pdfBusyLabel : pdfTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.92),
                        side: const BorderSide(color: _tailorStroke, width: 1.4),
                        backgroundColor: _tailorStroke.withOpacity(0.12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: tailoringBusy ? null : onTailor,
                      child: Row(
                        children: [
                          if (tailoringBusy)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Color(0xFFE9D5FF),
                              ),
                            )
                          else
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 22,
                              color: Colors.purple.shade100,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tailorTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  tailorSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10.5,
                                    color: Colors.white.withOpacity(0.62),
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Colors.amber.shade200.withOpacity(0.85),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pdfDockHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.58),
                            fontSize: 10.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
