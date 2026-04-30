import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists ATS checker upload path + scan results so returning from other
/// routes still shows the last resume and score.
class AtsCheckerSessionData {
  final String resumePath;
  final String? originalFileName;
  final String extractedText;
  final Map<String, dynamic> result;

  const AtsCheckerSessionData({
    required this.resumePath,
    this.originalFileName,
    required this.extractedText,
    required this.result,
  });
}

class AtsCheckerSession {
  AtsCheckerSession._();
  static final AtsCheckerSession instance = AtsCheckerSession._();

  static const _kPath = 'ats_checker_resume_path';
  static const _kOriginalName = 'ats_checker_original_file_name';
  static const _kText = 'ats_checker_extracted_text';
  static const _kResult = 'ats_checker_result_json';

  Future<void> save({
    required String resumePath,
    String? originalFileName,
    required String extractedText,
    required Map<String, dynamic> result,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPath, resumePath);
    if (originalFileName != null && originalFileName.trim().isNotEmpty) {
      await p.setString(_kOriginalName, originalFileName.trim());
    } else {
      await p.remove(_kOriginalName);
    }
    await p.setString(_kText, extractedText);
    await p.setString(_kResult, jsonEncode(result));
  }

  Future<AtsCheckerSessionData?> load() async {
    final p = await SharedPreferences.getInstance();
    final path = p.getString(_kPath);
    final originalName = p.getString(_kOriginalName);
    final text = p.getString(_kText);
    final resultRaw = p.getString(_kResult);
    if (path == null || text == null || resultRaw == null) return null;
    try {
      final decoded = jsonDecode(resultRaw);
      if (decoded is! Map<String, dynamic>) return null;
      return AtsCheckerSessionData(
        resumePath: path,
        originalFileName: originalName,
        extractedText: text,
        result: decoded,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPath);
    await p.remove(_kOriginalName);
    await p.remove(_kText);
    await p.remove(_kResult);
  }
}
