import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'pdf_text_extractor.dart';
import '../utils/pdf_export_ats_markers.dart';

class AIATSService {
  /// Set when running or building, e.g.
  /// `flutter run --dart-define=OPENAI_API_KEY=sk-...`
  static const String _apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const Duration _requestTimeout = Duration(seconds: 120);

  static Future<String> extractResumeText(File file) async {
    final pathLower = file.path.toLowerCase();
    if (pathLower.endsWith('.pdf')) {
      return PdfTextExtractorService.extractText(file);
    }
    try {
      return await file.readAsString();
    } catch (_) {
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static Future<Map<String, dynamic>> checkATS(File file) async {
    try {
      if (_apiKey.isEmpty) {
        return {
          "score": 0,
          "feedback":
              "OpenAI API key is not set. Run or build with --dart-define=OPENAI_API_KEY=your_key"
        };
      }

      String rawText;
      try {
        rawText = await extractResumeText(file);
      } catch (e) {
        return {"score": 0, "feedback": "Could not read resume text: $e"};
      }

      if (rawText.trim().isEmpty) {
        return {
          "score": 0,
          "feedback":
              "No readable text found in this file. Try a PDF with selectable text."
        };
      }

      // Styled template PDFs are mostly PNG pages; readable content lives in the
      // embedded ATS layer between [PdfExportAtsMarkers] (see [PdfService] export).
      var text = PdfExportAtsMarkers.stripEmbeddedMachineText(rawText);
      if (text.trim().isEmpty) {
        final embedded =
            PdfExportAtsMarkers.extractEmbeddedMachineText(rawText).trim();
        text = embedded.isNotEmpty ? embedded : rawText;
      }

      const maxChars = 48000;
      if (text.length > maxChars) {
        text = text.substring(0, maxChars);
      }

      int retry = 0;
      http.Response? response;

      while (retry < 3) {
        response = await http
            .post(
              Uri.parse("https://api.openai.com/v1/chat/completions"),
              headers: {
                "Authorization": "Bearer $_apiKey",
                "Content-Type": "application/json",
              },
              body: jsonEncode({
                "model": "gpt-4o-mini",
                "response_format": {"type": "json_object"},
                "messages": [
                  {
                    "role": "system",
                    "content":
                        "You are an ATS resume checker. Return ONLY a JSON object with keys score (number 0-100) and feedback (string)."
                  },
                  {
                    "role": "user",
                    "content":
                        "Analyze this resume:\n$text\n\nReturn JSON: {\"score\": <0-100>, \"feedback\": \"...\"}"
                  }
                ]
              }),
            )
            .timeout(_requestTimeout);

        if (response.statusCode == 200) break;

        if (response.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 3));
          retry++;
        } else {
          break;
        }
      }

      if (response == null || response.statusCode != 200) {
        String apiMessage = "";
        if (response != null && response.body.isNotEmpty) {
          try {
            final err = jsonDecode(response.body) as Map<String, dynamic>?;
            final error = err?["error"];
            if (error is Map && error["message"] != null) {
              apiMessage = error["message"].toString();
            }
          } catch (_) {}
        }
        final code = response?.statusCode ?? "—";
        return {
          "score": 0,
          "feedback": apiMessage.isNotEmpty
              ? "API error (HTTP $code): $apiMessage"
              : "API request failed (HTTP $code). Check your key, quota, and network."
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final content =
          (data["choices"] as List<dynamic>)[0]["message"]["content"];

      Map<String, dynamic> parsed;

      try {
        parsed = jsonDecode(content as String) as Map<String, dynamic>;
      } catch (_) {
        parsed = {
          "score": 70,
          "feedback": content.toString(),
        };
      }

      return {
        "score": parsed["score"] ?? 0,
        "feedback": parsed["feedback"] ?? "No feedback available"
      };
    } on TimeoutException {
      return {
        "score": 0,
        "feedback":
            "Request timed out. Check your connection and try again with a smaller PDF."
      };
    } catch (e) {
      return {
        "score": 0,
        "feedback": "Error: $e"
      };
    }
  }

  static Future<String> enhanceResume({
    required String resumeText,
    required String atsFeedback,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        "OpenAI API key is not set. Run or build with --dart-define=OPENAI_API_KEY=your_key",
      );
    }

    final trimmedResume = resumeText.trim();
    if (trimmedResume.isEmpty) {
      throw StateError("Resume text is empty.");
    }

    final truncatedResume =
        trimmedResume.length > 48000 ? trimmedResume.substring(0, 48000) : trimmedResume;
    final truncatedFeedback =
        atsFeedback.length > 8000 ? atsFeedback.substring(0, 8000) : atsFeedback;

    final response = await http
        .post(
          Uri.parse("https://api.openai.com/v1/chat/completions"),
          headers: {
            "Authorization": "Bearer $_apiKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "model": "gpt-4o-mini",
            "messages": [
              {
                "role": "system",
                "content":
                    "You are an expert resume writer and ATS optimizer. Rewrite resumes to be ATS-friendly and impact-focused. Output ONLY the improved resume text (no JSON, no markdown fences). Keep it truthful and do not invent employers, degrees, dates, or skills."
              },
              {
                "role": "user",
                "content":
                    "Improve this resume using the ATS feedback.\n\nATS feedback:\n$truncatedFeedback\n\nResume:\n$truncatedResume\n\nReturn the improved resume as clean text with clear sections (SUMMARY, EXPERIENCE, EDUCATION, SKILLS)."
              }
            ]
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      String apiMessage = "";
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>?;
        final error = err?["error"];
        if (error is Map && error["message"] != null) {
          apiMessage = error["message"].toString();
        }
      } catch (_) {}
      final code = response.statusCode;
      throw StateError(
        apiMessage.isNotEmpty
            ? "API error (HTTP $code): $apiMessage"
            : "API request failed (HTTP $code). Check your key, quota, and network.",
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (data["choices"] as List<dynamic>)[0]["message"]["content"]?.toString();
    return (content ?? "").trim();
  }
}
