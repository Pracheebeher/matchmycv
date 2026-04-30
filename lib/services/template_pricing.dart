import 'dart:math' as math;

/// Display-only pricing used in the paywall UI.
///
/// Store/IAP still charges the configured Play price; this is what we *show*
/// before Google Play shows its own localized sheet.
class TemplatePricing {
  const TemplatePricing._();

  /// Minor units (e.g. cents) for a single template purchase in a country.
  static int minorUnitsForCountry(String countryCode) {
    final c = countryCode.toUpperCase();
    switch (c) {
      case 'IN':
        return 9900; // ₹99.00
      case 'US':
      case 'CA':
      case 'AU':
      case 'NZ':
      case 'SG':
        return 199; // $1.99 (or local currency with same minor digits)
      case 'GB':
        return 199; // £1.99
      case 'DE':
      case 'FR':
      case 'ES':
      case 'IT':
      case 'NL':
      case 'BE':
      case 'AT':
      case 'IE':
        return 199; // €1.99
      default:
        return 199;
    }
  }

  static String currencyCodeForCountry(String countryCode) {
    final c = countryCode.toUpperCase();
    switch (c) {
      case 'IN':
        return 'INR';
      case 'GB':
        return 'GBP';
      case 'DE':
      case 'FR':
      case 'ES':
      case 'IT':
      case 'NL':
      case 'BE':
      case 'AT':
      case 'IE':
        return 'EUR';
      default:
        return 'USD';
    }
  }

  static String formatMinor(int minorUnits, String currencyCode) {
    final code = currencyCode.toUpperCase();
    final digits = switch (code) {
      'JPY' => 0,
      'KRW' => 0,
      _ => 2,
    };
    final divisor = math.pow(10, digits).toDouble();
    final major = minorUnits / divisor;
    final symbol = switch (code) {
      'INR' => '₹',
      'USD' => r'$',
      'GBP' => '£',
      'EUR' => '€',
      _ => '$code ',
    };
    if (digits == 0) {
      return '$symbol${major.round()}';
    }
    return '$symbol${major.toStringAsFixed(digits)}';
  }
}
