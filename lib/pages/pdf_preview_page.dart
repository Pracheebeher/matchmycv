import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/pdf_service.dart';
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

  Future<void> _printOrSavePdf(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final name = file.path.split(Platform.pathSeparator).last;
    try {
      final result = await PdfService.presentSystemPrintForPdf(
        file,
        name: name,
      );
      if (!context.mounted) return;
      if (result == null) {
        AppToast.error(context, t.printingUnavailable);
        return;
      }
    } catch (_) {
      if (!context.mounted) return;
      AppToast.error(context, t.printingFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: UniformAppBar.material(
        title,
        actions: [
          IconButton(
            tooltip: t.printOrSavePdfTooltip,
            icon: const Icon(Icons.print_rounded),
            onPressed: () => _printOrSavePdf(context),
          ),
        ],
      ),
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

