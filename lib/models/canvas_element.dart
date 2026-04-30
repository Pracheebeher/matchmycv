class CanvasElement {
  String id;
  String type; // text
  String value;

  double x;
  double y;

  double fontSize;

  CanvasElement({
    required this.id,
    required this.type,
    required this.value,
    required this.x,
    required this.y,
    this.fontSize = 14,
  });
}