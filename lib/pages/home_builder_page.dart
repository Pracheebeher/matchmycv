import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';

import '../models/resume_model.dart';
import '../services/ai_resume_parser.dart';
import '../services/ai_summary_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/paste_input_extras.dart';
import '../utils/category_entry_display.dart';
import '../widgets/uniform_app_bar.dart';
import 'template_selection_page.dart';

class HomeBuilderPage extends StatefulWidget {
  final ResumeData data;

  /// When true (e.g. opened from preview "Edit resume"), all editor sections start expanded.
  final bool expandAllSectionsForEdit;

  const HomeBuilderPage({
    super.key,
    required this.data,
    this.expandAllSectionsForEdit = false,
  });

  @override
  State<HomeBuilderPage> createState() => _HomeBuilderPageState();
}

class _HomeBuilderPageState extends State<HomeBuilderPage> {
  /// Separates structured parts in stored category strings (name/phone, course/date).
  static final String _kCategoryFieldSep = String.fromCharCode(0x1e);

  /// City / Country are edited under Personal info, not the category grid.
  static const Set<String> _personalGeoCategoryKeys = {'City', 'Country'};

  final GlobalKey _guideKeyPersonal = GlobalKey();
  final GlobalKey _guideKeySummary = GlobalKey();
  final GlobalKey _guideKeySkills = GlobalKey();
  final GlobalKey _guideKeyExperience = GlobalKey();
  Set<String> _guidedSectionTags = {};
  bool _guideHighlightBottomBar = false;

  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final city = TextEditingController();
  final country = TextEditingController();
  final summary = TextEditingController();
  final _skillInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _parallaxPx = ValueNotifier(0.0);

  // ---- Premium Futuristic Visual System (UI-only) ----
  // (keep colors grouped; _bg removed because unused)
  static const Color _glassFill = Color(0x14FFFFFF);
  static const Color _glassStroke = Color(0x22FFFFFF);
  static const Color _neonCyan = Color(0xFF06B6D4);
  static const Color _neonViolet = Color(0xFF7C3AED);
  static const LinearGradient _primaryNeon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),
      Color(0xFF06B6D4),
    ],
  );

  List<String> skills = [];
  List<Experience> experiences = [];
  List<Education> educationList = [];

  Map<String, List<String>> categories = {
    "Languages": [],
    "Courses": [],
    "Certifications": [],
    "City": [],
    "Country": [],
    "Links": [],
    "Hobbies": [],
    "Volunteering": [],
    "References": [],
    "Projects": [],
    "Achievements": [],
  };

  bool showPersonal = false;
  bool showSummary = false;
  bool showExperience = false;
  bool showEducation = false;
  bool showSkills = false;
  bool showCategory = false;

  OverlayEntry? _saveToastEntry;

  String _categoryDisplayTitle(String key, AppLocalizations t) {
    switch (key) {
      case 'Languages':
        return t.categoryLanguages;
      case 'Courses':
        return t.categoryCourses;
      case 'Links':
        return t.categoryLinks;
      case 'Hobbies':
        return t.categoryHobbies;
      case 'Volunteering':
        return t.categoryVolunteering;
      case 'References':
        return t.categoryReferences;
      case 'Certifications':
        return t.categoryCertifications;
      case 'City':
        return t.cityLabel;
      case 'Country':
        return t.countryLabel;
      case 'Achievements':
        return t.categoryAchievements;
      default:
        return key;
    }
  }

  String _firstCategoryValue(ResumeData data, String key) {
    for (final s in data.categories[key] ?? const <String>[]) {
      final t = s.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// Older resumes used a single [Location] bucket; split into City / Country when empty.
  void _migrateLegacyLocationToCityCountry() {
    final legacy = _firstCategoryValue(widget.data, 'Location');
    if (legacy.isEmpty) return;
    if (city.text.trim().isNotEmpty || country.text.trim().isNotEmpty) return;
    final parts = legacy
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      city.text = parts.first;
      country.text = parts.sublist(1).join(', ');
    } else {
      city.text = legacy;
    }
    categories['City'] =
        city.text.trim().isEmpty ? [] : <String>[city.text.trim()];
    categories['Country'] =
        country.text.trim().isEmpty ? [] : <String>[country.text.trim()];
  }

 @override
 void initState() {
   super.initState();

   name.text = widget.data.name;
   email.text = widget.data.email;
   phone.text = widget.data.phone;
   summary.text = widget.data.summary;

   skills = List.from(widget.data.skills);
   experiences = List.from(widget.data.experiences);
   educationList = List.from(widget.data.educationList);
   _normalizeEducationListInPlace();

   // ✅ SAFE INIT (NO overwrite issue)
   categories = {
     "Languages": (widget.data.categories["Languages"] ?? const <String>[])
         .map(CategoryEntryDisplay.normalizeLanguageStorage)
         .map((s) => s.trim())
         .where((s) => s.isNotEmpty)
         .toList(),
     "Courses": List<String>.from(widget.data.categories["Courses"] ?? []),
     "Certifications":
         List<String>.from(widget.data.categories["Certifications"] ?? []),
     "City": List<String>.from(widget.data.categories["City"] ?? []),
     "Country": List<String>.from(widget.data.categories["Country"] ?? []),
     "Links": List<String>.from(widget.data.categories["Links"] ?? []),
     "Hobbies": List<String>.from(widget.data.categories["Hobbies"] ?? []),
     "Volunteering": List<String>.from(widget.data.categories["Volunteering"] ?? []),
     "References": List<String>.from(widget.data.categories["References"] ?? []),
     "Projects": List<String>.from(widget.data.categories["Projects"] ?? []),
     "Achievements":
         List<String>.from(widget.data.categories["Achievements"] ?? []),
   };

   city.text = _firstCategoryValue(widget.data, 'City');
   country.text = _firstCategoryValue(widget.data, 'Country');
   if (city.text.trim().isEmpty && country.text.trim().isEmpty) {
     _migrateLegacyLocationToCityCountry();
   }

   if (widget.expandAllSectionsForEdit) {
     showPersonal = true;
     showSummary = true;
     showExperience = true;
     showEducation = true;
     showSkills = true;
     showCategory = true;
   }

   _scrollController.addListener(() {
     if (!_scrollController.hasClients) return;
     final px = _scrollController.position.pixels;
     if (_parallaxPx.value != px) _parallaxPx.value = px;
   });
 }

 @override
 void dispose() {
   save(showMessage: false);
   _saveToastEntry?.remove();
   _saveToastEntry = null;
   _scrollController.dispose();
   _parallaxPx.dispose();
   name.dispose();
   email.dispose();
   phone.dispose();
   city.dispose();
   country.dispose();
   summary.dispose();
   _skillInputController.dispose();
   super.dispose();
 }

  void _persistCategoriesToModel() {
    final next = Map<String, List<String>>.from(
      widget.data.categories.map(
        (k, v) => MapEntry(k, List<String>.from(v)),
      ),
    );
    for (final e in categories.entries) {
      next[e.key] = List<String>.from(e.value);
    }
    next.remove('Location');
    widget.data.categories = next;
  }

  Widget _categoryChipLabel(String item, String categoryKey) {
    const baseStyle = TextStyle(
      color: Color(0xFFF8FAFC),
      fontWeight: FontWeight.w800,
    );
    if (categoryKey == 'Projects') {
      final parts = item
          .split(_kCategoryFieldSep)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isEmpty) return const Text('', style: baseStyle);
      final title = parts.isNotEmpty ? parts[0] : '';
      final duration = parts.length >= 2 ? parts[1] : '';
      final details = parts.length >= 3 ? parts.sublist(2).join(' ') : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: baseStyle),
          if (duration.isNotEmpty)
            Text(
              duration,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                details,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      );
    }
    if (categoryKey == 'Achievements') {
      final parts = item.split(_kCategoryFieldSep);
      final title = parts.isNotEmpty ? parts[0].trim() : '';
      final where = parts.length >= 2 ? parts[1].trim() : '';
      final when = parts.length >= 3 ? parts[2].trim() : '';
      if (title.isEmpty) return const Text('', style: baseStyle);
      if (where.isEmpty && when.isEmpty) {
        return Text(title, style: baseStyle);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: baseStyle),
          if (where.isNotEmpty)
            Text(
              where,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          if (when.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: where.isEmpty ? 0 : 1),
              child: Text(
                when,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      );
    }
    if (categoryKey == 'References' ||
        categoryKey == 'Courses' ||
        categoryKey == 'Languages') {
      // Languages can come from PDF/AI with odd control chars; normalize first so
      // the separator never leaks into the UI as garbled symbols.
      final normalized = categoryKey == 'Languages'
          ? CategoryEntryDisplay.normalizeLanguageStorage(item)
          : item;
      final i = normalized.indexOf(_kCategoryFieldSep);
      if (i >= 0) {
        final a = normalized.substring(0, i).trim();
        final b = normalized.substring(i + 1).trim();
        final loc = AppLocalizations.of(context);
        final bDisplay = categoryKey == 'Languages' &&
                CategoryEntryDisplay.languageProficiencyCodes
                    .contains(b.toLowerCase())
            ? loc.languageProficiencyLabel(b)
            : b;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(a, style: baseStyle),
            if (b.isNotEmpty)
              Text(
                bDisplay,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
          ],
        );
      }
      if (categoryKey == 'Languages') {
        // Even if we can’t split, never show the raw separator tokens.
        return Text(normalized, style: baseStyle);
      }
    }
    return Text(item, style: baseStyle);
  }

  /// After template preview is blocked for empty resume: expand key sections,
  /// add a short glow on those cards (and the bottom bar when mostly empty),
  /// and scroll the first missing block into view.
  void _applyResumeEditorGuideFromTemplateGate() {
    final tags = <String>{};
    if (name.text.trim().isEmpty &&
        email.text.trim().isEmpty &&
        phone.text.trim().isEmpty) {
      tags.add('personal');
    }
    if (summary.text.trim().isEmpty) tags.add('summary');
    if (skills.isEmpty) tags.add('skills');
    if (experiences.isEmpty) tags.add('experience');

    final guideUpload = tags.length >= 3;

    setState(() {
      _guidedSectionTags = tags;
      _guideHighlightBottomBar = guideUpload;
      if (tags.contains('personal')) showPersonal = true;
      if (tags.contains('summary')) showSummary = true;
      if (tags.contains('skills')) showSkills = true;
      if (tags.contains('experience')) showExperience = true;
    });

    void scrollTo(GlobalKey key) {
      final c = key.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(
          c,
          alignment: 0.1,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GlobalKey? first;
      if (tags.contains('personal')) {
        first = _guideKeyPersonal;
      } else if (tags.contains('summary')) {
        first = _guideKeySummary;
      } else if (tags.contains('skills')) {
        first = _guideKeySkills;
      } else if (tags.contains('experience')) {
        first = _guideKeyExperience;
      }
      if (first != null) {
        scrollTo(first);
      } else {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      }
    });

    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      setState(() {
        _guidedSectionTags = {};
        _guideHighlightBottomBar = false;
      });
    });
  }

  // ================= SAVE =================
 void save({bool showMessage = true}) {
   widget.data.name = name.text;
   widget.data.email = email.text;
   widget.data.phone = phone.text;
   final c = city.text.trim();
   final co = country.text.trim();
   categories['City'] = c.isEmpty ? [] : <String>[c];
   categories['Country'] = co.isEmpty ? [] : <String>[co];
   widget.data.summary = summary.text;

   widget.data.skills = List.from(skills);
   widget.data.experiences = List.from(experiences);
   widget.data.educationList = List.from(educationList);

   _persistCategoriesToModel();
   if (showMessage) {
     _showPremiumSnack(AppLocalizations.of(context).saved);
   }
 }

  void _dismissSaveToast() {
    _saveToastEntry?.remove();
    _saveToastEntry = null;
  }

  /// Glass toast under the app bar. Uses [Overlay] so the body layout does not jump
  /// (unlike [MaterialBanner], which reserves space in the scaffold column).
  void _showPremiumSnack(String message) {
    _dismissSaveToast();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.paddingOf(ctx).top + kToolbarHeight + 6;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding:
                      const EdgeInsets.only(left: 14, top: 12, bottom: 12, right: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _primaryNeon,
                          border:
                              Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.75),
                          size: 22,
                        ),
                        onPressed: _dismissSaveToast,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _saveToastEntry = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (_saveToastEntry == entry) _dismissSaveToast();
    });
  }
  // ================= IMAGE =================
  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    );

    if (cropped != null) {
      setState(() {
        widget.data.profileImage = File(cropped.path);
      });
    }
  }

  // ================= ICON BUTTON =================
  Widget iconBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.92), size: 18),
          ),
        ),
      ),
    );
  }
