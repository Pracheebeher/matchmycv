import 'package:flutter/material.dart';
import '../models/canvas_element.dart';
import '../services/pdf_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/uniform_app_bar.dart';
import 'resume_canvas.dart';

class DragEditorPage extends StatefulWidget {
  const DragEditorPage({super.key});

  @override
  State<DragEditorPage> createState() => _DragEditorPageState();
}

class _DragEditorPageState extends State<DragEditorPage> {
  List<CanvasElement> elements = [
    CanvasElement(
      id: "1",
      type: "text",
      value: "Your Name",
      x: 40,
      y: 40,
      fontSize: 24,
    ),
    CanvasElement(
      id: "2",
      type: "text",
      value: "email@gmail.com",
      x: 40,
      y: 80,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UniformAppBar.material(
        AppLocalizations.of(context).dragResumeBuilderTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              await PdfService.exportFromCanvas(elements);
            },
          )
        ],
      ),

      body: Row(
        children: [

          // 🔥 TOOLBAR
          Container(
            width: 80,
            color: Colors.grey.shade200,
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.text_fields),
                  onPressed: () {
                    setState(() {
                      elements.add(
                        CanvasElement(
                          id: DateTime.now().toString(),
                          type: "text",
                          value: "New Text",
                          x: 50,
                          y: 50,
                        ),
                      );
                    });
                  },
                ),
              ],
            ),
          ),

          // 🔥 CANVAS
          Expanded(
            child: ResumeCanvas(
              elements: elements,
              onUpdate: (updated) {
                setState(() => elements = updated);
              },
            ),
          ),
        ],
      ),
    );
  }
}