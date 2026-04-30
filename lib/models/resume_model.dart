import 'dart:io';
class ResumeData {
  String name;
  String email;
  String phone;
  String summary;

  List<String> skills;
  List<Experience> experiences;
  List<Education> educationList;

  Map<String, List<String>> categories;

  File? profileImage;

  /// Optional full job posting text used for AI tailoring (resume + cover letter flows).
  String targetJobDescription;

  ResumeData({
    this.name = "",
    this.email = "",
    this.phone = "",
    this.summary = "",
    this.targetJobDescription = "",
    List<String>? skills,
    List<Experience>? experiences,
    List<Education>? educationList,
    Map<String, List<String>>? categories,
    this.profileImage,
  })  : skills = skills ?? [],
        experiences = experiences ?? [],
        educationList = educationList ?? [],
        categories = categories ?? {
          "Languages": [],
          "Courses": [],
          "Certifications": [],
          "Links": [],
          "Hobbies": [],
          "Volunteering": [],
          "References": [],
          "City": [],
          "Country": [],
          "Projects": [],
          "Achievements": [],
          "Frameworks": [],
          "Cloud/Databases/Tech-Stack": [],
        };

  /// Clears all structured category buckets before importing a new resume/PDF so
  /// values from a previous upload are not left behind when the next file omits a section.
  void resetCategoryBucketsForImport() {
    categories = {
      "Languages": [],
      "Courses": [],
      "Certifications": [],
      "Links": [],
      "Hobbies": [],
      "Volunteering": [],
      "References": [],
      "City": [],
      "Country": [],
      "Projects": [],
      "Achievements": [],
      "Frameworks": [],
      "Cloud/Databases/Tech-Stack": [],
    };
  }

  static bool _nonEmptyStr(String s) => s.trim().isNotEmpty;

  /// True if there is anything meaningful to render in a template preview
  /// (contact, summary, skills, experience, education, categories, or photo).
  bool hasAnyResumeContentForPreview() {
    if (_nonEmptyStr(name)) return true;
    if (_nonEmptyStr(email)) return true;
    if (_nonEmptyStr(phone)) return true;
    if (_nonEmptyStr(summary)) return true;
    if (skills.any(_nonEmptyStr)) return true;
    if (experiences.isNotEmpty) return true;
    if (educationList.any(
          (e) =>
              _nonEmptyStr(e.degree) ||
              _nonEmptyStr(e.institution) ||
              _nonEmptyStr(e.year),
        )) {
      return true;
    }
    if (profileImage != null) return true;
    for (final list in categories.values) {
      if (list.any(_nonEmptyStr)) return true;
    }
    return false;
  }
}

class Education {
  String degree;
  String institution;
  String year;

  Education({
    required this.degree,
    required this.institution,
    required this.year,
  });
}

class Experience {
  String role;
  String company;
  String duration;
  List<String> description;

  Experience({
    required this.role,
    required this.company,
    required this.duration,
    List<String>? description,
  }) : description = description ?? [];
}