Widget modernDialog({
  required String title,
  required List<Widget> fields,
  required VoidCallback onSave,
}) {
  final t = AppLocalizations.of(context);
  return Dialog(
    backgroundColor: Colors.transparent,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
              maxWidth: 420,
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🔥 TITLE
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 🔥 FIELDS
                  ...fields,

                  const SizedBox(height: 16),

                  // 🔥 BUTTONS
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.86),
                            backgroundColor: Colors.white.withOpacity(0.06),
                            side: BorderSide(color: Colors.white.withOpacity(0.16)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(t.cancel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: onSave,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00F5FF),
                                  Color(0xFF008CFF),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00F5FF).withOpacity(0.22),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                t.save,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final t = AppLocalizations.of(context);
    return Theme(
      data: base.copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: _neonCyan,
          selectionHandleColor: _neonCyan,
          selectionColor: _neonCyan.withOpacity(0.22),
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        // Keep the action dock truly fixed (no content behind it).
        extendBody: false,
        backgroundColor: const Color(0xFF070A12),

      appBar: UniformAppBar.material(t.buildResumeTitle),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF070A12).withOpacity(0.72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _guideHighlightBottomBar
                        ? const Color(0xFF22D3EE).withOpacity(0.92)
                        : Colors.white.withOpacity(0.10),
                    width: _guideHighlightBottomBar ? 2.2 : 1,
                  ),
                  boxShadow: [
                    if (_guideHighlightBottomBar)
                      BoxShadow(
                        color: const Color(0xFF22D3EE).withOpacity(0.38),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    neonButton(t.uploadResume, Icons.upload, uploadResume),
                    neonButton(t.templates, Icons.dashboard, () async {
                      save(showMessage: false);
                      final back = await Navigator.push<ResumeData?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TemplateSelectionPage(data: widget.data),
                        ),
                      );
                      if (!mounted) return;
                      if (back != null && identical(back, widget.data)) {
                        _applyResumeEditorGuideFromTemplateGate();
                      }
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
        body: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
            // 🔥 BACKGROUND — full viewport (extends under bottom bar)
            Positioned.fill(
              child: _FuturisticEditorBackdrop(scrollPixels: _parallaxPx),
            ),

            // 🔥  ORIGINAL UI
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                // Body already clears [bottomNavigationBar]; large bottom padding
                // here only created an empty scroll tail at the end of the page.
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  children: [

                  // ===== PROFILE IMAGE =====
                  Column(
                    children: [
                      Stack(
                        children: [
                          _ProfileAvatarRing(
                            radius: 55,
                            imageFile: widget.data.profileImage,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: _primaryNeon,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _neonCyan.withOpacity(0.22),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.uploadPhoto,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ===== PERSONAL =====
                  glassSection(
                    Icons.person,
                    t.personalInfoTitle,
                    showPersonal,
                    () => setState(() => showPersonal = !showPersonal),
                    Column(children: [
                      field(name, t.nameLabel),
                      field(email, t.emailLabel),
                      field(phone, t.phoneLabel),
                      field(city, t.cityLabel),
                      field(country, t.countryLabel),
                    ]),
                    sectionKey: _guideKeyPersonal,
                    guideHighlight: _guidedSectionTags.contains('personal'),
                  ),

                  // ===== SUMMARY (UPDATED AI UI) =====
                  glassSection(
                    Icons.description,
                    t.summaryTitle,
                    showSummary,
                    () => setState(() => showSummary = !showSummary),
                    Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final ai = AISummaryService.generateSummary(
                                name: name.text,
                                skills: skills,
                                experiences: experiences,
                                targetJobDescription:
                                    widget.data.targetJobDescription,
                              );
                              setState(() => summary.text = ai);
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withOpacity(0.06),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: Text(
                              t.generate,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            iconBtn(Icons.format_list_bulleted, () {
                              summary.text += "\n• ";
                              setState(() {});
                            }),
                            iconBtn(Icons.clear, () {
                              summary.clear();
                              setState(() {});
                            }),
                          ],
                        ),

                        const SizedBox(height: 10),

                        TextField(
                          controller: summary,
                          maxLines: 6,
                          minLines: 3,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: _neonCyan,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          contextMenuBuilder: (_, state) =>
                              buildPasteContextMenu(
                            editableTextState: state,
                            controller: summary,
                            pasteLabel: t.pasteFromClipboard,
                          ),
                          decoration: inputBox(t.writeSummaryHint),
                        )
                      ],
                    ),
                    sectionKey: _guideKeySummary,
                    guideHighlight: _guidedSectionTags.contains('summary'),
                  ),

                  // ===== EXPERIENCE =====
                  glassSection(Icons.work, t.experienceTitle, showExperience,
                      () => setState(() => showExperience = !showExperience),
                      Column(
                        children: [
                          ...experiences.asMap().entries.map(
                            (mapEntry) {
                              final i = mapEntry.key;
                              final e = mapEntry.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        76,
                                        10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(0.08),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withOpacity(0.12),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.work_rounded,
                                              size: 18,
                                              color: Colors.white
                                                  .withOpacity(0.92),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "${e.role} - ${e.company}",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  [
                                                    e.duration,
                                                    if (e.description.isNotEmpty)
                                                      e.description
                                                          .map((b) => b.trim())
                                                          .where(
                                                              (b) => b.isNotEmpty)
                                                          .map((b) => '• $b')
                                                          .join('\n'),
                                                  ]
                                                      .where((x) =>
                                                          x.trim().isNotEmpty)
                                                      .join('\n'),
                                                  maxLines: 16,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.72),
                                                    height: 1.25,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              tooltip: t.editExperienceTitle,
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                                color: Colors.white
                                                    .withOpacity(0.9),
                                              ),
                                              onPressed: () =>
                                                  _showExperienceDialog(
                                                      editIndex: i),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              tooltip: t.removeLabel,
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: Colors.white
                                                    .withOpacity(0.72),
                                              ),
                                              onPressed: () =>
                                                  _confirmRemoveExperience(i),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          uniformAddButton(t.addExperience, addExperience)
                        ],
                      ),
                      sectionKey: _guideKeyExperience,
                      guideHighlight:
                          _guidedSectionTags.contains('experience'),
                  ),

                  // ===== EDUCATION (FIXED MULTIPLE) =====
                  glassSection(Icons.school, t.educationTitle, showEducation,
                      () => setState(() => showEducation = !showEducation),
                      Column(
                        children: [
                          ...educationList.asMap().entries.map(
                            (mapEntry) {
                              final i = mapEntry.key;
                              final e = mapEntry.value;
                              final durLine =
                                  _educationYearLine(_educationDateRaw(e));
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        76,
                                        10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(0.08),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withOpacity(0.12),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.school_rounded,
                                              size: 18,
                                              color: Colors.white
                                                  .withOpacity(0.92),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "${e.degree} - ${e.institution}",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                if (durLine.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    durLine,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.72),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              tooltip: t.editEducationTitle,
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                                color: Colors.white
                                                    .withOpacity(0.9),
                                              ),
                                              onPressed: () =>
                                                  _showEducationDialog(
                                                      editIndex: i),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              tooltip: t.removeLabel,
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: Colors.white
                                                    .withOpacity(0.72),
                                              ),
                                              onPressed: () =>
                                                  _confirmRemoveEducation(i),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          uniformAddButton(t.addEducation, addEducation)
                        ],
                      )),

                  // ===== SKILLS =====
                  glassSection(Icons.star, t.skillsTitle, showSkills,
                      () => setState(() => showSkills = !showSkills),
                      Column(
                        children: [
                          Wrap(
                            spacing: 6,
                            children: skills
                                .map(
                                  (s) => Chip(
                                    label: Text(
                                      s,
                                      style: const TextStyle(
                                        color: Color(0xFFF8FAFC),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    deleteIcon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Colors.white.withOpacity(0.85),
                                    ),
                                    onDeleted: () {
                                      setState(() {
                                        skills.remove(s);
                                      });
                                    },
                                    backgroundColor: const Color(0xFF070A12),
                                    color: MaterialStatePropertyAll(
                                      Color(0xFF070A12),
                                    ),
                                    surfaceTintColor: Colors.transparent,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          TextField(
                            controller: _skillInputController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (v) {
                              final s = v.trim();
                              if (s.isEmpty) return;
                              setState(() {
                                skills.add(s);
                                _skillInputController.clear();
                              });
                              FocusManager.instance.primaryFocus?.unfocus();
                            },
                            onEditingComplete: () {
                              final s = _skillInputController.text.trim();
                              if (s.isNotEmpty) {
                                setState(() {
                                  skills.add(s);
                                  _skillInputController.clear();
                                });
                              }
                              FocusManager.instance.primaryFocus?.unfocus();
                            },
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            cursorColor: _neonCyan,
                            contextMenuBuilder: (_, state) =>
                                buildPasteContextMenu(
                              editableTextState: state,
                              controller: _skillInputController,
                              pasteLabel: t.pasteFromClipboard,
                            ),
                            decoration: inputBox(t.addSkillHint),
                          )
                        ],
                      ),
                      sectionKey: _guideKeySkills,
                      guideHighlight: _guidedSectionTags.contains('skills'),
                  ),
                // ✅ THIS WAS MISSING
                dynamicCategorySections(),
                // Categories
                    glassSection(
                      Icons.category,
                      t.categoriesTitle,
                      showCategory,
                      () => setState(() => showCategory = !showCategory),
                      Column(
                        children: [
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            childAspectRatio: 3,
                            children: categories.keys
                                .where(
                                  (k) =>
                                      !_personalGeoCategoryKeys.contains(k),
                                )
                                .map((k) => categoryCard(k, t))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

Widget dynamicCategorySections() {
  final t = AppLocalizations.of(context);
  final sections = categories.entries
      .where(
        (e) =>
            e.value.isNotEmpty &&
            !_personalGeoCategoryKeys.contains(e.key),
      )
      .toList();

  return Column(
    children: sections.map((entry) {
      return glassSection(
        getCategoryIcon(entry.key),
        _categoryDisplayTitle(entry.key, t),
        true,
        () {},
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: entry.value.map((item) {
                return Chip(
                  label: _categoryChipLabel(item, entry.key),
                  deleteIcon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.85)),
                  onDeleted: () {
                    setState(() {
                      entry.value.remove(item);
                    });
                  },
                  backgroundColor: const Color(0xFF070A12),
                  color: const MaterialStatePropertyAll(Color(0xFF070A12)),
                  surfaceTintColor: Colors.transparent,
                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        // Add items only from the main Categories section (grid cards).
        showTitleAddPlus: false,
      );
    }).toList(),
  );
}
  // ================= HELPERS =================
Widget uniformAddButton(String text, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          borderRadius: BorderRadius.circular(14),
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: _primaryNeon,
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: _neonViolet.withOpacity(0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 10,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
  Widget glassSection(
    IconData icon, // ✅ FIX: strongly typed
    String title,
    bool show,
    VoidCallback toggle,
    Widget child, {
    Key? sectionKey,
    bool guideHighlight = false,
    bool showTitleAddPlus = false,
  }) {
    return AnimatedContainer(
      key: sectionKey,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 12),
      padding: guideHighlight ? const EdgeInsets.all(2.6) : EdgeInsets.zero,
      decoration: guideHighlight
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: _primaryNeon,
              boxShadow: [
                BoxShadow(
                  color: _neonCyan.withOpacity(0.42),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: _glassFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _glassStroke),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _primaryNeon,
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: _neonCyan.withOpacity(0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ), // ✅ force render
                  title: showTitleAddPlus
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.add_rounded,
                              size: 17,
                              color: Colors.white.withOpacity(0.72),
                            ),
                          ],
                        )
                      : Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                  trailing: Icon(
                    show ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white.withOpacity(0.92),
                  ),
                  onTap: toggle,
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: show
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.all(12),
                    child: child,
                  ),
                  secondChild: const SizedBox(),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
Widget categoryCard(String key, AppLocalizations t) {
  final icons = {
    "Languages": Icons.language,
    "Courses": Icons.menu_book,
    "Certifications": Icons.workspace_premium,
    "Achievements": Icons.emoji_events_outlined,
    "Links": Icons.link,
    "Hobbies": Icons.sports_esports,
    "Volunteering": Icons.volunteer_activism,
    "References": Icons.people,
    "Projects": Icons.folder_special_rounded,
  };

  return GestureDetector(
    onTap: () => addCategoryItem(key),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icons[key] ?? Icons.category,
                  color: Colors.white.withOpacity(0.92),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _categoryDisplayTitle(key, t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: Colors.white.withOpacity(0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
IconData getCategoryIcon(String key) {
  switch (key) {
    case "Languages":
      return Icons.language;
    case "Courses":
      return Icons.menu_book;
    case "Certifications":
      return Icons.workspace_premium;
    case "Achievements":
      return Icons.emoji_events_outlined;
    case "Links":
      return Icons.link;
    case "Hobbies":
      return Icons.sports_esports;
    case "Volunteering":
      return Icons.volunteer_activism;
    case "References":
      return Icons.people;
    case "Projects":
      return Icons.folder_special_rounded;
    default:
      return Icons.category;
  }
}

  Widget neonButton(String text, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _primaryNeon,
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: _neonCyan.withOpacity(0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.18),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Icon(
                      icon,
                      color: const Color(0xFFF8FAFC),
                      size: 18,
                      shadows: const [
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        height: 1.05,
                        shadows: [
                          Shadow(
                            color: Color(0xAA000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget field(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final loc = AppLocalizations.of(context);
    final multiline = maxLines > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: multiline ? maxLines : 1,
        minLines: multiline ? math.min(maxLines, 3) : null,
        keyboardType:
            keyboardType ?? (multiline ? TextInputType.multiline : TextInputType.text),
        textInputAction:
            multiline ? TextInputAction.newline : TextInputAction.done,
        style: const TextStyle(color: Colors.white),
        cursorColor: _neonCyan,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onEditingComplete: multiline
            ? null
            : () => FocusManager.instance.primaryFocus?.unfocus(),
        contextMenuBuilder: (_, state) => buildPasteContextMenu(
          editableTextState: state,
          controller: controller,
          pasteLabel: loc.pasteFromClipboard,
        ),
        decoration: inputBox(hint),
      ),
    );
  }

  InputDecoration inputBox(hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.50),
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _neonCyan.withOpacity(0.55), width: 1.2),
      ),
    );
  }

  Future<DateTime?> _pickMonthYear(
    BuildContext context, {
    DateTime? initial,
    int startYear = 1980,
    int endYear = 2035,
  }) async {
    final now = DateTime.now();
    final init = initial ?? DateTime(now.year, now.month, 1);

    final months = const <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    int selMonth = init.month;
    int selYear = init.year.clamp(startYear, endYear);

    return showModalBottomSheet<DateTime?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF070A12).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select month & year',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selMonth,
                            dropdownColor: const Color(0xFF0B1222),
                            decoration: inputBox('Month'),
                            items: List.generate(
                              12,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(
                                  months[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            onChanged: (v) =>
                                setModal(() => selMonth = v ?? selMonth),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selYear,
                            dropdownColor: const Color(0xFF0B1222),
                            decoration: inputBox('Year'),
                            items: [
                              for (int y = endYear; y >= startYear; y--)
                                DropdownMenuItem(
                                  value: y,
                                  child: Text(
                                    '$y',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setModal(() => selYear = v ?? selYear),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white.withOpacity(0.86),
                              backgroundColor: Colors.white.withOpacity(0.06),
                              side:
                                  BorderSide(color: Colors.white.withOpacity(0.16)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx, DateTime(selYear, selMonth, 1));
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _neonCyan.withOpacity(0.20),
                              foregroundColor: const Color(0xFFF8FAFC),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side:
                                    BorderSide(color: _neonCyan.withOpacity(0.40)),
                              ),
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatMonthYear(DateTime d) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _educationYearLine(String raw) {
    final t = _sanitizeEducationYearRaw(raw);
    if (t.isEmpty) return '';
    final p = _parseEducationPeriodFields(t);
    final a = p.start.trim();
    final b = p.end.trim();
    if (a.isNotEmpty && b.isNotEmpty) return '$a - $b';
    if (a.isNotEmpty) return a;
    if (b.isNotEmpty) return b;
    // Do not echo arbitrary text (e.g. a whole degree line mistaken for a year).
    if (_looksLikeEducationPeriod(t)) return t;
    return '';
  }

  /// True when [s] looks like a graduation / attendance span, not degree prose.
  bool _looksLikeEducationPeriod(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 56) return false;
    final low = t.toLowerCase();
    if (RegExp(
      r'\b(university|college|school|academy|institute|bachelor|bachelors|masters?|master|mba|phd|doctor|associate|diploma|science|engineering|technology|business|studies|program)\b',
      caseSensitive: false,
    ).hasMatch(low)) {
      return false;
    }
    if (!RegExp(r'(19|20)\d{2}', caseSensitive: false).hasMatch(t)) {
      return false;
    }
    if (RegExp(
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\s+(19|20)\d{2}\b',
      caseSensitive: false,
    ).hasMatch(low)) {
      return true;
    }
    if (RegExp(r'\d{1,2}/(19|20)\d{2}', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^(19|20)\d{2}(\s*-\s*(19|20)\d{2})?$', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (RegExp(r'\d{4}-\d{2}(?:-\d{2})?', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    return false;
  }

  String _sanitizeEducationYearRaw(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll('\u001e', ' ');
    s = s.replaceAll(RegExp(r'[–—]'), '-');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Prefer the first window if older import paths joined duplicates with ';'.
    final semi = s.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (semi.length >= 2) {
      final a = semi.first;
      final b = semi.last;
      if (a == b) return a;
      return a;
    }

    return s;
  }

  /// Resume import often leaves [Education.year] empty while dates live in [Education.degree]
  /// / [Education.institution]. This mirrors the experience row: resolve a timeline string
  /// from whatever fields actually contain it.
  String _educationDateRaw(Education e) {
    final y = _sanitizeEducationYearRaw(e.year);
    if (y.isNotEmpty && _looksLikeEducationPeriod(y)) return y;
    return _educationTimelineFromBlob('${e.degree} ${e.institution}');
  }

  String _educationTimelineFromBlob(String combined) {
    final blob = combined.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (blob.isEmpty) return '';
    final fromParser = AIResumeParser.educationPeriodFromFreeText(blob);
    if (fromParser != null &&
        fromParser.isNotEmpty &&
        _looksLikeEducationPeriod(fromParser)) {
      return fromParser;
    }
    // Do NOT use [_parseExperienceDurationFields] here: education lines often
    // contain `Degree - School`, which splits like a date range and duplicates
    // the headline into the duration row.
    return '';
  }

  String _stripInsensitiveSubstringOnce(String haystack, String needle) {
    if (haystack.isEmpty || needle.isEmpty) return haystack.trim();
    final idx = haystack.toLowerCase().indexOf(needle.toLowerCase());
    if (idx < 0) return haystack.trim();
    final out = (haystack.substring(0, idx) + haystack.substring(idx + needle.length))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return out
        .replaceAll(RegExp(r'^[,|;\-\s]+'), '')
        .replaceAll(RegExp(r'[,|;\-\s]+$'), '')
        .trim();
  }

  /// Writes a parsed timeline into [Education.year] when imports left it blank.
  void _promoteImportedEducationYearFromBlob() {
    for (var i = 0; i < educationList.length; i++) {
      final e = educationList[i];
      if (e.year.trim().isNotEmpty) continue;
      final ext = _educationTimelineFromBlob('${e.degree} ${e.institution}');
      if (ext.isEmpty || !_looksLikeEducationPeriod(ext)) continue;

      var deg = e.degree.trim();
      var inst = e.institution.trim();
      final extLow = ext.toLowerCase();
      if (inst.isNotEmpty && inst.toLowerCase().contains(extLow)) {
        inst = _stripInsensitiveSubstringOnce(inst, ext);
      } else if (deg.isNotEmpty && deg.toLowerCase().contains(extLow)) {
        deg = _stripInsensitiveSubstringOnce(deg, ext);
      }

      educationList[i] = Education(
        degree: deg,
        institution: inst,
        year: ext,
      );
    }
  }

  void _normalizeEducationListInPlace() {
    _promoteImportedEducationYearFromBlob();
    for (var i = 0; i < educationList.length; i++) {
      final e = educationList[i];
      final ySan = _sanitizeEducationYearRaw(e.year);
      final yLine = _educationYearLine(_educationDateRaw(e));
      final nextYear =
          yLine.isNotEmpty ? yLine : (_looksLikeEducationPeriod(ySan) ? ySan : '');
      if (nextYear == e.year.trim()) continue;
      educationList[i] = Education(
        degree: e.degree,
        institution: e.institution,
        year: nextYear,
      );
    }
  }

  /// Parses imported or legacy duration strings into start/end display text and Present flag.
  ({String start, String end, bool isPresent}) _parseExperienceDurationFields(
    String raw,
  ) {
    var s = raw.trim();
    if (s.isEmpty) {
      return (start: '', end: '', isPresent: false);
    }
    s = s.replaceAll(RegExp(r'[–—]'), '-');

    var segments = s
        .split(RegExp(r'\s*-\s*|\s+to\s+', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    var isPresent = false;
    if (segments.isNotEmpty) {
      final last = segments.last.toLowerCase();
      if (last == 'present' || last == 'current' || last == 'now') {
        isPresent = true;
        segments = segments.sublist(0, segments.length - 1);
      }
    }

    if (segments.isEmpty) {
      return (start: '', end: '', isPresent: isPresent);
    }

    final startNorm = _normalizeMonthYearDisplay(segments.first);
    if (isPresent) {
      return (start: startNorm, end: '', isPresent: true);
    }
    if (segments.length >= 2) {
      final endNorm = _normalizeMonthYearDisplay(segments.last);
      return (start: startNorm, end: endNorm, isPresent: false);
    }
    return (start: startNorm, end: '', isPresent: false);
  }

  /// Parses education period stored in [Education.year] (no Present flag).
  ///
  /// Uses the **same** split/normalization rules as [_parseExperienceDurationFields]
  /// so imported strings like `Jan 2020-May 2024` or `Jan 2020 - May 2024` behave
  /// consistently with the experience card (education previously required spaces
  /// around `-`, which broke many real resumes).
  ({String start, String end}) _parseEducationPeriodFields(String raw) {
    var s = _sanitizeEducationYearRaw(raw);
    if (s.isEmpty) {
      return (start: '', end: '');
    }

    final sDash = s.replaceAll(RegExp(r'[–—]'), '-');

    // Plain calendar year ranges: `2018-2022` (do not route through `-` splitting).
    final plainYearRange = RegExp(
      r'^(19|20)\d{2}\s*-\s*(19|20)\d{2}\s*$',
    ).firstMatch(sDash);
    if (plainYearRange != null) {
      final a = plainYearRange.group(1)!;
      final b = plainYearRange.group(2)!;
      return (start: a, end: b);
    }

    // Two ISO-style tokens separated by a spaced dash (same idea as experience
    // "start - end" but avoids shredding a single `YYYY-MM-DD`).
    final isoRange = RegExp(
      r'^(\d{4}-\d{2}(?:-\d{2})?)\s*-\s*(\d{4}-\d{2}(?:-\d{2})?)\s*$',
    ).firstMatch(sDash);
    if (isoRange != null) {
      final a = _normalizeMonthYearDisplay(isoRange.group(1)!);
      final b = _normalizeMonthYearDisplay(isoRange.group(2)!);
      return (start: a.trim(), end: b.trim());
    }

    // Lone graduation date `2020-09-01` / `2020-09`.
    final singleIso = RegExp(r'^(\d{4}-\d{2}(?:-\d{2})?)\s*$').firstMatch(sDash);
    if (singleIso != null) {
      final a = _normalizeMonthYearDisplay(singleIso.group(1)!);
      return (start: a.trim(), end: '');
    }

    final x = _parseExperienceDurationFields(sDash);
    if (x.isPresent) {
      return (start: x.start, end: '');
    }
    return (start: x.start, end: x.end);
  }

  int? _monthTokenToNumber(String token) {
    final key = token.toLowerCase().replaceAll('.', '').trim();
    const byName = <String, int>{
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return byName[key];
  }

  DateTime? _parseLooseToFirstOfMonth(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    var m = RegExp(
      r'^([A-Za-z]+)\s+(\d{4})\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final mon = _monthTokenToNumber(m.group(1)!);
      final year = int.tryParse(m.group(2)!);
      if (mon != null && year != null) {
        return DateTime(year, mon, 1);
      }
    }

    m = RegExp(r'^(\d{1,2})/(\d{4})\s*$').firstMatch(t);
    if (m != null) {
      final mo = int.tryParse(m.group(1)!);
      final year = int.tryParse(m.group(2)!);
      if (mo != null && year != null && mo >= 1 && mo <= 12) {
        return DateTime(year, mo, 1);
      }
    }

    m = RegExp(r'^(\d{4})-(\d{1,2})\s*$').firstMatch(t);
    if (m != null) {
      final year = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (year != null && mo != null && mo >= 1 && mo <= 12) {
        return DateTime(year, mo, 1);
      }
    }

    m = RegExp(r'^(\d{4})\s*$').firstMatch(t);
    if (m != null) {
      final year = int.tryParse(m.group(1)!);
      if (year != null) return DateTime(year, 1, 1);
    }

    return null;
  }

  String _normalizeMonthYearDisplay(String raw) {
    final dt = _parseLooseToFirstOfMonth(raw);
    if (dt != null) return _formatMonthYear(dt);
    return raw.trim();
  }

  DateTime? _displayMonthYearToDateTime(String display) {
    return _parseLooseToFirstOfMonth(display);
  }

  Widget _pickerField({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onTap,
    IconData icon = Icons.calendar_month_rounded,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: inputBox(hint).copyWith(
              suffixIcon: Icon(icon, color: Colors.white.withOpacity(0.70)),
            ),
          ),
        ),
      ),
    );
  }

  // ================= ACTIONS =================

  void _syncResumeFieldsFromModel() {
    name.text = widget.data.name;
    email.text = widget.data.email;
    phone.text = widget.data.phone;
    summary.text = widget.data.summary;

    skills = List.from(widget.data.skills);
    experiences = List.from(widget.data.experiences);
    educationList = List.from(widget.data.educationList);
    _normalizeEducationListInPlace();

    categories = {
      "Languages": (widget.data.categories["Languages"] ?? const <String>[])
          .map(CategoryEntryDisplay.normalizeLanguageStorage)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      "Courses": List<String>.from(widget.data.categories["Courses"] ?? []),
      "Certifications":
          List<String>.from(widget.data.categories["Certifications"] ?? []),
      "City": List<String>.from(widget.data.categories["City"] ?? []),
      "Country": List<String>.from(widget.data.categories["Country"] ?? []),
      "Links": List<String>.from(widget.data.categories["Links"] ?? []),
      "Hobbies": CategoryEntryDisplay.sanitizeHobbyItems(
        widget.data.categories["Hobbies"] ?? const <String>[],
      ),
      "Volunteering":
          List<String>.from(widget.data.categories["Volunteering"] ?? []),
      "References":
          List<String>.from(widget.data.categories["References"] ?? []),
      "Projects": List<String>.from(widget.data.categories["Projects"] ?? []),
      "Achievements":
          List<String>.from(widget.data.categories["Achievements"] ?? []),
    };

    city.text = _firstCategoryValue(widget.data, 'City');
    country.text = _firstCategoryValue(widget.data, 'Country');
    if (city.text.trim().isEmpty && country.text.trim().isEmpty) {
      _migrateLegacyLocationToCityCountry();
    }

    showPersonal = true;
    showSummary = true;
    showExperience = true;
    showEducation = true;
    showSkills = true;
    showCategory = true;
  }

  Future<void> uploadResume() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
      withReadStream: true,
    );

    if (result == null) return;

    final picked = result.files.single;
    Uint8List? bytes = picked.bytes;
    final String? path = picked.path;
    final File? file = path != null ? File(path) : null;
    if (bytes == null && picked.readStream != null) {
      try {
        final b = BytesBuilder(copy: false);
        await for (final chunk in picked.readStream!) {
          b.add(chunk);
        }
        bytes = b.takeBytes();
      } catch (_) {
        // fall through to other paths / errors
      }
    }
    if (bytes == null && file == null) {
      if (mounted) {
        _showPremiumSnack(AppLocalizations.of(context).couldNotReadFile);
      }
      return;
    }

    bool looksLikePdf(Uint8List b) {
      if (b.length < 4) return false;
      // "%PDF"
      return b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _neonCyan,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppLocalizations.of(context).uploadingResume,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (bytes != null) {
        if (!looksLikePdf(bytes)) {
          throw const FormatException('Selected file is not a valid PDF.');
        }
        final extracted = await AIResumeParser.parseResumeBytes(bytes, widget.data);
        // Belt-and-suspenders: merge again with the same full text the parser used,
        // so Courses/Certs land in widget.data even if an intermediate step changed.
        AIResumeParser.mergeCoursesAndCertificationsFromFullText(
          extracted,
          widget.data,
        );
      } else {
        final extracted = await AIResumeParser.parseResume(file!, widget.data);
        AIResumeParser.mergeCoursesAndCertificationsFromFullText(
          extracted,
          widget.data,
        );
      }
      // Ensure category strings are normalized for UI + subsequent exports even if
      // the refine step is skipped (no API key) or partially fails.
      AIResumeParser.sanitizeExtractedData(widget.data);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        // More actionable message for common failure cases (encrypted/corrupt PDFs).
        final msg = '$e'.toLowerCase();
        if (msg.contains('password') ||
            msg.contains('encrypted') ||
            msg.contains('encryption')) {
          _showPremiumSnack('This PDF is password-protected. Please upload an unlocked PDF.');
        } else if (msg.contains('not a valid pdf')) {
          _showPremiumSnack('That file is not a valid PDF. Please upload a real PDF resume.');
        } else {
          _showPremiumSnack(AppLocalizations.of(context).couldNotParseResume);
        }
      }
      return;
    }

    if (mounted) Navigator.of(context).pop();

    if (!mounted) return;

    setState(_syncResumeFieldsFromModel);
    // Persist promoted education dates (year was empty on model; filled from degree/institution)
    // so preview / export see the same data as the editor.
    save(showMessage: false);
    _showPremiumSnack(AppLocalizations.of(context).resumeImported);
  }

void addExperience() => _showExperienceDialog();

Future<void> _confirmRemoveExperience(int index) async {
  if (index < 0 || index >= experiences.length) return;
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.removeExperienceTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t.removeExperienceBody,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.86),
                          backgroundColor: Colors.white.withOpacity(0.06),
                          side: BorderSide(color: Colors.white.withOpacity(0.16)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(t.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.95),
                          backgroundColor: Colors.red.withOpacity(0.18),
                          side: BorderSide(color: Colors.red.withOpacity(0.45)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(t.removeLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (ok == true && mounted) {
    setState(() => experiences.removeAt(index));
  }
}

Future<void> _confirmRemoveEducation(int index) async {
  if (index < 0 || index >= educationList.length) return;
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.removeEducationTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t.removeEducationBody,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.86),
                          backgroundColor: Colors.white.withOpacity(0.06),
                          side: BorderSide(color: Colors.white.withOpacity(0.16)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(t.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.95),
                          backgroundColor: Colors.red.withOpacity(0.18),
                          side: BorderSide(color: Colors.red.withOpacity(0.45)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(t.removeLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (ok == true && mounted) {
    setState(() => educationList.removeAt(index));
  }
}

void _showExperienceDialog({int? editIndex}) {
  final loc = AppLocalizations.of(context);
  final isEdit = editIndex != null;
  final existing =
      editIndex != null ? experiences[editIndex] : null;

  final r = TextEditingController(text: existing?.role ?? '');
  final c = TextEditingController(text: existing?.company ?? '');
  final parsedDuration =
      _parseExperienceDurationFields(existing?.duration ?? '');
  final startMY = TextEditingController(text: parsedDuration.start);
  final endMY = TextEditingController(text: parsedDuration.end);
  // New entries default to Present (current role); edits use parsed duration.
  bool isPresent =
      existing == null ? true : parsedDuration.isPresent;
  final bullets = TextEditingController(
    text: existing?.description.join('\n') ?? '',
  );

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: isEdit ? loc.editExperienceTitle : loc.addExperienceTitle,
      fields: [
        field(r, AppLocalizations.of(context).roleLabel),
        field(c, AppLocalizations.of(context).companyLabel),
        StatefulBuilder(
          builder: (ctx, setModal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pickerField(
                  controller: startMY,
                  hint: loc.startMonthYearHint,
                  onTap: () async {
                    final picked = await _pickMonthYear(
                      context,
                      initial: _displayMonthYearToDateTime(startMY.text),
                    );
                    if (picked == null) return;
                    startMY.text = _formatMonthYear(picked);
                    if (!mounted) return;
                    setModal(() {});
                  },
                ),
                _pickerField(
                  controller: endMY,
                  hint: loc.endMonthYearHint,
                  onTap: isPresent
                      ? () {}
                      : () async {
                          final picked = await _pickMonthYear(
                            context,
                            initial: _displayMonthYearToDateTime(endMY.text),
                          );
                          if (picked == null) return;
                          endMY.text = _formatMonthYear(picked);
                          if (!mounted) return;
                          setModal(() {});
                        },
                  icon: isPresent
                      ? Icons.lock_rounded
                      : Icons.calendar_month_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).present,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.86),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Switch(
                          value: isPresent,
                          onChanged: (v) {
                            isPresent = v;
                            if (isPresent) endMY.clear();
                            setModal(() {});
                          },
                          activeColor: _neonCyan,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        field(
          bullets,
          AppLocalizations.of(context).bulletPointsHint,
          maxLines: 6,
        ),
      ],
      onSave: () {
        setState(() {
          final parsedBullets = bullets.text
              .split("\n")
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

          final st = startMY.text.trim();
          final en = endMY.text.trim();
          final computedDuration = st.isEmpty
              ? ''
              : (isPresent
                  ? '$st - Present'
                  : (en.isEmpty ? st : '$st - $en'));
          final entry = Experience(
            role: r.text,
            company: c.text,
            duration: computedDuration,
            description: parsedBullets,
          );
          if (editIndex != null) {
            experiences[editIndex] = entry;
          } else {
            experiences.add(entry);
          }
        });
        Navigator.pop(context);
      },
    ),
  );
}
void addCategoryItem(String key) {
  if (key == 'References') {
    _showAddReferenceDialog();
    return;
  }
  if (key == 'Courses') {
    _showAddCourseDialog();
    return;
  }
  if (key == 'Certifications') {
    _showAddCertificationDialog();
    return;
  }
  if (key == 'Languages') {
    _showAddLanguageDialog();
    return;
  }
  if (key == 'Projects') {
    _showAddProjectDialog();
    return;
  }
  if (key == 'Achievements') {
    _showAddAchievementDialog();
    return;
  }

  final input = TextEditingController();
  final t = AppLocalizations.of(context);
  final title = _categoryDisplayTitle(key, t);

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: t.addToCategoryTitle(title),
      fields: [
        field(input, t.enterCategoryItemHint(title)),
      ],
      onSave: () {
        if (input.text.trim().isEmpty) return;

        setState(() {
          categories[key]!.add(input.text.trim());
        });

        Navigator.pop(context);
      },
    ),
  );
}

void _showAddProjectDialog() {
  final titleC = TextEditingController();
  final durationC = TextEditingController();
  final detailsC = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: 'Add Project',
      fields: [
        field(titleC, 'Project name'),
        field(durationC, 'Duration (e.g. Jan 2023 - May 2023)'),
        field(detailsC, 'Details', maxLines: 4),
      ],
      onSave: () {
        final name = titleC.text.trim();
        if (name.isEmpty) return;
        final duration = durationC.text.trim();
        final details = detailsC.text.trim().replaceAll('\n', ' ');

        final parts = <String>[
          name,
          if (duration.isNotEmpty) duration,
          if (details.isNotEmpty) details,
        ];
        setState(() {
          categories['Projects']!.add(parts.join(_kCategoryFieldSep));
        });
        Navigator.pop(context);
      },
    ),
  );
}

void _showAddReferenceDialog() {
  final nameC = TextEditingController();
  final phoneC = TextEditingController();
  final t = AppLocalizations.of(context);

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: t.addReferenceTitle,
      fields: [
        field(nameC, t.referenceNameLabel),
        field(phoneC, t.referencePhoneLabel),
      ],
      onSave: () {
        final n = nameC.text.trim();
        if (n.isEmpty) return;
        final p = phoneC.text.trim();
        setState(() {
          categories['References']!.add('$n$_kCategoryFieldSep$p');
        });
        Navigator.pop(context);
      },
    ),
  );
}

void _showAddAchievementDialog() {
  final titleC = TextEditingController();
  final whereC = TextEditingController();
  final whenC = TextEditingController();
  final t = AppLocalizations.of(context);

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: t.addAchievementTitle,
      fields: [
        field(titleC, t.achievementTitleLabel),
        field(whereC, t.achievementWhereHint),
        field(whenC, t.achievementWhenHint),
      ],
      onSave: () {
        final title = titleC.text.trim();
        if (title.isEmpty) return;
        final where = whereC.text.trim();
        final when = whenC.text.trim();
        setState(() {
          if (where.isEmpty && when.isEmpty) {
            categories['Achievements']!.add(title);
          } else if (when.isEmpty) {
            categories['Achievements']!.add('$title$_kCategoryFieldSep$where');
          } else if (where.isEmpty) {
            categories['Achievements']!
                .add('$title$_kCategoryFieldSep$_kCategoryFieldSep$when');
          } else {
            categories['Achievements']!
                .add('$title$_kCategoryFieldSep$where$_kCategoryFieldSep$when');
          }
        });
        Navigator.pop(context);
      },
    ),
  );
}

void _showAddCertificationDialog() {
  final titleC = TextEditingController();
  final myC = TextEditingController();
  final t = AppLocalizations.of(context);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) {
        return modernDialog(
          title: t.addCertificationTitle,
          fields: [
            field(titleC, t.certificationNameLabel),
            _pickerField(
              controller: myC,
              hint: t.certificationMonthYearHint,
              onTap: () async {
                final picked = await _pickMonthYear(ctx);
                if (picked == null) return;
                myC.text = _formatMonthYear(picked);
                if (!mounted) return;
                setModal(() {});
              },
            ),
          ],
          onSave: () {
            final title = titleC.text.trim();
            if (title.isEmpty) return;
            final my = myC.text.trim();
            setState(() {
              if (my.isEmpty) {
                categories['Certifications']!.add(title);
              } else {
                categories['Certifications']!.add('$title$_kCategoryFieldSep$my');
              }
            });
            Navigator.pop(context);
          },
        );
      },
    ),
  );
}

void _showAddCourseDialog() {
  final titleC = TextEditingController();
  final myC = TextEditingController();
  final t = AppLocalizations.of(context);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) {
        return modernDialog(
          title: t.addCourseTitle,
          fields: [
            field(titleC, t.courseNameLabel),
            _pickerField(
              controller: myC,
              hint: t.courseMonthYearHint,
              onTap: () async {
                final picked = await _pickMonthYear(ctx);
                if (picked == null) return;
                myC.text = _formatMonthYear(picked);
                if (!mounted) return;
                setModal(() {});
              },
            ),
          ],
          onSave: () {
            final title = titleC.text.trim();
            if (title.isEmpty) return;
            final my = myC.text.trim();
            setState(() {
              if (my.isEmpty) {
                categories['Courses']!.add(title);
              } else {
                categories['Courses']!.add('$title$_kCategoryFieldSep$my');
              }
            });
            Navigator.pop(context);
          },
        );
      },
    ),
  );
}

void _showAddLanguageDialog() {
  final langC = TextEditingController();
  final t = AppLocalizations.of(context);
  var level = 'fluent';

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) {
        return modernDialog(
          title: t.addLanguageTitle,
          fields: [
            field(langC, t.languageNameLabel),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DropdownButtonFormField<String>(
                value: level,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                decoration: inputBox(t.languageProficiencyFieldLabel),
                items: [
                  DropdownMenuItem(
                    value: 'native',
                    child: Text(
                      t.languageProficiencyLabel('native'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'fluent',
                    child: Text(
                      t.languageProficiencyLabel('fluent'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'professional',
                    child: Text(
                      t.languageProficiencyLabel('professional'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'intermediate',
                    child: Text(
                      t.languageProficiencyLabel('intermediate'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'basic',
                    child: Text(
                      t.languageProficiencyLabel('basic'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setModal(() => level = v);
                },
              ),
            ),
          ],
          onSave: () {
            final lang = langC.text.trim();
            if (lang.isEmpty) return;
            setState(() {
              categories['Languages']!.add('$lang$_kCategoryFieldSep$level');
            });
            Navigator.pop(context);
          },
        );
      },
    ),
  );
}
void addEducation() => _showEducationDialog();

void _showEducationDialog({int? editIndex}) {
  final loc = AppLocalizations.of(context);
  final isEdit = editIndex != null;
  final existing =
      editIndex != null ? educationList[editIndex] : null;

  final d = TextEditingController(text: existing?.degree ?? '');
  final inst = TextEditingController(text: existing?.institution ?? '');
  final parsedEdu = _parseEducationPeriodFields(
    existing == null ? '' : _educationDateRaw(existing),
  );
  final eduStartMY = TextEditingController(text: parsedEdu.start);
  final eduEndMY = TextEditingController(text: parsedEdu.end);

  showDialog(
    context: context,
    builder: (_) => modernDialog(
      title: isEdit ? loc.editEducationTitle : loc.addEducationTitle,
      fields: [
        field(d, loc.degreeLabel),
        field(inst, loc.institutionLabel),
        StatefulBuilder(
          builder: (ctx, setModal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pickerField(
                  controller: eduStartMY,
                  hint: loc.startMonthYearHint,
                  onTap: () async {
                    final picked = await _pickMonthYear(
                      context,
                      initial: _displayMonthYearToDateTime(eduStartMY.text),
                    );
                    if (picked == null) return;
                    eduStartMY.text = _formatMonthYear(picked);
                    setModal(() {});
                  },
                ),
                _pickerField(
                  controller: eduEndMY,
                  hint: loc.endMonthYearHint,
                  onTap: () async {
                    final picked = await _pickMonthYear(
                      context,
                      initial: _displayMonthYearToDateTime(eduEndMY.text),
                    );
                    if (picked == null) return;
                    eduEndMY.text = _formatMonthYear(picked);
                    setModal(() {});
                  },
                ),
              ],
            );
          },
        ),
      ],
      onSave: () {
        setState(() {
          final st = eduStartMY.text.trim();
          final en = eduEndMY.text.trim();
          final yearStored =
              st.isEmpty ? '' : (en.isEmpty ? st : '$st - $en');
          final entry = Education(
            degree: d.text,
            institution: inst.text,
            year: yearStored,
          );
          if (editIndex != null) {
            educationList[editIndex] = entry;
          } else {
            educationList.add(entry);
          }
        });
        Navigator.pop(context);
      },
    ),
  );
}
}

class _FuturisticEditorBackdrop extends StatefulWidget {
  final ValueListenable<double> scrollPixels;
  const _FuturisticEditorBackdrop({required this.scrollPixels});

  @override
  State<_FuturisticEditorBackdrop> createState() =>
      _FuturisticEditorBackdropState();
}

class _FuturisticEditorBackdropState extends State<_FuturisticEditorBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Background is intentionally NOT driven by scroll to avoid
      // “moving/shrinking layer” artifacts on long pages.
      animation: _ambient,
      builder: (context, _) {
        final wave = math.sin(_ambient.value * math.pi * 2);
        final driftY = wave * 18.0;
        final driftX = wave * 12.0;

        // Fixed backdrop: no scroll-driven translate/scale.
        const gradDy = 0.0;
        const gradDx = 0.0;
        final cx =
            (-0.65 + (driftX * 0.0008).clamp(-0.02, 0.02)).clamp(-1.0, 1.0);
        final cy =
            (-0.75 + (driftY * 0.0008).clamp(-0.02, 0.02)).clamp(-1.0, 1.0);
        const meshScale = 1.0;

        final orbTopDy = driftY;
        final orbTopDx = driftX;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Opaque base so nothing “shows through” from overflow paints.
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFF070A12)),
            ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(gradDx, gradDy),
                child: Transform.scale(
                  scale: meshScale,
                  alignment: Alignment.topLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(cx, cy),
                        radius: 1.25,
                        colors: const [
                          Color(0xFF1B2A4A),
                          Color(0xFF070A12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _ParallaxCareerIconLayer(
                  scrollPixels: 0,
                  driftX: driftX,
                  driftY: driftY,
                ),
              ),
            ),
            Positioned(
              left: -160 + orbTopDx,
              top: -160 + orbTopDy,
              child: const _GlowOrb(color: Color(0xFF7C3AED), size: 280),
            ),
            // No bottom cyan orb — its large radius + bottom-right anchor caused a
            // bright vertical band behind the scroll content and action dock.
          ],
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.35),
            color.withOpacity(0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// Subtle resume / AI / ATS themed icons that drift with scroll + ambient motion.
class _ParallaxCareerIconLayer extends StatelessWidget {
  final double scrollPixels;
  final double driftX;
  final double driftY;

  const _ParallaxCareerIconLayer({
    required this.scrollPixels,
    required this.driftX,
    required this.driftY,
  });

  static const List<IconData> _icons = [
    Icons.description_rounded,
    Icons.analytics_rounded,
    Icons.auto_awesome_rounded,
    Icons.psychology_rounded,
    Icons.work_outline_rounded,
    Icons.article_rounded,
    Icons.assessment_rounded,
    Icons.check_circle_outline_rounded,
    Icons.school_rounded,
    Icons.trending_up_rounded,
    Icons.smart_toy_rounded,
    Icons.mail_outline_rounded,
    Icons.folder_special_rounded,
    Icons.insert_drive_file_rounded,
    Icons.speed_rounded,
    Icons.verified_rounded,
  ];

  /// Stable pseudo-random in [0, 1) — well spread per (i, channel); avoids sin() bunching.
  static double _hash01(int i, int channel) {
    final h = Object.hash(i, channel, 0xC0FFEE, 926371);
    return (h.abs() % 1000003) / 1000003.0;
  }

  /// Stratified grid + jitter: guarantees coverage of the whole area. A
  /// (n·φ, n·φ²) Kronecker pair lies near a line in the unit square, which
  /// read as a diagonal streak behind the form.
  static (double, double) _spreadXY(int i) {
    final cols = math.max(4, math.sqrt(_decorCount * 1.2).ceil());
    final rows = math.max(3, (_decorCount / cols).ceil());
    final cx = i % cols;
    final cy = i ~/ cols;
    final jx = _hash01(i, 11);
    final jy = _hash01(i, 13);
    final fx = (cx + 0.18 + 0.64 * jx) / cols;
    final fy = (cy + 0.18 + 0.64 * jy) / rows;
    return (
      fx.clamp(0.02, 0.98),
      fy.clamp(0.02, 0.98),
    );
  }

  /// More icons than the palette so the page feels full; positions are scattered.
  static const int _decorCount = 26;

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final w = sz.width;
    final h = sz.height;
    final px = scrollPixels;

    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: List.generate(_decorCount, (i) {
        final icon = _icons[i % _icons.length];
        final (uX, uY) = _spreadXY(i);
        final uD = _hash01(i, 3);
        final uS = _hash01(i, 5);
        final uO = _hash01(i, 7);

        final baseX = w * (0.03 + 0.94 * uX);
        final baseY = h * (0.03 + 0.94 * uY);
        final depth = 0.45 + 0.75 * uD;
        final ox = driftX * depth * 1.0 + px * 0.036 * depth;
        final oy = driftY * depth * 0.75 + px * 0.045 * depth;
        final size = 18.0 + uS * 22.0;
        final opacity = 0.038 + uO * 0.055;

        final left = (baseX + ox - size * 0.5)
            .clamp(0.0, math.max(0.0, w - size))
            .toDouble();
        final top = (baseY + oy - size * 0.5)
            .clamp(0.0, math.max(0.0, h - size))
            .toDouble();

        return Positioned(
          left: left,
          top: top,
          child: Icon(
            icon,
            size: size,
            color: Colors.white.withOpacity(opacity.clamp(0.035, 0.095)),
          ),
        );
      }),
    );
  }
}

class _ProfileAvatarRing extends StatelessWidget {
  final double radius;
  final File? imageFile;
  const _ProfileAvatarRing({required this.radius, required this.imageFile});

  @override
  Widget build(BuildContext context) {
    final outer = radius + 3;
    return Container(
      width: outer * 2,
      height: outer * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Center(
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white.withOpacity(0.10),
          backgroundImage: imageFile != null ? FileImage(imageFile!) : null,
          child: imageFile == null
              ? const Icon(Icons.person, size: 40, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}