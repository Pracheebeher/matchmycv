import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// After a PDF is built, user picks system share vs in-app print (ISO A4 hints).
enum ResumePdfPostExportChoice { share, print }

Future<ResumePdfPostExportChoice?> showResumePdfPostExportSheet(
  BuildContext context, {
  required AppLocalizations strings,
}) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return showModalBottomSheet<ResumePdfPostExportChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withOpacity(0.94),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.18)),
                left: BorderSide(color: Colors.white.withOpacity(0.08)),
                right: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 8 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Text(
                    strings.resumeExportReadyTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PostExportCard(
                    accent: const Color(0xFF06B6D4),
                    icon: Icons.ios_share_rounded,
                    title: strings.resumeExportShareToApps,
                    description: strings.resumeExportShareToAppsDescription,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx, ResumePdfPostExportChoice.share);
                    },
                  ),
                  const SizedBox(height: 10),
                  _PostExportCard(
                    accent: const Color(0xFF22C55E),
                    icon: Icons.print_rounded,
                    title: strings.resumeExportPrintOrSavePdf,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx, ResumePdfPostExportChoice.print);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.75),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      strings.resumeExportCancel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PostExportCard extends StatelessWidget {
  const _PostExportCard({
    required this.accent,
    required this.icon,
    required this.title,
    this.description,
    required this.onTap,
  });

  final Color accent;
  final IconData icon;
  final String title;
  /// Second line (e.g. Email, Google Drive). Omit for a single-line row.
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = description?.trim() ?? '';
    final hasSub = sub.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment:
                  hasSub ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withOpacity(0.35),
                        accent.withOpacity(0.12),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                      if (hasSub) ...[
                        const SizedBox(height: 6),
                        Text(
                          sub,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.35,
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
      ),
    );
  }
}
