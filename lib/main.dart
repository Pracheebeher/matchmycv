import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'models/resume_model.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_home_page.dart';
import 'services/template_billing.dart';
import 'services/template_entitlements_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TemplateEntitlementsStore.instance.init();
  await TemplateBilling.instance.init();
  runApp(MyApp());
}

final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('en'));

/// ISO-style country code for the picker (UI region); not wired into formatting yet.
final ValueNotifier<String> appCountryCode = ValueNotifier('US');

class MyApp extends StatelessWidget {
  final ResumeData data = ResumeData();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        appLocale,
        appCountryCode,
        TemplateEntitlementsStore.instance,
      ]),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: appLocale.value,
          supportedLocales: const [
            Locale('en'),
            Locale('hi'),
            Locale('de'),
            Locale('fr'),
            Locale('es'),
            Locale('it'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            AppLocalizations.delegate,
          ],
          home: MainHomePage(data: data),
        );
      },
    );
  }
}