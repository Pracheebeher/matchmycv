import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';

/// Picker UI for country + app language. Updates [appLocale] and [appCountryCode].
class RegionLanguageSheet {
  RegionLanguageSheet._();

  static const Map<String, String> countryNames = <String, String>{
    'US': 'United States',
    'IN': 'India',
    'GB': 'United Kingdom',
    'DE': 'Germany',
    'FR': 'France',
    'ES': 'Spain',
    'IT': 'Italy',
    'NL': 'Netherlands',
    'IE': 'Ireland',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'BE': 'Belgium',
    'AT': 'Austria',
    'PT': 'Portugal',
    'PL': 'Poland',
    'DK': 'Denmark',
    'NO': 'Norway',
    'FI': 'Finland',
  };

  static const Map<String, String> languageNames = <String, String>{
    'EN': 'English',
    'HI': 'Hindi',
    'DE': 'German',
    'FR': 'French',
    'ES': 'Spanish',
    'IT': 'Italian',
  };

  static List<String> get countries =>
      countryNames.keys.toList(growable: false);

  static List<String> get languages =>
      languageNames.keys.toList(growable: false);

  static String languageKeyForLocale(Locale locale) {
    final k = locale.languageCode.toUpperCase();
    if (languageNames.containsKey(k)) return k;
    return 'EN';
  }

  static Future<void> open(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    var c = appCountryCode.value;
    var l = languageKeyForLocale(appLocale.value);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1020),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void setCountry(String code) {
              setModalState(() => c = code);
              appCountryCode.value = code;
            }

            void setLanguage(String code) {
              setModalState(() => l = code);
              appLocale.value = Locale(code.toLowerCase());
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        t.sheetTitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _SheetDropdown(
                    label: t.sheetCountryLabel,
                    value: c,
                    items: countries,
                    itemLabelFor: (code) =>
                        '${countryNames[code] ?? code} ($code)',
                    onChanged: (v) => setCountry(v ?? c),
                  ),
                  const SizedBox(height: 12),
                  _SheetDropdown(
                    label: t.sheetLanguageLabel,
                    value: l,
                    items: languages,
                    itemLabelFor: (code) =>
                        '${languageNames[code] ?? code} ($code)',
                    onChanged: (v) => setLanguage(v ?? l),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        t.sheetDone,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SheetDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final String Function(String value)? itemLabelFor;
  final ValueChanged<String?> onChanged;

  const _SheetDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.itemLabelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF0B1020),
              iconEnabledColor: Colors.white.withOpacity(0.8),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              items: items
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e,
                      child: Text(itemLabelFor?.call(e) ?? e),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
