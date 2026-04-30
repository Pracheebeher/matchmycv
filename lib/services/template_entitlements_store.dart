import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which premium templates are unlocked on this device.
///
/// Next step (recommended): verify purchases on a backend and merge server truth.
class TemplateEntitlementsStore extends ChangeNotifier {
  TemplateEntitlementsStore._();
  static final TemplateEntitlementsStore instance = TemplateEntitlementsStore._();

  static const _prefsKey = 'unlocked_template_ids_v1';

  final Set<String> _unlocked = <String>{};
  bool _ready = false;
  bool get isReady => _ready;

  Set<String> get unlockedIds => Set.unmodifiable(_unlocked);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
    _unlocked
      ..clear()
      ..addAll(raw);
    _ready = true;
    notifyListeners();
  }

  bool isUnlocked(String templateId) => _unlocked.contains(templateId);

  /// Used for local testing / emergency unlock if billing isn't configured yet.
  Future<void> debugUnlock(String templateId) async {
    if (templateId.isEmpty) return;
    _unlocked.add(templateId);
    await _persist();
    notifyListeners();
  }

  Future<void> grantFromVerifiedPurchase(String templateId) async {
    if (templateId.isEmpty) return;
    _unlocked.add(templateId);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _unlocked.toList()..sort());
  }
}
