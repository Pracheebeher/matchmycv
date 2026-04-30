import 'package:flutter/material.dart';
import '../services/premium_service.dart';
import 'app_toast.dart';
import '../l10n/app_localizations.dart';

class PremiumDialog {
  static void show(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text("Go Premium 🚀"),
        content: const Text(
          "Unlock all templates, ATS optimizer & AI features.\n\nOnly €4.99/month",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final t = AppLocalizations.of(dialogContext);
              PremiumService.unlockPremium();
              Navigator.pop(dialogContext);
              AppToast.successMessenger(
                messenger,
                t.premiumUnlockedShort,
              );
            },
            child: const Text("Upgrade"),
          ),
        ],
      ),
    );
  }
}