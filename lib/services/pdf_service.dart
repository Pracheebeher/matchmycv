import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/resume_model.dart';
import '../utils/category_entry_display.dart';
import '../utils/pdf_export_ats_markers.dart';

/// A resume PDF written to a temp file, ready for share or in-app print.
typedef ResumePdfExport = ({File file, String displayName});

class PdfService {
  /// ISO A4 with **no margins** for styled PNG export and preview height math.
  ///
  /// Width/height are the **same thousandths-of-an-inch** values Android uses for
  /// [PrintAttributes.MediaSize.ISO_A4] (8270×11690 mils). The `printing` plugin
  /// maps [PdfPageFormat] to a predefined [MediaSize] only when the converted
  /// mils match within a small tolerance; using exact `21×29.7 cm` in points can
  /// yield 8267×11692 mils and miss `ISO_A4`, so the system print UI falls back
  /// to `UNKNOWN` and some devices default **Save as PDF** to US Letter.
  static const PdfPageFormat styledTemplateExportPageFormat = PdfPageFormat(
    8270 * 72 / 1000.0,
    11690 * 72 / 1000.0,
    marginAll: 0,
  );

  /// Same **MediaBox** as [styledTemplateExportPageFormat] with [PdfPageFormat.a4]-style
  /// `2 cm` margins. Used for ATS / text resume [pw.MultiPage] exports so a file
  /// opened from the share sheet (Gmail, Drive, Files) matches the styled PDF’s
  /// A4 page size instead of metric `21×29.7 cm` points (8267×11692 mils), which
  /// some pipelines treat as “unknown” and default to US Letter for print/preview.
  static const PdfPageFormat documentExportPageFormat = PdfPageFormat(
    8270 * 72 / 1000.0,
    11690 * 72 / 1000.0,
    marginAll: 2.0 * PdfPageFormat.cm,
  );

