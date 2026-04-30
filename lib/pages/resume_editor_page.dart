import 'dart:async';

import 'package:flutter/material.dart';
import '../models/resume_model.dart';
import '../services/pdf_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../widgets/uniform_app_bar.dart';

class ResumeEditorPage extends StatelessWidget {
  final ResumeData data;
  final String templateId;

  const ResumeEditorPage({
    super.key,
    required this.data,
    required this.templateId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: UniformAppBar.material(
        AppLocalizations.of(context).resumePreviewTitle,
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: AppButtons.primary("Download", Icons.download, () {
                unawaited(() async {
                  try {
                    await PdfService.downloadResume(data: data);
                    if (!context.mounted) return;
                    AppToast.success(
                      context,
                      AppLocalizations.of(context).successfullyDownloaded,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    AppToast.error(
                      context,
                      AppLocalizations.of(context).downloadCouldNotComplete,
                    );
                  }
                }());
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButtons.secondary("Share", Icons.share, () {
                unawaited(() async {
                  try {
                    await PdfService.shareResume(data: data);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppToast.error(
                      context,
                      AppLocalizations.of(context).shareCouldNotComplete,
                    );
                  }
                }());
              }),
            ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // HEADER
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: data.profileImage != null
                        ? FileImage(data.profileImage!)
                        : null,
                    child: data.profileImage == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(data.email),
                      Text(data.phone),
                    ],
                  )
                ],
              ),

              const SizedBox(height: 20),

              // SUMMARY
              if (data.summary.isNotEmpty) ...[
                const Text("Summary",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(data.summary),
                const SizedBox(height: 20),
              ],

              // SKILLS
              if (data.skills.isNotEmpty) ...[
                const Text("Skills",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children:
                      data.skills.map((s) => Chip(label: Text(s))).toList(),
                ),
                const SizedBox(height: 20),
              ],

              // EXPERIENCE
              if (data.experiences.isNotEmpty) ...[
                const Text("Experience",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...data.experiences.map((e) => ListTile(
                      leading: const Icon(Icons.work),
                      title: Text("${e.role} - ${e.company}"),
                      subtitle: Text(e.duration),
                    )),
                const SizedBox(height: 20),
              ],

              // EDUCATION
              if (data.educationList.isNotEmpty) ...[
                const Text("Education",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...data.educationList.map((e) => ListTile(
                      leading: const Icon(Icons.school),
                      title: Text(e.degree),
                      subtitle: Text("${e.institution} · ${e.year}"),
                    )),
                const SizedBox(height: 20),
              ],

              // 🔥 ALL CATEGORIES
              ...data.categories.entries.map((entry) {
                if (entry.value.isEmpty) return const SizedBox();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 6,
                      children: entry.value
                          .map((e) => Chip(label: Text(e)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}