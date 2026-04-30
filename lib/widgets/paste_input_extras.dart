import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Inserts plain-text clipboard content at the current selection (or at the end).
Future<bool> pastePlainTextAtSelection(TextEditingController controller) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) return false;

  final value = controller.value;
  var start = value.selection.start;
  var end = value.selection.end;
  if (!value.selection.isValid || start < 0 || end < 0) {
    start = end = value.text.length;
  }
  if (start > end) {
    final t = start;
    start = end;
    end = t;
  }
  start = start.clamp(0, value.text.length);
  end = end.clamp(0, value.text.length);

  final newText = value.text.replaceRange(start, end, text);
  final newOffset = start + text.length;
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newOffset),
  );
  return true;
}

/// Long-press / right-click: show a single **Paste** action (no trailing icons).
Widget buildPasteContextMenu({
  required EditableTextState editableTextState,
  required TextEditingController controller,
  required String pasteLabel,
}) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          pastePlainTextAtSelection(controller);
        },
        label: pasteLabel,
      ),
    ],
  );
}
