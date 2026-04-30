import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_toast.dart';
import '../widgets/uniform_app_bar.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class PdfPreviewPage extends StatelessWidget {
  final File file;
  final String title;

  const PdfPreviewPage({
    super.key,
    required this.file,
    this.title = "Preview",
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: UniformAppBar.material(title),
      // PDFView is GPU-heavy; isolating repaints reduces jank when opened from
      // screens that also use BackdropFilter / animated gradients.
      body: RepaintBoundary(
        child: ColoredBox(
          color: Colors.black,
          child: PDFView(
            filePath: file.path,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            fitPolicy: FitPolicy.BOTH,
            onError: (error) {
              AppToast.error(
                context,
                AppLocalizations.of(context).pdfOpenFailed,
              );
            },
            onPageError: (page, error) {
              AppToast.error(
                context,
                AppLocalizations.of(context).pdfOpenFailed,
              );
            },
          ),
        ),
      ),
    );
  }
}

