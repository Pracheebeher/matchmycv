import 'dart:io';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_toast.dart';
import '../widgets/uniform_app_bar.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

/// Shows the exact uploaded PDF and a plain-text editor for the extracted resume.
/// Editing does not change the PDF bytes; it updates the text used for AI enhancement.
class AtsUploadedPdfTextEditorPage extends StatefulWidget {
  final File pdf;
  final String initialText;

  const AtsUploadedPdfTextEditorPage({
    super.key,
    required this.pdf,
    required this.initialText,
  });

  @override
  State<AtsUploadedPdfTextEditorPage> createState() =>
      _AtsUploadedPdfTextEditorPageState();
}

class _AtsUploadedPdfTextEditorPageState
    extends State<AtsUploadedPdfTextEditorPage> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _finish() {
    Navigator.of(context).pop<String>(_textController.text);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (!didPop) {
          _finish();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070A12),
        appBar: UniformAppBar.material(
          'Resume PDF editor',
          actions: [
            TextButton(
              onPressed: _finish,
              child: const Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF60A5FA),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Your uploaded file (read-only preview). Edit the text below only.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            Expanded(
              flex: 11,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: Colors.white,
                    child: PDFView(
                      key: ValueKey(widget.pdf.path),
                      filePath: widget.pdf.path,
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Resume text',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 9,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.35,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF60A5FA)),
                    ),
                    hintText: 'Edit resume text…',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                    ),
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
