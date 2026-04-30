import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/resume_model.dart';
import '../utils/category_entry_display.dart';
import '../utils/pdf_export_ats_markers.dart';

class PdfService {
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
        pageFormat: PdfPageFormat.a4,
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

  static Future<String> shareTemplatePreviewPdf({
    required List<Uint8List> pagePngBytes,
    required ResumeData data,
    Rect? sharePositionOrigin,
  }) async {
    if (pagePngBytes.isEmpty) {
      throw StateError('Nothing to export (no rendered pages).');
    }

    final base = _safeResumePdfBaseName(data);
    final displayName = '$base.pdf';

    // Embed an (almost invisible) selectable text layer so ATS extractors can
    // read the exported PDF even though the visuals come from screenshots.
    final atsText = _resumePlainTextForAts(data);

    final pdf = pw.Document();
    for (final png in pagePngBytes) {
      final img = pw.MemoryImage(png);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Stack(
            children: [
              // Fill the full A4 page. `contain` letterboxes when the rasterized
              // preview aspect ratio differs slightly from A4, leaving empty bands
              // (often mistaken for “wrong margins” in Save / Share PDF).
              pw.Positioned.fill(
                child: pw.Image(img, fit: pw.BoxFit.fill),
              ),
              if (atsText.isNotEmpty)
                pw.Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: pw.Opacity(
                    // Not fully 0.0 so extractors don't drop it as "invisible".
                    opacity: 0.01,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        atsText,
                        style: const pw.TextStyle(
                          fontSize: 1.2,
                          color: PdfColors.black,
                          lineSpacing: 1.1,
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

    final file = await _savePdfToTemp(pdf, base);
    final exists = await file.exists();
    final len = exists ? await file.length() : 0;
    if (!exists || len <= 0) {
      throw StateError('Export PDF was not created (exists=$exists, bytes=$len).');
    }

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: displayName,
        ),
      ],
      subject: 'Resume',
      sharePositionOrigin: sharePositionOrigin,
    );
    return displayName;
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
  static Future<String> downloadResume({
    required ResumeData data,
    Rect? sharePositionOrigin,
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

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: displayName,
        ),
      ],
      subject: 'Resume',
      sharePositionOrigin: sharePositionOrigin,
    );
    return displayName;
  }

  // ================= SHARE =================
  static Future<void> shareResume({
    required ResumeData data,
    Rect? sharePositionOrigin,
  }) async {
    final pdf = await _buildResumePdf(data);
    final base = _safeResumePdfBaseName(data);
    final file = await _savePdfToTemp(pdf, base);
    final displayName = '$base.pdf';
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: displayName,
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
        pageFormat: PdfPageFormat.a4,
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
        pageFormat: PdfPageFormat.a4,
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
        pageFormat: PdfPageFormat.a4,
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