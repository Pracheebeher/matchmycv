import 'package:flutter/material.dart';
import '../models/canvas_element.dart';
import '../l10n/app_localizations.dart';

class ResumeCanvas extends StatelessWidget {
  final List<CanvasElement> elements;
  final Function(List<CanvasElement>) onUpdate;

  const ResumeCanvas({
    super.key,
    required this.elements,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: elements.map((e) {
          return Positioned(
            left: e.x,
            top: e.y,
            child: Draggable(
              feedback: Material(
                color: Colors.transparent,
                child: _buildElement(e),
              ),
              childWhenDragging: Container(),
              child: GestureDetector(
                onDoubleTap: () => _editText(context, e),
                child: _buildElement(e),
              ),
              onDragEnd: (details) {
                e.x = details.offset.dx;
                e.y = details.offset.dy;
                onUpdate(elements);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildElement(CanvasElement e) {
    return Text(
      e.value,
      style: TextStyle(fontSize: e.fontSize),
    );
  }

  void _editText(BuildContext context, CanvasElement e) {
    final controller = TextEditingController(text: e.value);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.editTextTitle),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () {
              e.value = controller.text;
              Navigator.pop(context);
            },
            child: const Text("Save"),
          )
        ],
      ),
    );
  }
}