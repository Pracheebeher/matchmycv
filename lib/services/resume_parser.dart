import 'dart:io';
import '../models/resume_model.dart';

class ResumeParser {

  static Future<void> parseResume(File file, ResumeData data) async {
    try {
      final text = await file.readAsString();

      final lines = text.split('\n');

      // ===== BASIC EXTRACTION =====

      for (var line in lines) {
        line = line.trim();

        // Name (first non-empty line)
        if (data.name.isEmpty && line.isNotEmpty) {
          data.name = line;
        }

        // Email
        if (data.email.isEmpty && line.contains("@")) {
          data.email = line;
        }

        // Phone
        if (data.phone.isEmpty && RegExp(r'\d{10,}').hasMatch(line)) {
          data.phone = line;
        }

        // Skills (basic detection)
        if (line.toLowerCase().contains("skills")) {
          final index = lines.indexOf(line);
          if (index + 1 < lines.length) {
            data.skills.addAll(
              lines[index + 1].split(",").map((e) => e.trim()),
            );
          }
        }

        // Education (basic fallback)
        if (line.toLowerCase().contains("education")) {
          final index = lines.indexOf(line);
          if (index + 1 < lines.length) {
            data.educationList.add(
              Education(
                degree: lines[index + 1],
                institution: "",
                year: "",
              ),
            );
          }
        }
      }

    } catch (e) {
      print("❌ Resume Parse Error: $e");
    }
  }
}