  /// Normalizes a preview screenshot PNG into a pixel-exact ISO A4 canvas so it
  /// can be embedded with [pw.BoxFit.cover] / [pw.BoxFit.fill] without skew.
  static Future<Uint8List> _normalizePreviewPngToA4(Uint8List pngBytes) async {
    final a4w = styledTemplateExportPageFormat.width;
    final a4h = styledTemplateExportPageFormat.height;

    final codec = await ui.instantiateImageCodec(pngBytes);
    try {
      final frame = await codec.getNextFrame();
      final src = frame.image;
      try {
        // About 2.8 px/pt: sharp enough, reasonable file size.
        const targetW = 1654;
        final targetH = (targetW * a4h / a4w).round();

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );

        final sw = src.width.toDouble();
        final sh = src.height.toDouble();
        final scale = math.min(targetW / sw, targetH / sh);
        final dw = sw * scale;
        final dh = sh * scale;
        final dx = (targetW - dw) / 2;
        final dy = (targetH - dh) / 2;

        canvas.drawImageRect(
          src,
          ui.Rect.fromLTWH(0, 0, sw, sh),
          ui.Rect.fromLTWH(dx, dy, dw, dh),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );

        final picture = recorder.endRecording();
        ui.Image out;
        try {
          out = await picture.toImage(targetW, targetH);
        } finally {
          picture.dispose();
        }
        try {
          final bd = await out.toByteData(format: ui.ImageByteFormat.png);
          if (bd == null) {
            throw StateError('Failed to encode normalized PNG.');
          }
          return bd.buffer.asUint8List();
        } finally {
          out.dispose();
        }
      } finally {
        src.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static String _resumePlainTextForAts(ResumeData data) {
    final b = StringBuffer();
    void addLine(String s) {
      final t = _sanitizeTextForPdf(s).trim();
      if (t.isEmpty) return;
      b.writeln(t);
    }

    addLine(PdfExportAtsMarkers.begin);
    addLine(data.name);
    if (data.email.trim().isNotEmpty) addLine('Email: ${data.email}');
    if (data.phone.trim().isNotEmpty) addLine('Phone: ${data.phone}');

    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (links.isNotEmpty) {
      addLine('Links: ${links.join(" | ")}');
    }

    String firstNonEmpty(String key) {
      for (final s in data.categories[key] ?? const <String>[]) {
        final t = s.trim();
        if (t.isNotEmpty) return t;
      }
      return '';
    }

    final city = firstNonEmpty('City');
    final country = firstNonEmpty('Country');
    if (city.isNotEmpty) addLine('City: $city');
    if (country.isNotEmpty) addLine('Country: $country');
    if (city.isEmpty && country.isEmpty) {
      final legacy = firstNonEmpty('Location');
      if (legacy.isNotEmpty) addLine('Location: $legacy');
    }

    if (data.summary.trim().isNotEmpty) {
      addLine('Summary: ${data.summary}');
    }

    if (data.skills.isNotEmpty) {
      final skills = data.skills.map((s) => s.trim()).where((s) => s.isNotEmpty);
      addLine('Skills: ${skills.join(", ")}');
    }

    if (data.experiences.isNotEmpty) {
      addLine('Experience:');
      for (final e in data.experiences) {
        final header = '${e.role} - ${e.company} (${e.duration})'.trim();
        addLine('- $header');
        for (final d in e.description) {
          final t = d.trim();
          if (t.isNotEmpty) addLine('  • $t');
        }
      }
    }

    if (data.educationList.isNotEmpty) {
      addLine('Education:');
      for (final e in data.educationList) {
        addLine('- ${e.degree} - ${e.institution} (${e.year})');
      }
    }

    // Add any remaining categories (certs, projects, etc.)
    final skip = <String>{
      'Links',
      'Location',
      'City',
      'Country',
      'Languages',
      'Hobbies',
    };
    for (final entry in data.categories.entries) {
      final k = entry.key;
      if (skip.contains(k)) continue;
      final values =
          entry.value.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (values.isEmpty) continue;
      final display = k == 'Achievements'
          ? CategoryEntryDisplay.sanitizeAchievementDisplayList(values)
          : values;
      addLine('$k: ${display.join(" | ")}');
    }

    final langs = (data.categories["Languages"] ?? const <String>[])
        .map(CategoryEntryDisplay.normalizeLanguageStorage)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (langs.isNotEmpty) {
      addLine('Languages:');
      for (final l in langs) {
        addLine('- ${CategoryEntryDisplay.formatLanguageEnglish(l)}');
      }
    }

    final hobbiesForAts = CategoryEntryDisplay.sanitizeHobbyItems(
      data.categories["Hobbies"] ?? const <String>[],
    );
    if (hobbiesForAts.isNotEmpty) {
      addLine('Hobbies:');
      for (final h in hobbiesForAts) {
        addLine('- $h');
      }
    }

    if (data.targetJobDescription.trim().isNotEmpty) {
      addLine('Target job: ${data.targetJobDescription}');
    }

    addLine(PdfExportAtsMarkers.end);
    return b.toString().trim();
  }

  static String? _extractFirstWebUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    // Prefer an explicit URL in the string.
    final m = RegExp(
      r'(https?://\S+|www\.\S+|linkedin\.com/\S+)',
      caseSensitive: false,
    ).firstMatch(t);
    final candidate = (m?.group(0) ?? t).trim();

    // Strip common trailing punctuation that often follows pasted links.
    var cleaned = candidate.replaceAll(RegExp(r'[)\],.]+$'), '').trim();
    if (cleaned.isEmpty) return null;

    // Already has a scheme.
    if (cleaned.contains('://')) return cleaned;

    // Looks like a host/path; assume https.
    if (cleaned.toLowerCase().startsWith('www.') ||
        cleaned.toLowerCase().contains('linkedin.com/')) {
      return 'https://$cleaned';
    }

    return null;
  }

  static String? _mailtoUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.contains('@')) return null;
    return 'mailto:$t';
  }

  static String? _telUrl(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;
    return 'tel:$digits';
  }

  static String _jdSnippet(String raw, int maxChars) {
    final cleaned = _sanitizeTextForPdf(raw);
    final t = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars - 1)}…';
  }

  static List<pw.Widget> _pdfTargetJobBlock(String jd, {int maxChars = 720}) {
    final jdClean = _sanitizeTextForPdf(jd);
    if (jdClean.trim().isEmpty) return <pw.Widget>[];
    return [
      pw.Text(
        'APPLYING TOWARD THIS ROLE',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.55,
          color: PdfColors.grey700,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        _jdSnippet(jdClean, maxChars),
        style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.15),
      ),
    ];
  }

  // ================= SAVE =================
  static Future<File> _savePdf(pw.Document pdf, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/$name.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Ephemeral path for share/export sheets (OS can reclaim; avoids cluttering documents).
  static Future<File> _savePdfToTemp(pw.Document pdf, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/$name.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ================= MAIN BUILD =================
  static Future<pw.Document> _buildResumePdf(
    ResumeData data,
  ) async {

    final pdf = pw.Document();

    // Avoid custom fonts here: on some devices/builds, parsing embedded TTFs can
    // fail during PDF generation with UTF-8/encoding errors. Falling back to the
    // built-in fonts keeps export reliable.
    final pw.ThemeData? theme = null;

    // 🔥 IMAGE
    pw.MemoryImage? image;
    if (data.profileImage != null &&
        await data.profileImage!.exists()) {
      image = pw.MemoryImage(
        await data.profileImage!.readAsBytes(),
      );
    }

    final languages = (data.categories["Languages"] ?? const <String>[])
        .map((s) => _sanitizeTextForPdf(
              CategoryEntryDisplay.formatLanguageEnglish(s),
            ))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: documentExportPageFormat,
        margin: const pw.EdgeInsets.all(20),
        maxPages: 100,
        build: (context) => [
          pw.Partitions(
            children: [
              pw.Partition(
                width: 140,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  color: PdfColors.grey900,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (image != null)
                        pw.Builder(
                          builder: (ctx) {
                            final mem = image!;
                            final firstPage = ctx.pageNumber == 1;
                            return pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                if (firstPage)
                                  pw.Container(
                                    width: 70,
                                    height: 70,
                                    decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle,
                                      image: pw.DecorationImage(image: mem),
                                    ),
                                  )
                                else
                                  pw.SizedBox(height: 12),
                                pw.SizedBox(height: firstPage ? 20 : 8),
                              ],
                            );
                          },
                        ),
                      _sideTitle("CONTACT"),
                      _contactLinePdf(
                        'Email',
                        data.email,
                        destination: _mailtoUrl(data.email),
                      ),
                      _contactLinePdf(
                        'Phone',
                        data.phone,
                        destination: _telUrl(data.phone),
                      ),
                      ..._buildContactLinks(data),
                      pw.SizedBox(height: 20),
                      _sideTitle("SKILLS"),
                      ...data.skills.map(
                        (s) => _skillBar(_sanitizeTextForPdf(s)),
                      ),
                      if (languages.isNotEmpty) ...[
                        pw.SizedBox(height: 20),
                        _sideTitle("LANGUAGES"),
                        ...languages.map(_sideText),
                      ],
                    ],
                  ),
                ),
              ),
              pw.Partition(
                flex: 1,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 16),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _sanitizeTextForPdf(data.name),
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 15),
                      if (data.summary.isNotEmpty ||
                          data.targetJobDescription.trim().isNotEmpty) ...[
                        _title("PROFILE"),
                        ..._pdfTargetJobBlock(
                          data.targetJobDescription,
                          maxChars: 900,
                        ),
                        if (data.targetJobDescription.trim().isNotEmpty)
                          pw.SizedBox(height: 10),
                        if (data.summary.isNotEmpty)
                          pw.Text(_sanitizeTextForPdf(data.summary)),
                        pw.SizedBox(height: 15),
                      ],
                      if (data.experiences.isNotEmpty) ...[
                        _title("EXPERIENCE"),
                        ..._pdfTargetJobBlock(
                          data.targetJobDescription,
                          maxChars: 640,
                        ),
                        if (data.targetJobDescription.trim().isNotEmpty)
                          pw.SizedBox(height: 8),
                        ...data.experiences.map(
                          (e) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 10),
                            child: pw.Column(
                              crossAxisAlignment:
                                  pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  _sanitizeTextForPdf(
                                    "${e.role} - ${e.company}",
                                  ),
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  _sanitizeTextForPdf(e.duration),
                                  style: const pw.TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 15),
                      ],
                      if (data.educationList.isNotEmpty) ...[
                        _title("EDUCATION"),
                        ...data.educationList.map(
                          (e) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 6),
                            child: pw.Text(
                              _sanitizeTextForPdf(
                                "${e.degree} - ${e.institution} (${e.year})",
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf;
  }

  /// Safe base name for a PDF on disk (no path separators / illegal chars).
  static String _safeResumePdfBaseName(ResumeData data) {
    var name = data.name.trim();
    if (name.isEmpty) name = 'Resume';
    name = name.replaceAll(RegExp(r'[/\\:*?"<>|\n\r\t]'), '_').trim();
    if (name.isEmpty) name = 'Resume';
    if (name.length > 44) name = name.substring(0, 44).trim();
    return '${name}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Builds the styled (preview) resume PDF to a temp file — does not open UI.
  static Future<ResumePdfExport> exportTemplatePreviewPdfToTemp({
    required List<Uint8List> pagePngBytes,
    required ResumeData data,
  }) async {
    if (pagePngBytes.isEmpty) {
      throw StateError('Nothing to export (no rendered pages).');
    }

    final base = _safeResumePdfBaseName(data);
    final displayName = '$base.pdf';

    final pdf = pw.Document();
    for (final png in pagePngBytes) {
      final normalized = await _normalizePreviewPngToA4(png);
      final img = pw.MemoryImage(normalized);
      pdf.addPage(
        pw.Page(
          pageFormat: styledTemplateExportPageFormat,
          margin: pw.EdgeInsets.zero,
          // Use [BoxFit.cover] so X/Y scale is identical (no anamorphic stretch).
          // With a true A4 MediaBox and normalized PNG aspect, this still fills the page.
          build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                pw.Container(color: PdfColors.white),
                pw.Positioned.fill(
                  child: pw.Image(img, fit: pw.BoxFit.cover),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final file = await _savePdfToTemp(pdf, base);
    final exists = await file.exists();
    final len = exists ? await file.length() : 0;
    if (!exists || len <= 0) {
      throw StateError('Export PDF was not created (exists=$exists, bytes=$len).');
    }

    return (file: file, displayName: displayName);
  }

  static Future<String> shareTemplatePreviewPdf({
    required List<Uint8List> pagePngBytes,
    required ResumeData data,
    Rect? sharePositionOrigin,
  }) async {
    final r = await exportTemplatePreviewPdfToTemp(
      pagePngBytes: pagePngBytes,
      data: data,
    );
    await Share.shareXFiles(
      [
        XFile(
          r.file.path,
          mimeType: 'application/pdf',
          name: r.displayName,
        ),
      ],
      subject: 'Resume',
      sharePositionOrigin: sharePositionOrigin,
    );
    return r.displayName;
  }

  /// Opens the OS **Print** / **Save as PDF** panel for an existing PDF file.
  ///
  /// Uses [styledTemplateExportPageFormat] so the dialog defaults to **ISO A4**
  /// instead of US Letter where the platform honors [Printing.layoutPdf].
  ///
  /// Returns `null` if printing is unavailable, `true` if the user printed or
  /// saved, `false` if they cancelled the dialog.
  static Future<bool?> presentSystemPrintForPdf(
    File file, {
    String name = 'Document',
    PdfPageFormat format = styledTemplateExportPageFormat,
  }) async {
    final info = await Printing.info();
    if (!info.canPrint) {
      return null;
    }
    final bytes = await file.readAsBytes();
    var docName = name.trim();
    if (docName.toLowerCase().endsWith('.pdf')) {
      docName = docName.substring(0, docName.length - 4);
    }
    if (docName.isEmpty) docName = 'Document';
    final printed = await Printing.layoutPdf(
      onLayout: (PdfPageFormat _) async => bytes,
      name: docName,
      format: format,
      dynamicLayout: false,
    );
    return printed;
  }

  /// Builds the resume PDF and opens the platform share sheet so the user can
  /// save to Files, Downloads, Drive, etc. Saving only under [getApplicationDocumentsDirectory]
  /// is not visible as a normal “download”, which is why this uses [Share.shareXFiles].
  ///
  /// Export resume PDF via the system share sheet (Save to Files / Downloads).
  /// Returns the filename suggested to the OS (includes `.pdf`).
  ///
  /// This intentionally does NOT fall back to app-private storage silently — if
  /// the share sheet fails, callers should show an error because the user asked
  /// to save the file to a visible location.
  /// Builds the ATS-style resume PDF to a temp file — does not open UI.
  static Future<ResumePdfExport> exportResumePdfToTemp({
    required ResumeData data,
  }) async {
    final pdf = await _buildResumePdf(data);
    final base = _safeResumePdfBaseName(data);
    final file = await _savePdfToTemp(pdf, base);
    final displayName = '$base.pdf';
    final exists = await file.exists();
    final len = exists ? await file.length() : 0;
    if (!exists || len <= 0) {
      throw StateError('Export PDF was not created (exists=$exists, bytes=$len).');
    }
    return (file: file, displayName: displayName);
  }

  static Future<String> downloadResume({
    required ResumeData data,
    Rect? sharePositionOrigin,
  }) async {
    final r = await exportResumePdfToTemp(data: data);
    await Share.shareXFiles(
      [
        XFile(
          r.file.path,
          mimeType: 'application/pdf',
          name: r.displayName,
        ),
      ],
      subject: 'Resume',
      sharePositionOrigin: sharePositionOrigin,
    );
    return r.displayName;
  }

  // ================= SHARE =================
  static Future<void> shareResume({
    required ResumeData data,
    Rect? sharePositionOrigin,
  }) async {
    final r = await exportResumePdfToTemp(data: data);
    await Share.shareXFiles(
      [
        XFile(
          r.file.path,
          mimeType: 'application/pdf',
          name: r.displayName,
        ),
      ],
      subject: 'Resume',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  // ================= UI HELPERS =================

  static pw.Widget _title(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _sideTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  static pw.Widget _sideText(String text) {
    final t = _sanitizeTextForPdf(text);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        t,
        style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
      ),
    );
  }

  /// Contact rows without a Material icon font (not bundled — loading it broke PDF export).
  static pw.Widget _contactLinePdf(
    String label,
    String value, {
    String? destination,
  }) {
    final v = _sanitizeTextForPdf(value).trim();
    if (v.isEmpty) return pw.SizedBox();
    final line = '$label: $v';
    final dest = destination?.trim();
    if (dest != null && dest.isNotEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.UrlLink(
          destination: dest,
          child: pw.Text(
            line,
            style: const pw.TextStyle(
              color: PdfColors.white,
              fontSize: 10,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        line,
        style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
      ),
    );
  }

  static List<pw.Widget> _buildContactLinks(ResumeData data) {
    final links = (data.categories["Links"] ?? const <String>[])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (links.isEmpty) return const <pw.Widget>[];

    String? linkedIn;
    for (final l in links) {
      if (l.toLowerCase().contains('linkedin')) {
        linkedIn = l;
        break;
      }
    }

    final widgets = <pw.Widget>[];
    if (linkedIn != null) {
      final url = _extractFirstWebUrl(linkedIn);
      widgets.add(
        _contactLinePdf(
          'LinkedIn',
          linkedIn,
          destination: url,
        ),
      );
    }

    // Add up to one more non-LinkedIn link (portfolio / website) for convenience.
    for (final l in links) {
      if (linkedIn != null && l == linkedIn) continue;
      final url = _extractFirstWebUrl(l);
      if (url == null) continue;
      widgets.add(
        _contactLinePdf(
          'Link',
          l,
          destination: url,
        ),
      );
      break;
    }

    return widgets;
  }

  // 🔥 SKILL BAR
  static pw.Widget _skillBar(String skill) {
    final s = _sanitizeTextForPdf(skill);
    final level = (s.hashCode % 70 + 30).toDouble();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(s,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
        pw.SizedBox(height: 3),
        pw.Stack(
          children: [
            pw.Container(
              height: 4,
              width: 100,
              color: PdfColors.grey700,
            ),
            pw.Container(
              height: 4,
              width: level,
              color: PdfColors.blue,
            ),
          ],
        ),
        pw.SizedBox(height: 6),
      ],
    );
  }

  // ================= COVER LETTER =================

  static Future<void> downloadCoverLetter({
    required String text,
    required String fileName,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        theme: await _tryLoadRobotoTheme(),
        pageFormat: documentExportPageFormat,
        margin: const pw.EdgeInsets.fromLTRB(56, 64, 56, 64),
        maxPages: 4,
        build: (context) {
          final safe = _sanitizeTextForPdf(text).trim();
          final blocks = safe
              .split(RegExp(r'\n\\s*\n+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

          return [
            pw.DefaultTextStyle(
              style: const pw.TextStyle(fontSize: 11.5, height: 1.55),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    pw.Paragraph(text: blocks[i]),
                    if (i != blocks.length - 1) pw.SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ];
        },
      ),
    );

    await _savePdf(pdf, fileName);
  }

  static Future<void> shareCoverLetter(String text) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        theme: await _tryLoadRobotoTheme(),
        pageFormat: documentExportPageFormat,
        margin: const pw.EdgeInsets.fromLTRB(56, 64, 56, 64),
        maxPages: 4,
        build: (context) {
          final safe = _sanitizeTextForPdf(text).trim();
          final blocks = safe
              .split(RegExp(r'\n\\s*\n+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

          return [
            pw.DefaultTextStyle(
              style: const pw.TextStyle(fontSize: 11.5, height: 1.55),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    pw.Paragraph(text: blocks[i]),
                    if (i != blocks.length - 1) pw.SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ];
        },
      ),
    );

    final file = await _savePdf(pdf, "cover_letter");

    await Share.shareXFiles([XFile(file.path)]);
  }

  static Future<void> downloadResumeFromText({
    required String text,
    String fileName = "enhanced_resume",
  }) async {
    await buildResumePdfFromTextFile(
      text: text,
      fileName: fileName,
    );
  }

  static Future<File> buildResumePdfFromTextFile({
    required String text,
    String fileName = "enhanced_resume",
  }) async {
    final pdf = pw.Document();

    final safeText = _sanitizeTextForPdf(text);

    pdf.addPage(
      pw.MultiPage(
        // Intentionally avoid custom fonts here: some devices/builds can fail
        // while parsing embedded TTFs, which breaks Preview/Download.
        theme: null,
        pageFormat: documentExportPageFormat,
        margin: const pw.EdgeInsets.all(24),
        maxPages: 100,
        build: (context) => [
          // Use a SpanningWidget so long resumes flow across pages.
          pw.Paragraph(
            text: safeText,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );

    return _savePdf(pdf, fileName);
  }

  static Future<pw.ThemeData?> _tryLoadRobotoTheme() async {
    try {
      final robotoRegular = pw.Font.ttf(
        await rootBundle.load("assets/fonts/Roboto-Regular.ttf"),
      );
      final robotoBold = pw.Font.ttf(
        await rootBundle.load("assets/fonts/Roboto-Bold.ttf"),
      );
      return pw.ThemeData.withFont(base: robotoRegular, bold: robotoBold);
    } catch (_) {
      // If fonts fail to load/parse on a device, fall back to default fonts
      // so PDF preview/download still works.
      return null;
    }
  }

  /// Strips UTF-16 surrogates, BOM, NUL, and C0 controls (except tab/LF/CR) so
  /// [utf8.encode] / the PDF writer never hit [FormatException] on resume text
  /// (e.g. U+001E from structured category fields, bad PDF extraction bytes).
  static String _sanitizeTextForPdf(String input) {
    final out = StringBuffer();
    for (final r in input.runes) {
      if (r >= 0xD800 && r <= 0xDFFF) continue;
      if (r == 0xFEFF || r == 0) continue;
      if (r < 32 && r != 9 && r != 10 && r != 13) continue;
      out.writeCharCode(r);
    }
    final s = out.toString();
    try {
      utf8.encode(s);
      return s;
    } catch (_) {
      return String.fromCharCodes(
        s.codeUnits.where((u) => u < 0xD800 || u > 0xDFFF),
      );
    }
  }
}