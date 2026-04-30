import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfTextExtractorService {
  static Future<String> extractText(File file) async {
    final bytes = await file.readAsBytes();
    return extractTextFromBytes(bytes);
  }

  static Future<String> extractTextFromBytes(Uint8List bytes) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      return extractor.extractText();
    } finally {
      document?.dispose();
    }
  }
}