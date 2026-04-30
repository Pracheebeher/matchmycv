/// Markers used to embed a machine-readable text layer into styled template PDFs.
/// This text is for ATS extractors; it must be stripped on re-import so it does
/// not pollute structured resume sections (e.g. Hobbies).
class PdfExportAtsMarkers {
  static const String begin = '<<<MATCHMYCV_ATS_TEXT_BEGIN>>>';
  static const String end = '<<<MATCHMYCV_ATS_TEXT_END>>>';

  /// Returns the embedded machine-readable ATS layer if present; otherwise `""`.
  static String extractEmbeddedMachineText(String raw) {
    final re = RegExp(
      '${RegExp.escape(begin)}([\\s\\S]*?)${RegExp.escape(end)}',
      multiLine: true,
    );
    final m = re.firstMatch(raw);
    if (m == null) return '';
    final t = (m.group(1) ?? '').trim();
    return t;
  }

  static String stripEmbeddedMachineText(String raw) {
    var t = raw;
    final re = RegExp(
      '${RegExp.escape(begin)}[\\s\\S]*?${RegExp.escape(end)}',
      multiLine: true,
    );
    t = t.replaceAll(re, '');
    t = t.replaceAll(begin, '').replaceAll(end, '');
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
