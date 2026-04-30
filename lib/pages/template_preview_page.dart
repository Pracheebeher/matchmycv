import 'package:flutter/material.dart';
import '../widgets/uniform_app_bar.dart';
import '../models/resume_model.dart';
import 'resume_editor_page.dart';

class TemplatePreviewPage extends StatelessWidget {
  final ResumeData data;
  final String image;
  final String name;
  final String templateId;

  const TemplatePreviewPage({
    super.key,
    required this.data,
    required this.image,
    required this.name,
    required this.templateId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: UniformAppBar.material(name),
      body: Column(
        children: [
          Expanded(
            child: Image.asset(image, fit: BoxFit.contain),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.white,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResumeEditorPage(
                      data: data,
                      templateId: templateId,
                    ),
                  ),
                );
              },
              child: const Text("Edit This Template"),
            ),
          )
        ],
      ),
    );
  }
}