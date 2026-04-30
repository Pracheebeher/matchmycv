import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'template_entitlements_store.dart';

/// Google Play Billing integration for per-template unlocks.
///
/// Configure **non-consumable** products in Play Console with these IDs:
/// `template_3` … `template_8`
class TemplateBilling {
  TemplateBilling._();
  static final TemplateBilling instance = TemplateBilling._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _initialized = false;
  final Map<String, ProductDetails> _products = {};

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[billing] IAP not available on this device/build.');
      }
      return;
    }

    _sub = _iap.purchaseStream.listen(_onPurchases, onDone: () {}, onError: (_) {});
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final ids = <String>{
      for (final id in const ['3', '4', '5', '6', '7', '8']) productIdForTemplate(id),
    };
    final resp = await _iap.queryProductDetails(ids);
    if (resp.error != null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[billing] queryProductDetails error: ${resp.error}');
      }
    }
    for (final p in resp.productDetails) {
      _products[p.id] = p;
    }
    if (kDebugMode && _products.isEmpty) {
      // ignore: avoid_print
      print(
        '[billing] No products returned. Create non-consumables in Play Console: '
        '${ids.join(", ")}',
      );
    }
  }

  static String productIdForTemplate(String templateId) => 'template_$templateId';

  ProductDetails? productForTemplate(String templateId) =>
      _products[productIdForTemplate(templateId)];

  Future<void> buyTemplate(String templateId) async {
    await init();
    final pid = productIdForTemplate(templateId);
    final p = _products[pid];
    if (p == null) {
      throw StateError(
        'Play product "$pid" not found. Create it in Play Console (non-consumable) '
        'or use Restore purchases after configuring products.',
      );
    }

    final purchaseParam = PurchaseParam(productDetails: p);
    // Non-consumable: false on Android for non-consumables in this API shape.
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await init();
    await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[billing] purchase error: ${purchase.error}');
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final templateId = _templateIdFromProductId(purchase.productID);
        if (templateId != null) {
          await TemplateEntitlementsStore.instance.grantFromVerifiedPurchase(templateId);
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    }
  }

  String? _templateIdFromProductId(String productId) {
    const prefix = 'template_';
    if (!productId.startsWith(prefix)) return null;
    final tail = productId.substring(prefix.length);
    return tail;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
