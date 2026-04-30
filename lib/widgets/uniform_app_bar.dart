import 'package:flutter/material.dart';

/// Shared top bar styling: dark strip, gradient title, white icons.
class UniformAppBar {
  UniformAppBar._();

  static const Color headerBackground = Color(0xFF070A12);

  static const LinearGradient _titleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFBDEBFF),
    ],
  );

  /// Title text: 18 / w900 / letterSpacing 0.2, white→cyan gradient fill.
  static Widget gradientTitle(String text, {int? maxLines}) {
    return ShaderMask(
      shaderCallback: (rect) => _titleGradient.createShader(rect),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static AppBar material(
    String title, {
    List<Widget>? actions,
    bool automaticallyImplyLeading = true,
    PreferredSizeWidget? bottom,
    Widget? titleWidget,
  }) {
    return AppBar(
      title: titleWidget ?? gradientTitle(title),
      centerTitle: false,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: headerBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: actions,
      bottom: bottom,
    );
  }
}
