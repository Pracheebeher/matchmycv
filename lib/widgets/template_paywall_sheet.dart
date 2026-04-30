import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../l10n/app_localizations.dart';
import 'app_toast.dart';
import '../services/template_billing.dart';
import '../services/template_entitlements_store.dart';
import '../services/template_pricing.dart';

class TemplatePaywallSheet extends StatefulWidget {
  final String templateId;
  final String templateName;

  const TemplatePaywallSheet({
    super.key,
    required this.templateId,
    required this.templateName,
  });

  static Future<void> open(
    BuildContext context, {
    required String templateId,
    required String templateName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TemplatePaywallSheet(
        templateId: templateId,
        templateName: templateName,
      ),
    );
  }

  @override
  State<TemplatePaywallSheet> createState() => _TemplatePaywallSheetState();
}

class _TemplatePaywallSheetState extends State<TemplatePaywallSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _purchase() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TemplateBilling.instance.buyTemplate(widget.templateId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final t = AppLocalizations.of(context);
      Navigator.pop(context);
      AppToast.infoMessenger(messenger, t.purchaseStarted);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TemplateBilling.instance.restorePurchases();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final t = AppLocalizations.of(context);
      Navigator.pop(context);
      AppToast.infoMessenger(messenger, t.restoreStarted);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _debugUnlock() async {
    await TemplateEntitlementsStore.instance.debugUnlock(widget.templateId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    Navigator.pop(context);
    AppToast.infoMessenger(messenger, t.debugUnlockedTemplate);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: appCountryCode,
      builder: (context, _) {
        final country = appCountryCode.value;
        final minor = TemplatePricing.minorUnitsForCountry(country);
        final currency = TemplatePricing.currencyCodeForCountry(country);
        final shown = TemplatePricing.formatMinor(minor, currency);
        final product =
            TemplateBilling.instance.productForTemplate(widget.templateId);
        final playPrice = product?.price;
        final productId = TemplateBilling.productIdForTemplate(widget.templateId);
        final missingProduct = product == null;

        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1020),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.templatePaywallTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.templateName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.templatePaywallPriceHint(shown, country),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (playPrice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.templatePaywallPlayPrice(playPrice),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (missingProduct) ...[
                    const SizedBox(height: 10),
                    Text(
                      t.playProductNotConfigured(productId),
                      style: const TextStyle(
                        color: Color(0xFFFFD6A5),
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    t.templatePaywallBillingNote,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: (_busy || missingProduct) ? null : _purchase,
                    child: Text(t.unlockTemplateFor(shown)),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : _restore,
                    child: Text(t.restorePurchases),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _busy ? null : _debugUnlock,
                      child: Text(t.debugUnlockTemplate),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
