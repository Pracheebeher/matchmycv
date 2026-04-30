import 'package:flutter/material.dart';

enum _AppToastKind { validation, info, success, error }

/// Compact floating messages for validation, brief confirmations, and errors.
class AppToast {
  AppToast._();

  static void validation(BuildContext context, String message) =>
      _showOnContext(context, message, _AppToastKind.validation);

  static void info(BuildContext context, String message) =>
      _showOnContext(context, message, _AppToastKind.info);

  static void success(BuildContext context, String message) =>
      _showOnContext(context, message, _AppToastKind.success);

  static void error(BuildContext context, String message) =>
      _showOnContext(context, message, _AppToastKind.error);

  /// Use after closing a dialog/route when the previous [BuildContext] may be
  /// invalid, but the scaffold messenger is still the same.
  static void successMessenger(
    ScaffoldMessengerState messenger,
    String message, {
    double bottomMargin = 32,
  }) {
    _showOnMessenger(messenger, message, _AppToastKind.success, bottomMargin);
  }

  static void infoMessenger(
    ScaffoldMessengerState messenger,
    String message, {
    double bottomMargin = 32,
  }) {
    _showOnMessenger(messenger, message, _AppToastKind.info, bottomMargin);
  }

  static void _showOnContext(
    BuildContext context,
    String message,
    _AppToastKind kind,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    _showOnMessenger(messenger, message, kind, bottom);
  }

  static void _showOnMessenger(
    ScaffoldMessengerState messenger,
    String message,
    _AppToastKind kind,
    double bottomMargin,
  ) {
    late final Color background;
    late final Color foreground;
    switch (kind) {
      case _AppToastKind.validation:
        background = const Color(0xFF92400E).withOpacity(0.94);
        foreground = const Color(0xFFFFFBEB);
        break;
      case _AppToastKind.info:
        background = const Color(0xFF0F172A).withOpacity(0.92);
        foreground = const Color(0xFFF1F5F9);
        break;
      case _AppToastKind.success:
        background = const Color(0xFF14532D).withOpacity(0.92);
        foreground = const Color(0xFFECFDF5);
        break;
      case _AppToastKind.error:
        background = const Color(0xFF7F1D1D).withOpacity(0.94);
        foreground = const Color(0xFFFEF2F2);
        break;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
        padding: EdgeInsets.zero,
        duration: Duration(seconds: kind == _AppToastKind.error ? 3 : 2),
        content: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
