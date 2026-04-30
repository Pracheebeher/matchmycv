import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    final v = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(v != null, 'AppLocalizations not found in context');
    return v!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('it'),
  ];

  String get _lang => locale.languageCode.toLowerCase();

  // ---- Strings (MainHomePage for now) ----
  String get appTitle => _t(
        en: 'CVentra AI - Resume builder & ATS optimizer',
        hi: 'CVentra AI - रिज़्यूमे बिल्डर और ATS ऑप्टिमाइज़र',
        de: 'CVentra AI – Lebenslauf-Builder & ATS-Optimierer',
        fr: 'CVentra AI – Créateur de CV & Optimiseur ATS',
        es: 'CVentra AI – Creador de CV y optimizador ATS',
        it: 'CVentra AI – Creatore CV e ottimizzatore ATS',
      );

  String get appSubtitle => _t(
        en: 'Build, optimize, and get shortlisted faster.',
        hi: 'बनाएँ, ऑप्टिमाइज़ करें और तेज़ी से शॉर्टलिस्ट हों।',
        de: 'Erstellen, optimieren und schneller in die Vorauswahl kommen.',
        fr: 'Créez, optimisez et soyez présélectionné plus vite.',
        es: 'Crea, optimiza y consigue preselecciones más rápido.',
        it: 'Crea, ottimizza e fatti selezionare più velocemente.',
      );

  String get heroTitle => _t(
        en: 'Upgrade your career in minutes.',
        hi: 'मिनटों में अपने करियर को अपग्रेड करें।',
        de: 'Bringe deine Karriere in Minuten auf das nächste Level.',
        fr: 'Améliorez votre carrière en quelques minutes.',
        es: 'Mejora tu carrera en minutos.',
        it: 'Potenzia la tua carriera in pochi minuti.',
      );

  String get ctaResumeTitle => _t(
        en: 'Design My Resume',
        hi: 'मेरा रिज़्यूमे बनाएं',
        de: 'Meinen Lebenslauf erstellen',
        fr: 'Créer mon CV',
        es: 'Diseñar mi CV',
        it: 'Crea il mio CV',
      );

  String get ctaResumeSubtitle => _t(
        en: 'Build a professional resume with templates',
        hi: 'टेम्पलेट्स के साथ प्रोफेशनल रिज़्यूमे बनाएं',
        de: 'Erstelle einen professionellen Lebenslauf mit Vorlagen',
        fr: 'Créez un CV professionnel avec des modèles',
        es: 'Crea un CV profesional con plantillas',
        it: 'Crea un CV professionale con modelli',
      );

  String get ctaCoverTitle => _t(
        en: 'Craft My Cover Letter',
        hi: 'कवर लेटर तैयार करें',
        de: 'Mein Anschreiben erstellen',
        fr: 'Rédiger ma lettre',
        es: 'Crear mi carta',
        it: 'Crea la mia lettera',
      );

  String get ctaCoverSubtitle => _t(
        en: 'Generate a tailored letter instantly',
        hi: 'तुरंत एक टेलर्ड लेटर बनाएं',
        de: 'Sofort ein passendes Anschreiben generieren',
        fr: 'Générez instantanément une lettre adaptée',
        es: 'Genera al instante una carta personalizada',
        it: 'Genera subito una lettera su misura',
      );

  String get ctaAtsTitle => _t(
        en: 'ATS Resume Check',
        hi: 'ATS रिज़्यूमे चेक',
        de: 'ATS-Lebenslauf-Check',
        fr: 'Vérification ATS du CV',
        es: 'Revisión ATS del CV',
        it: 'Controllo ATS del CV',
      );

  String get ctaAtsSubtitle => _t(
        en: 'Score, analyze, and improve your resume',
        hi: 'स्कोर करें, विश्लेषण करें और रिज़्यूमे सुधारें',
        de: 'Bewerten, analysieren und deinen Lebenslauf verbessern',
        fr: 'Notez, analysez et améliorez votre CV',
        es: 'Puntúa, analiza y mejora tu CV',
        it: 'Valuta, analizza e migliora il tuo CV',
      );

  String get countryLanguageTitle => _t(
        en: 'Country & language',
        hi: 'देश और भाषा',
        de: 'Land & Sprache',
        fr: 'Pays et langue',
        es: 'País e idioma',
        it: 'Paese e lingua',
      );

  String get sheetTitle => countryLanguageTitle;
  String get sheetCountryLabel => _t(
        en: 'Country',
        hi: 'देश',
        de: 'Land',
        fr: 'Pays',
        es: 'País',
        it: 'Paese',
      );

  String get sheetLanguageLabel => _t(
        en: 'Language',
        hi: 'भाषा',
        de: 'Sprache',
        fr: 'Langue',
        es: 'Idioma',
        it: 'Lingua',
      );

  String get sheetDone => _t(
        en: 'Done',
        hi: 'हो गया',
        de: 'Fertig',
        fr: 'Terminé',
        es: 'Listo',
        it: 'Fatto',
      );

  // ---- Template selection ----
  String get chooseTemplate => _t(
        en: 'Choose template',
        hi: 'टेम्पलेट चुनें',
        de: 'Vorlage auswählen',
        fr: 'Choisir un modèle',
        es: 'Elegir plantilla',
        it: 'Scegli un modello',
      );

  String get templatesTitle => _t(
        en: 'Templates',
        hi: 'टेम्पलेट्स',
        de: 'Vorlagen',
        fr: 'Modèles',
        es: 'Plantillas',
        it: 'Modelli',
      );

  String templatesCountLine(int count) => _t(
        en: '$count styles • Tap to preview',
        hi: '$count स्टाइल्स • प्रीव्यू के लिए टैप करें',
        de: '$count Stile • Tippen zum Anzeigen',
        fr: '$count styles • Appuyez pour prévisualiser',
        es: '$count estilos • Toca para previsualizar',
        it: '$count stili • Tocca per anteprima',
      );

  String get templatePreviewNeedContentTitle => _t(
        en: 'Add resume details first',
        hi: 'पहले रिज़्यूम विवरण जोड़ें',
        de: 'Zuerst Lebenslauf-Angaben eintragen',
        fr: 'Ajoutez d’abord les infos du CV',
        es: 'Añade primero los datos del CV',
        it: 'Aggiungi prima i dati del CV',
      );

  String get templatePreviewNeedContentMessage => _t(
        en:
            'Your resume is still empty. Tap OK to return to the editor — we’ll expand the key sections and highlight where to add details or upload a PDF.',
        hi:
            'आपका रिज़्यूम अभी खाली है। संपादक पर लौटने के लिए OK दबाएँ — हम मुख्य सेक्शन खोलेंगे और हाइलाइट करेंगे जहाँ विवरण या PDF जोड़ें।',
        de:
            'Dein Lebenslauf ist noch leer. Tippe auf OK, um zum Editor zurückzukehren — wir klappen die wichtigen Bereiche auf und markieren, wo du etwas eintragen oder eine PDF hochladen kannst.',
        fr:
            'Votre CV est encore vide. Appuyez sur OK pour revenir à l’éditeur — nous ouvrirons les sections clés et indiquerons où ajouter des infos ou importer un PDF.',
        es:
            'Tu CV sigue vacío. Pulsa OK para volver al editor: abriremos las secciones clave y resaltaremos dónde añadir datos o subir un PDF.',
        it:
            'Il CV è ancora vuoto. Tocca OK per tornare all’editor: apriremo le sezioni principali ed evidenzieremo dove aggiungere contenuti o caricare un PDF.',
      );

  String get templatePreviewNeedContentOk => _t(
        en: 'OK',
        hi: 'ठीक है',
        de: 'OK',
        fr: 'OK',
        es: 'OK',
        it: 'OK',
      );

  String get premiumLook => _t(
        en: 'Premium look',
        hi: 'प्रीमियम लुक',
        de: 'Premium-Look',
        fr: 'Style premium',
        es: 'Aspecto premium',
        it: 'Stile premium',
      );

  // ---- Industry filters ----
  String get industryAll => _t(
        en: 'All',
        hi: 'सभी',
        de: 'Alle',
        fr: 'Tous',
        es: 'Todos',
        it: 'Tutti',
      );

  String get industryIT => _t(
        en: 'IT',
        hi: 'आईटी',
        de: 'IT',
        fr: 'Informatique',
        es: 'TI',
        it: 'IT',
      );

  String get industryFinance => _t(
        en: 'Finance',
        hi: 'वित्त',
        de: 'Finanzen',
        fr: 'Finance',
        es: 'Finanzas',
        it: 'Finanza',
      );

  String get industryTeacher => _t(
        en: 'Teacher',
        hi: 'शिक्षक',
        de: 'Lehrer',
        fr: 'Enseignant',
        es: 'Docente',
        it: 'Insegnante',
      );

  String get industryInfluencer => _t(
        en: 'Influencer',
        hi: 'इन्फ्लुएंसर',
        de: 'Influencer',
        fr: 'Influenceur',
        es: 'Influencer',
        it: 'Influencer',
      );

  String get industryCreative => _t(
        en: 'Creative',
        hi: 'क्रिएटिव',
        de: 'Kreativ',
        fr: 'Créatif',
        es: 'Creativo',
        it: 'Creativo',
      );

  String get tapToPreview => _t(
        en: 'Tap to preview',
        hi: 'प्रीव्यू के लिए टैप करें',
        de: 'Tippen zum Anzeigen',
        fr: 'Appuyez pour prévisualiser',
        es: 'Toca para previsualizar',
        it: 'Tocca per anteprima',
      );

  String get premiumTemplateTitle => _t(
        en: 'Premium Template',
        hi: 'प्रीमियम टेम्पलेट',
        de: 'Premium-Vorlage',
        fr: 'Modèle premium',
        es: 'Plantilla premium',
        it: 'Modello premium',
      );

  String unlockTemplateFor(String price) => _t(
        en: 'Unlock this template for $price',
        hi: 'इस टेम्पलेट को $price में अनलॉक करें',
        de: 'Diese Vorlage für $price freischalten',
        fr: 'Débloquez ce modèle pour $price',
        es: 'Desbloquea esta plantilla por $price',
        it: 'Sblocca questo modello per $price',
      );

  String get cancel => _t(
        en: 'Cancel',
        hi: 'रद्द करें',
        de: 'Abbrechen',
        fr: 'Annuler',
        es: 'Cancelar',
        it: 'Annulla',
      );

  String get buy => _t(
        en: 'Buy',
        hi: 'खरीदें',
        de: 'Kaufen',
        fr: 'Acheter',
        es: 'Comprar',
        it: 'Acquista',
      );

  String get paymentComingSoon => _t(
        en: 'Payment flow coming soon',
        hi: 'पेमेंट जल्द आ रहा है',
        de: 'Zahlung folgt in Kürze',
        fr: 'Paiement bientôt disponible',
        es: 'Pago disponible pronto',
        it: 'Pagamento in arrivo',
      );

  // ---- Template paywall (Play Billing) ----
  String get templatePaywallTitle => _t(
        en: 'Unlock premium template',
        hi: 'प्रीमियम टेम्पलेट अनलॉक करें',
        de: 'Premium-Vorlage freischalten',
        fr: 'Débloquer le modèle premium',
        es: 'Desbloquear plantilla premium',
        it: 'Sblocca modello premium',
      );

  String templatePaywallPriceHint(String shownPrice, String countryCode) => _t(
        en: 'Shown price for your selected country ($countryCode): $shownPrice',
        hi: 'आपके चुने देश ($countryCode) के लिए दिखाई गई कीमत: $shownPrice',
        de: 'Angezeigter Preis für dein Land ($countryCode): $shownPrice',
        fr: 'Prix affiché pour le pays sélectionné ($countryCode) : $shownPrice',
        es: 'Precio mostrado para tu país ($countryCode): $shownPrice',
        it: 'Prezzo mostrato per il paese ($countryCode): $shownPrice',
      );

  String templatePaywallPlayPrice(String playPrice) => _t(
        en: 'Google Play price: $playPrice',
        hi: 'Google Play कीमत: $playPrice',
        de: 'Google-Play-Preis: $playPrice',
        fr: 'Prix Google Play : $playPrice',
        es: 'Precio en Google Play: $playPrice',
        it: 'Prezzo Google Play: $playPrice',
      );

  String get templatePaywallBillingNote => _t(
        en: 'You will complete payment in Google Play using the payment methods available for your account and region.',
        hi: 'आप अपने खाते और क्षेत्र के लिए उपलब्ध तरीकों से Google Play में भुगतान पूरा करेंगे।',
        de: 'Die Zahlung erfolgt in Google Play mit den für dein Konto/Region verfügbaren Zahlungsmethoden.',
        fr: 'Le paiement se fait dans Google Play avec les moyens disponibles pour votre compte et région.',
        es: 'Completarás el pago en Google Play con los métodos disponibles para tu cuenta y región.',
        it: 'Completi il pagamento in Google Play con i metodi disponibili per account e regione.',
      );

  String get restorePurchases => _t(
        en: 'Restore purchases',
        hi: 'खरीदारी पुनर्स्थापित करें',
        de: 'Käufe wiederherstellen',
        fr: 'Restaurer les achats',
        es: 'Restaurar compras',
        it: 'Ripristina acquisti',
      );

  String get purchaseStarted => _t(
        en: 'Purchase started — follow Google Play prompts',
        hi: 'खरीदारी शुरू — Google Play निर्देशों का पालन करें',
        de: 'Kauf gestartet — folge den Google-Play-Hinweisen',
        fr: 'Achat démarré — suivez les instructions Google Play',
        es: 'Compra iniciada — sigue las indicaciones de Google Play',
        it: 'Acquisto avviato — segui i prompt di Google Play',
      );

  String get restoreStarted => _t(
        en: 'Restoring purchases…',
        hi: 'खरीदारी रिस्टोर हो रही है…',
        de: 'Käufe werden wiederhergestellt…',
        fr: 'Restauration des achats…',
        es: 'Restaurando compras…',
        it: 'Ripristino acquisti…',
      );

  String get debugUnlockTemplate => _t(
        en: 'Debug: unlock template',
        hi: 'डिबग: टेम्पलेट अनलॉक',
        de: 'Debug: Vorlage freischalten',
        fr: 'Debug : débloquer le modèle',
        es: 'Depuración: desbloquear plantilla',
        it: 'Debug: sblocca modello',
      );

  String get debugUnlockedTemplate => _t(
        en: 'Debug unlock applied',
        hi: 'डिबग अनलॉक लागू',
        de: 'Debug-Freischaltung angewendet',
        fr: 'Déblocage debug appliqué',
        es: 'Desbloqueo de depuración aplicado',
        it: 'Sblocco debug applicato',
      );

  String playProductNotConfigured(String productId) => _t(
        en: 'Payment isn’t configured yet for this template (missing Play product: $productId).',
        hi: 'इस टेम्पलेट के लिए भुगतान अभी कॉन्फ़िगर नहीं है (Play प्रोडक्ट नहीं मिला: $productId)।',
        de: 'Zahlung ist für diese Vorlage noch nicht konfiguriert (fehlendes Play-Produkt: $productId).',
        fr: 'Le paiement n’est pas encore configuré pour ce modèle (produit Play manquant : $productId).',
        es: 'El pago aún no está configurado para esta plantilla (falta el producto de Play: $productId).',
        it: 'Pagamento non ancora configurato per questo modello (prodotto Play mancante: $productId).',
      );

  // ---- Shared chrome (other pages) ----
  String get buildResumeTitle => _t(
        en: 'Build Resume',
        hi: 'रिज़्यूमे बनाएं',
        de: 'Lebenslauf erstellen',
        fr: 'Créer un CV',
        es: 'Crear CV',
        it: 'Crea CV',
      );

  String get resumePreviewEditResume => _t(
        en: 'Edit resume',
        hi: 'रिज़्यूमे संपादित करें',
        de: 'Lebenslauf bearbeiten',
        fr: 'Modifier le CV',
        es: 'Editar currículum',
        it: 'Modifica CV',
      );

  String get summarySuggestionAdded => _t(
        en: 'Suggested summary added to your summary.',
        hi: 'सुझाया गया सारांश आपके सारांश में जोड़ा गया।',
        de: 'Vorschlag für die Zusammenfassung wurde hinzugefügt.',
        fr: 'Le résumé suggéré a été ajouté à votre texte.',
        es: 'Se añadió el resumen sugerido a tu resumen.',
        it: 'Il riassunto suggerito è stato aggiunto al tuo testo.',
      );

  String get resumePreviewTitle => _t(
        en: 'Preview',
        hi: 'पूर्वावलोकन',
        de: 'Vorschau',
        fr: 'Aperçu',
        es: 'Vista previa',
        it: 'Anteprima',
      );

  String get resumePreviewTailorActionTitle => _t(
        en: 'Tailor to job',
        hi: 'नौकरी के अनुसार बनाएं',
        de: 'Auf Stelle anpassen',
        fr: 'Adapter au poste',
        es: 'Adaptar al empleo',
        it: 'Adatta all’offerta',
      );

  String get resumePreviewTailorActionSubtitle => _t(
        en: 'Add a job description · AI aligns your resume',
        hi: 'जॉब डिस्क्रिप्शन जोड़ें · AI रिज़्यूमे मिलाएगा',
        de: 'Stellenausschreibung · KI passt den Lebenslauf an',
        fr: 'Description du poste · l’IA aligne votre CV',
        es: 'Descripción del puesto · la IA adapta tu CV',
        it: 'Descrizione lavoro · l’IA allinea il CV',
      );

  String get resumePreviewDownloadActionTitle => _t(
        en: 'Download PDF',
        hi: 'PDF डाउनलोड',
        de: 'PDF herunterladen',
        fr: 'Télécharger le PDF',
        es: 'Descargar PDF',
        it: 'Scarica PDF',
      );

  String get resumePreviewDownloadActionSubtitle => _t(
        en: 'Save a printable resume file',
        hi: 'प्रिंट करने योग्य फ़ाइल सेव करें',
        de: 'Druckbare Datei speichern',
        fr: 'Enregistrer un CV imprimable',
        es: 'Guardar CV para imprimir',
        it: 'Salva CV stampabile',
      );

  String get resumePreviewPdfPreparing => _t(
        en: 'Preparing PDF…',
        hi: 'PDF तैयार हो रहा है…',
        de: 'PDF wird erstellt…',
        fr: 'Préparation du PDF…',
        es: 'Preparando PDF…',
        it: 'Preparazione PDF…',
      );

  /// One-line hint under preview PDF actions (narrow layout).
  String get resumePreviewPdfDockHint => _t(
        en: 'Tip: the share sheet opens next — choose Save to Files, Downloads, or Drive.',
        hi: 'टिप: अगले शेयर शीट में Files, Downloads या Drive चुनें।',
        de: 'Tipp: Im Teilen-Dialog „In Dateien sichern“, Downloads oder Drive wählen.',
        fr: 'Astuce : dans Partager, choisissez Fichiers, Téléchargements ou Drive.',
        es: 'Consejo: en compartir, elige Archivos, Descargas o Drive.',
        it: 'Suggerimento: in Condividi scegli File, Download o Drive.',
      );

  /// After PDF export opens the system share sheet (Save to Files / Downloads).
  String get resumePdfExportShareHint => _t(
        en:
            'Your PDF is ready. In the share sheet, pick Save to Files, Downloads, or another folder to keep it on this device.',
        hi:
            'आपका PDF तैयार है। शेयर शीट में “Save to Files” या डिवाइस पर किसी फ़ोल्डर में सेव करें।',
        de:
            'PDF ist fertig. Wähle im Teilen-Dialog „In Dateien sichern“, „Downloads“ o. Ä., um die Datei auf dem Gerät zu behalten.',
        fr:
            'Votre PDF est prêt. Dans le partage, choisissez Enregistrer dans Fichiers, Téléchargements ou un dossier pour le garder sur l’appareil.',
        es:
            'Tu PDF está listo. En la hoja de compartir, elige Guardar en Archivos, Descargas u otra carpeta en el dispositivo.',
        it:
            'Il PDF è pronto. Nel foglio Condividi scegli Salva in File, Download o un’altra cartella sul dispositivo.',
      );

  /// Shown after a resume/cover PDF download or share-to-save completes.
  String get successfullyDownloaded => _t(
        en: 'Successfully downloaded.',
        hi: 'सफलतापूर्वक डाउनलोड हो गया।',
        de: 'Erfolgreich heruntergeladen.',
        fr: 'Téléchargement réussi.',
        es: 'Descargado correctamente.',
        it: 'Download completato.',
      );

  String get downloadCouldNotComplete => _t(
        en: 'Download could not complete. Please try again.',
        hi: 'डाउनलोड पूरा नहीं हो सका। कृपया फिर कोशिश करें।',
        de: 'Download fehlgeschlagen. Bitte erneut versuchen.',
        fr: 'Le téléchargement a échoué. Réessayez.',
        es: 'No se pudo completar la descarga. Inténtalo de nuevo.',
        it: 'Download non riuscito. Riprova.',
      );

  String get shareCouldNotComplete => _t(
        en: 'Share could not complete. Please try again.',
        hi: 'शेयर पूरा नहीं हो सका। कृपया फिर कोशिश करें।',
        de: 'Teilen fehlgeschlagen. Bitte erneut versuchen.',
        fr: 'Le partage a échoué. Réessayez.',
        es: 'No se pudo compartir. Inténtalo de nuevo.',
        it: 'Condivisione non riuscita. Riprova.',
      );

  String get jobDescriptionRequiredTailor => _t(
        en: 'Add a job description to tailor your resume.',
        hi: 'रिज़्यूमे टेलर करने के लिए जॉब डिस्क्रिप्शन जोड़ें।',
        de: 'Füge eine Stellenbeschreibung hinzu, um den Lebenslauf anzupassen.',
        fr: 'Ajoutez une offre d’emploi pour adapter le CV.',
        es: 'Añade la descripción del puesto para adaptar el CV.',
        it: 'Aggiungi una job description per adattare il CV.',
      );

  String get skillsMergedShort => _t(
        en: 'Skills updated.',
        hi: 'स्किल्स अपडेट हो गईं।',
        de: 'Fähigkeiten aktualisiert.',
        fr: 'Compétences mises à jour.',
        es: 'Habilidades actualizadas.',
        it: 'Competenze aggiornate.',
      );

  String get tailoringCouldNotComplete => _t(
        en: 'Could not tailor the resume. Please try again.',
        hi: 'रिज़्यूमे टेलर नहीं हो सका। कृपया फिर कोशिश करें।',
        de: 'Lebenslauf konnte nicht angepasst werden. Bitte erneut versuchen.',
        fr: 'Impossible d’adapter le CV. Réessayez.',
        es: 'No se pudo adaptar el CV. Inténtalo de nuevo.',
        it: 'Impossibile adattare il CV. Riprova.',
      );

  String get coverLetterAiFallbackNotice => _t(
        en: 'AI could not tailor the letter. A template version was used.',
        hi: 'AI लेटर टेलर नहीं कर सका। टेम्पलेट संस्करण उपयोग किया गया।',
        de: 'KI konnte das Anschreiben nicht anpassen. Vorlagenversion genutzt.',
        fr: 'L’IA n’a pas pu adapter la lettre. Version modèle utilisée.',
        es: 'La IA no pudo adaptar la carta. Se usó una plantilla.',
        it: 'L’IA non ha potuto adattare la lettera. Usata versione modello.',
      );

  String get premiumUnlockedShort => _t(
        en: 'Premium unlocked.',
        hi: 'प्रीमियम अनलॉक हो गया।',
        de: 'Premium freigeschaltet.',
        fr: 'Premium débloqué.',
        es: 'Premium desbloqueado.',
        it: 'Premium sbloccato.',
      );

  String get atsCheckerErrorShort => _t(
        en: 'Something went wrong. Please try again.',
        hi: 'कुछ गलत हो गया। कृपया फिर कोशिश करें।',
        de: 'Etwas ist schiefgelaufen. Bitte erneut versuchen.',
        fr: 'Une erreur s’est produite. Réessayez.',
        es: 'Algo salió mal. Inténtalo de nuevo.',
        it: 'Qualcosa è andato storto. Riprova.',
      );

  String get atsResumeFileMissing => _t(
        en: 'Saved resume file is missing. Please upload again.',
        hi: 'सेव किया रिज़्यूमे फ़ाइल नहीं मिली। कृपया फिर अपलोड करें।',
        de: 'Gespeicherter Lebenslauf fehlt. Bitte erneut hochladen.',
        fr: 'Fichier CV introuvable. Téléversez à nouveau.',
        es: 'Falta el archivo del CV. Súbelo de nuevo.',
        it: 'File del CV mancante. Carica di nuovo.',
      );

  String get atsCouldNotOpenTemplates => _t(
        en: 'Could not open templates. Please try again.',
        hi: 'टेम्पलेट नहीं खुल सके। कृपया फिर कोशिश करें।',
        de: 'Vorlagen konnten nicht geöffnet werden. Bitte erneut versuchen.',
        fr: 'Impossible d’ouvrir les modèles. Réessayez.',
        es: 'No se pudieron abrir las plantillas. Inténtalo de nuevo.',
        it: 'Impossibile aprire i modelli. Riprova.',
      );

  String get pdfOpenFailed => _t(
        en: 'Could not open this PDF.',
        hi: 'यह PDF नहीं खुल सका।',
        de: 'Dieses PDF konnte nicht geöffnet werden.',
        fr: 'Impossible d’ouvrir ce PDF.',
        es: 'No se pudo abrir este PDF.',
        it: 'Impossibile aprire questo PDF.',
      );

  String get resumeTextRequiredShort => _t(
        en: 'Add resume text first.',
        hi: 'पहले रिज़्यूमे टेक्स्ट जोड़ें।',
        de: 'Bitte zuerst Lebenslauftext einfügen.',
        fr: 'Ajoutez d’abord le texte du CV.',
        es: 'Añade primero el texto del CV.',
        it: 'Aggiungi prima il testo del CV.',
      );

  String get enhancementUpdatedShort => _t(
        en: 'Enhancement updated.',
        hi: 'एन्हांसमेंट अपडेट हो गया।',
        de: 'Optimierung aktualisiert.',
        fr: 'Version améliorée mise à jour.',
        es: 'Versión mejorada actualizada.',
        it: 'Ottimizzazione aggiornata.',
      );

  String get noPdfAttachedSession => _t(
        en: 'No PDF is attached to this session.',
        hi: 'इस सत्र में कोई PDF जुड़ा नहीं है।',
        de: 'Dieser Sitzung ist kein PDF zugeordnet.',
        fr: 'Aucun PDF n’est associé à cette session.',
        es: 'No hay PDF adjunto a esta sesión.',
        it: 'Nessun PDF associato a questa sessione.',
      );

  String get atsResumeCheckerTitle => _t(
        en: 'ATS Resume Checker',
        hi: 'ATS रिज़्यूमे चेकर',
        de: 'ATS-Lebenslauf-Check',
        fr: 'Vérificateur ATS',
        es: 'Comprobador ATS',
        it: 'Controllo ATS',
      );

  String get atsHeroTitle => _t(
        en: 'Check ATS compatibility',
        hi: 'ATS अनुकूलता जाँचें',
        de: 'ATS-Kompatibilität prüfen',
        fr: 'Vérifier la compatibilité ATS',
        es: 'Comprobar compatibilidad ATS',
        it: 'Verifica compatibilità ATS',
      );

  String get atsHeroSubtitle => _t(
        en: 'Upload your PDF and get a score + fixes you can apply instantly.',
        hi: 'PDF अपलोड करें और स्कोर + सुधार तुरंत पाएं।',
        de: 'PDF hochladen und sofort Score + Verbesserungen erhalten.',
        fr: 'Téléversez votre PDF et obtenez un score + des corrections.',
        es: 'Sube tu PDF y obtén puntuación y mejoras al instante.',
        it: 'Carica il PDF e ottieni punteggio e migliorie subito.',
      );

  String get resumeEnhancerTitle => _t(
        en: 'Resume Enhancer',
        hi: 'रिज़्यूमे एन्हांसर',
        de: 'Lebenslauf-Optimierung',
        fr: 'Amélioration du CV',
        es: 'Mejorador de CV',
        it: 'Migliora CV',
      );

  String get dragResumeBuilderTitle => _t(
        en: 'Drag Resume Builder',
        hi: 'ड्रैग रिज़्यूमे बिल्डर',
        de: 'Drag-and-drop Lebenslauf',
        fr: 'CV par glisser-déposer',
        es: 'CV por arrastre',
        it: 'CV drag & drop',
      );

  String get personalInfoTitle => _t(
        en: 'Personal Info',
        hi: 'व्यक्तिगत जानकारी',
        de: 'Persönliche Infos',
        fr: 'Infos personnelles',
        es: 'Información personal',
        it: 'Dati personali',
      );

  // ---- Home builder form ----
  String get nameLabel => _t(
        en: 'Name',
        hi: 'नाम',
        de: 'Name',
        fr: 'Nom',
        es: 'Nombre',
        it: 'Nome',
      );

  String get emailLabel => _t(
        en: 'Email',
        hi: 'ईमेल',
        de: 'E-Mail',
        fr: 'E-mail',
        es: 'Correo',
        it: 'Email',
      );

  String get phoneLabel => _t(
        en: 'Phone',
        hi: 'फ़ोन',
        de: 'Telefon',
        fr: 'Téléphone',
        es: 'Teléfono',
        it: 'Telefono',
      );

  String get cityLabel => _t(
        en: 'City',
        hi: 'शहर',
        de: 'Stadt',
        fr: 'Ville',
        es: 'Ciudad',
        it: 'Città',
      );

  String get countryLabel => _t(
        en: 'Country',
        hi: 'देश',
        de: 'Land',
        fr: 'Pays',
        es: 'País',
        it: 'Paese',
      );

  String get uploadPhoto => _t(
        en: 'Upload Photo',
        hi: 'फोटो अपलोड करें',
        de: 'Foto hochladen',
        fr: 'Téléverser une photo',
        es: 'Subir foto',
        it: 'Carica foto',
      );

  String get summaryTitle => _t(
        en: 'Summary',
        hi: 'सारांश',
        de: 'Zusammenfassung',
        fr: 'Résumé',
        es: 'Resumen',
        it: 'Riepilogo',
      );

  String get writeSummaryHint => _t(
        en: 'Write your summary...',
        hi: 'अपना सारांश लिखें...',
        de: 'Schreibe deine Zusammenfassung...',
        fr: 'Écrivez votre résumé...',
        es: 'Escribe tu resumen...',
        it: 'Scrivi il tuo riepilogo...',
      );

  String get targetJobSectionTitle => _t(
        en: 'Target job (optional)',
        hi: 'लक्ष्य नौकरी (वैकल्पिक)',
        de: 'Zielstelle (optional)',
        fr: 'Poste visé (facultatif)',
        es: 'Empleo objetivo (opcional)',
        it: 'Ruolo di interesse (facoltativo)',
      );

  String get targetJobFieldHint => _t(
        en: 'Paste the job posting you are applying for — shown with your summary and experience so your resume reads role-ready.',
        hi: 'जिस नौकरी के लिए आप आवेदन कर रहे हैं, उसका विवरण चिपकाएँ — आपके सारांश और अनुभव के साथ दिखाया जाएगा।',
        de: 'Stellenanzeige einfügen — wird bei Profil und Erfahrung angezeigt, damit der Lebenslauf zur Rolle passt.',
        fr: 'Collez l’offre visée — affichée avec le résumé et l’expérience pour un CV aligné sur le poste.',
        es: 'Pega la oferta a la que aplicas; se mostrará con el resumen y la experiencia.',
        it: 'Incolla l’annuncio per cui ti candidi; comparirà con riepilogo ed esperienza.',
      );

  String get targetJobBannerCaption => _t(
        en: 'Applying toward this role',
        hi: 'इस भूमिका की ओर आवेदन',
        de: 'Ausrichtung auf diese Stelle',
        fr: 'Candidature pour ce rôle',
        es: 'Enfocado a este puesto',
        it: 'Orientato a questo ruolo',
      );

  String get targetJobShortHint => _t(
        en: 'Paste job title, responsibilities, and requirements…',
        hi: 'नौकरी का शीर्षक, जिम्मेदारियाँ और आवश्यकताएँ चिपकाएँ…',
        de: 'Titel, Aufgaben und Anforderungen einfügen…',
        fr: 'Titre du poste, missions et exigences…',
        es: 'Título, responsabilidades y requisitos…',
        it: 'Titolo, responsabilità e requisiti…',
      );

  String get generate => _t(
        en: 'Generate',
        hi: 'जनरेट करें',
        de: 'Erstellen',
        fr: 'Générer',
        es: 'Generar',
        it: 'Genera',
      );

  String get example => _t(
        en: 'Example',
        hi: 'उदाहरण',
        de: 'Beispiel',
        fr: 'Exemple',
        es: 'Ejemplo',
        it: 'Esempio',
      );

  String get experienceTitle => _t(
        en: 'Experience',
        hi: 'अनुभव',
        de: 'Berufserfahrung',
        fr: 'Expérience',
        es: 'Experiencia',
        it: 'Esperienza',
      );

  String get educationTitle => _t(
        en: 'Education',
        hi: 'शिक्षा',
        de: 'Ausbildung',
        fr: 'Formation',
        es: 'Educación',
        it: 'Istruzione',
      );

  String get skillsTitle => _t(
        en: 'Skills',
        hi: 'कौशल',
        de: 'Fähigkeiten',
        fr: 'Compétences',
        es: 'Habilidades',
        it: 'Competenze',
      );

  String get categoriesTitle => _t(
        en: 'Categories',
        hi: 'श्रेणियाँ',
        de: 'Kategorien',
        fr: 'Catégories',
        es: 'Categorías',
        it: 'Categorie',
      );

  String get categoryLanguages => _t(
        en: 'Languages',
        hi: 'भाषाएँ',
        de: 'Sprachen',
        fr: 'Langues',
        es: 'Idiomas',
        it: 'Lingue',
      );

  String get categoryCourses => _t(
        en: 'Courses',
        hi: 'कोर्स',
        de: 'Kurse',
        fr: 'Cours',
        es: 'Cursos',
        it: 'Corsi',
      );

  String get categoryLinks => _t(
        en: 'Links',
        hi: 'लिंक्स',
        de: 'Links',
        fr: 'Liens',
        es: 'Enlaces',
        it: 'Link',
      );

  String get categoryHobbies => _t(
        en: 'Hobbies',
        hi: 'शौक',
        de: 'Hobbys',
        fr: 'Loisirs',
        es: 'Aficiones',
        it: 'Hobby',
      );

  String get categoryVolunteering => _t(
        en: 'Volunteering',
        hi: 'स्वयंसेवा',
        de: 'Ehrenamt',
        fr: 'Bénévolat',
        es: 'Voluntariado',
        it: 'Volontariato',
      );

  String get categoryReferences => _t(
        en: 'References',
        hi: 'संदर्भ',
        de: 'Referenzen',
        fr: 'Références',
        es: 'Referencias',
        it: 'Referenze',
      );

  String get categoryCertifications => _t(
        en: 'Certifications',
        hi: 'प्रमाणपत्र',
        de: 'Zertifizierungen',
        fr: 'Certifications',
        es: 'Certificaciones',
        it: 'Certificazioni',
      );

  String get categoryAchievements => _t(
        en: 'Achievements',
        hi: 'उपलब्धियाँ',
        de: 'Erfolge',
        fr: 'Réalisations',
        es: 'Logros',
        it: 'Risultati',
      );

  String get addReferenceTitle => _t(
        en: 'Add reference',
        hi: 'संदर्भ जोड़ें',
        de: 'Referenz hinzufügen',
        fr: 'Ajouter une référence',
        es: 'Agregar referencia',
        it: 'Aggiungi referenza',
      );

  String get referenceNameLabel => _t(
        en: 'Name',
        hi: 'नाम',
        de: 'Name',
        fr: 'Nom',
        es: 'Nombre',
        it: 'Nome',
      );

  String get referencePhoneLabel => _t(
        en: 'Phone number',
        hi: 'फ़ोन नंबर',
        de: 'Telefonnummer',
        fr: 'Numéro de téléphone',
        es: 'Teléfono',
        it: 'Telefono',
      );

  String get addCourseTitle => _t(
        en: 'Add course',
        hi: 'कोर्स जोड़ें',
        de: 'Kurs hinzufügen',
        fr: 'Ajouter un cours',
        es: 'Agregar curso',
        it: 'Aggiungi corso',
      );

  String get courseNameLabel => _t(
        en: 'Course name',
        hi: 'कोर्स का नाम',
        de: 'Kursname',
        fr: 'Nom du cours',
        es: 'Nombre del curso',
        it: 'Nome corso',
      );

  String get courseMonthYearHint => _t(
        en: 'Completed (month/year)',
        hi: 'पूरा (माह/वर्ष)',
        de: 'Abgeschlossen (Monat/Jahr)',
        fr: 'Terminé (mois/année)',
        es: 'Completado (mes/año)',
        it: 'Completato (mese/anno)',
      );

  String get addCertificationTitle => _t(
        en: 'Add certification',
        hi: 'प्रमाणपत्र जोड़ें',
        de: 'Zertifizierung hinzufügen',
        fr: 'Ajouter une certification',
        es: 'Agregar certificación',
        it: 'Aggiungi certificazione',
      );

  String get certificationNameLabel => _t(
        en: 'Certification name',
        hi: 'प्रमाणपत्र का नाम',
        de: 'Zertifizierungsname',
        fr: 'Nom de la certification',
        es: 'Nombre de la certificación',
        it: 'Nome certificazione',
      );

  String get certificationMonthYearHint => _t(
        en: 'Issued (month/year)',
        hi: 'जारी (माह/वर्ष)',
        de: 'Ausgestellt (Monat/Jahr)',
        fr: 'Délivré (mois/année)',
        es: 'Emitido (mes/año)',
        it: 'Rilasciato (mese/anno)',
      );

  String get addAchievementTitle => _t(
        en: 'Add achievement',
        hi: 'उपलब्धि जोड़ें',
        de: 'Erfolg hinzufügen',
        fr: 'Ajouter une réalisation',
        es: 'Agregar logro',
        it: 'Aggiungi risultato',
      );

  String get achievementTitleLabel => _t(
        en: 'Achievement or award',
        hi: 'उपलब्धि या पुरस्कार',
        de: 'Erfolg oder Auszeichnung',
        fr: 'Réalisation ou distinction',
        es: 'Logro o premio',
        it: 'Risultato o riconoscimento',
      );

  String get achievementWhereHint => _t(
        en: 'Where (organization, school, event…)',
        hi: 'कहाँ (संस्था, विद्यालय, आयोजन…)',
        de: 'Wo (Organisation, Schule, Veranstaltung …)',
        fr: 'Où (organisation, école, événement…)',
        es: 'Dónde (organización, centro, evento…)',
        it: 'Dove (organizzazione, scuola, evento…)',
      );

  String get achievementWhenHint => _t(
        en: 'When (date or period)',
        hi: 'कब (तारीख या अवधि)',
        de: 'Wann (Datum oder Zeitraum)',
        fr: 'Quand (date ou période)',
        es: 'Cuándo (fecha o periodo)',
        it: 'Quando (data o periodo)',
      );

  String get addLanguageTitle => _t(
        en: 'Add language',
        hi: 'भाषा जोड़ें',
        de: 'Sprache hinzufügen',
        fr: 'Ajouter une langue',
        es: 'Agregar idioma',
        it: 'Aggiungi lingua',
      );

  String get languageNameLabel => _t(
        en: 'Language',
        hi: 'भाषा',
        de: 'Sprache',
        fr: 'Langue',
        es: 'Idioma',
        it: 'Lingua',
      );

  String get languageProficiencyFieldLabel => _t(
        en: 'Proficiency',
        hi: 'प्रवीणता',
        de: 'Niveau',
        fr: 'Niveau',
        es: 'Nivel',
        it: 'Livello',
      );

  /// [code] is one of: native, fluent, professional, intermediate, basic.
  String languageProficiencyLabel(String code) {
    switch (code.toLowerCase()) {
      case 'native':
        return _t(
          en: 'Native',
          hi: 'मातृभाषा',
          de: 'Muttersprache',
          fr: 'Langue maternelle',
          es: 'Nativo',
          it: 'Madrelingua',
        );
      case 'fluent':
        return _t(
          en: 'Fluent',
          hi: 'धाराप्रवाह',
          de: 'Fließend',
          fr: 'Courant',
          es: 'Fluido',
          it: 'Fluente',
        );
      case 'professional':
        return _t(
          en: 'Professional working',
          hi: 'पेशेवर कार्य स्तर',
          de: 'Verhandlungssicher',
          fr: 'Professionnel',
          es: 'Profesional',
          it: 'Professionale',
        );
      case 'intermediate':
        return _t(
          en: 'Intermediate',
          hi: 'मध्यवर्ती',
          de: 'Mittelstufe',
          fr: 'Intermédiaire',
          es: 'Intermedio',
          it: 'Intermedio',
        );
      case 'basic':
        return _t(
          en: 'Basic',
          hi: 'बुनियादी',
          de: 'Grundkenntnisse',
          fr: 'Notions',
          es: 'Básico',
          it: 'Base',
        );
      default:
        return code;
    }
  }

  String addCategoryInlineHint(String categoryTitle) => _t(
        en: 'Add $categoryTitle',
        hi: '$categoryTitle जोड़ें',
        de: '$categoryTitle hinzufügen',
        fr: 'Ajouter $categoryTitle',
        es: 'Agregar $categoryTitle',
        it: 'Aggiungi $categoryTitle',
      );

  String get addSkillHint => _t(
        en: 'Add Skill',
        hi: 'कौशल जोड़ें',
        de: 'Fähigkeit hinzufügen',
        fr: 'Ajouter une compétence',
        es: 'Agregar habilidad',
        it: 'Aggiungi competenza',
      );

  String get addExperience => _t(
        en: 'Add Experience',
        hi: 'अनुभव जोड़ें',
        de: 'Erfahrung hinzufügen',
        fr: 'Ajouter une expérience',
        es: 'Agregar experiencia',
        it: 'Aggiungi esperienza',
      );

  String get addEducation => _t(
        en: 'Add Education',
        hi: 'शिक्षा जोड़ें',
        de: 'Ausbildung hinzufügen',
        fr: 'Ajouter une formation',
        es: 'Agregar educación',
        it: 'Aggiungi istruzione',
      );

  String get uploadResume => _t(
        en: 'Upload\nResume',
        hi: 'रिज़्यूमे\nअपलोड करें',
        de: 'Lebenslauf\nhochladen',
        fr: 'Téléverser\nCV',
        es: 'Subir\nCV',
        it: 'Carica\nCV',
      );

  String get templates => _t(
        en: 'Templates',
        hi: 'टेम्पलेट्स',
        de: 'Vorlagen',
        fr: 'Modèles',
        es: 'Plantillas',
        it: 'Modelli',
      );

  String get saved => _t(
        en: 'Saved',
        hi: 'सेव हो गया',
        de: 'Gespeichert',
        fr: 'Enregistré',
        es: 'Guardado',
        it: 'Salvato',
      );

  String get uploadingResume => _t(
        en: 'Uploading Resume...',
        hi: 'रिज़्यूमे अपलोड हो रहा है...',
        de: 'Lebenslauf wird hochgeladen...',
        fr: 'Téléversement du CV...',
        es: 'Subiendo CV...',
        it: 'Caricamento CV...',
      );

  String get couldNotReadFile => _t(
        en: 'Could not read file',
        hi: 'फ़ाइल पढ़ी नहीं जा सकी',
        de: 'Datei konnte nicht gelesen werden',
        fr: 'Impossible de lire le fichier',
        es: 'No se pudo leer el archivo',
        it: 'Impossibile leggere il file',
      );

  String get couldNotParseResume => _t(
        en: 'Could not parse resume',
        hi: 'रिज़्यूमे पार्स नहीं हो सका',
        de: 'Lebenslauf konnte nicht verarbeitet werden',
        fr: 'Impossible d’analyser le CV',
        es: 'No se pudo analizar el CV',
        it: 'Impossibile analizzare il CV',
      );

  String get resumeImported => _t(
        en: 'Resume imported',
        hi: 'रिज़्यूमे इम्पोर्ट हो गया',
        de: 'Lebenslauf importiert',
        fr: 'CV importé',
        es: 'CV importado',
        it: 'CV importato',
      );

  String get addExperienceTitle => _t(
        en: 'Add Experience',
        hi: 'अनुभव जोड़ें',
        de: 'Erfahrung hinzufügen',
        fr: 'Ajouter une expérience',
        es: 'Agregar experiencia',
        it: 'Aggiungi esperienza',
      );

  String get editExperienceTitle => _t(
        en: 'Edit Experience',
        hi: 'अनुभव संपादित करें',
        de: 'Erfahrung bearbeiten',
        fr: 'Modifier l’expérience',
        es: 'Editar experiencia',
        it: 'Modifica esperienza',
      );

  String get removeExperienceTitle => _t(
        en: 'Remove experience?',
        hi: 'अनुभव हटाएं?',
        de: 'Erfahrung entfernen?',
        fr: 'Supprimer l’expérience ?',
        es: '¿Eliminar experiencia?',
        it: 'Rimuovere l’esperienza?',
      );

  String get removeExperienceBody => _t(
        en: 'This work history entry will be deleted.',
        hi: 'यह कार्य अनुभव हटा दिया जाएगा।',
        de: 'Dieser Berufserfahrungseintrag wird gelöscht.',
        fr: 'Cette expérience professionnelle sera supprimée.',
        es: 'Se eliminará esta experiencia laboral.',
        it: 'Questa esperienza lavorativa verrà eliminata.',
      );

  String get removeLabel => _t(
        en: 'Remove',
        hi: 'हटाएं',
        de: 'Entfernen',
        fr: 'Supprimer',
        es: 'Eliminar',
        it: 'Rimuovi',
      );

  String get addEducationTitle => _t(
        en: 'Add Education',
        hi: 'शिक्षा जोड़ें',
        de: 'Ausbildung hinzufügen',
        fr: 'Ajouter une formation',
        es: 'Agregar educación',
        it: 'Aggiungi istruzione',
      );

  String get editEducationTitle => _t(
        en: 'Edit Education',
        hi: 'शिक्षा संपादित करें',
        de: 'Ausbildung bearbeiten',
        fr: 'Modifier la formation',
        es: 'Editar educación',
        it: 'Modifica istruzione',
      );

  String get removeEducationTitle => _t(
        en: 'Remove education?',
        hi: 'शिक्षा हटाएं?',
        de: 'Ausbildung entfernen?',
        fr: 'Supprimer la formation ?',
        es: '¿Eliminar educación?',
        it: 'Rimuovere l’istruzione?',
      );

  String get removeEducationBody => _t(
        en: 'This education entry will be deleted.',
        hi: 'यह शिक्षा प्रविष्टि हटा दी जाएगी।',
        de: 'Dieser Ausbildungseintrag wird gelöscht.',
        fr: 'Cette formation sera supprimée.',
        es: 'Se eliminará esta entrada de educación.',
        it: 'Questa voce di istruzione verrà eliminata.',
      );

  String addToCategoryTitle(String key) => _t(
        en: 'Add to $key',
        hi: '$key में जोड़ें',
        de: 'Zu $key hinzufügen',
        fr: 'Ajouter à $key',
        es: 'Agregar a $key',
        it: 'Aggiungi a $key',
      );

  String enterCategoryItemHint(String key) => _t(
        en: 'Enter $key',
        hi: '$key दर्ज करें',
        de: '$key eingeben',
        fr: 'Saisir $key',
        es: 'Ingresar $key',
        it: 'Inserisci $key',
      );

  String get roleLabel => _t(
        en: 'Role',
        hi: 'भूमिका',
        de: 'Rolle',
        fr: 'Poste',
        es: 'Rol',
        it: 'Ruolo',
      );

  String get companyLabel => _t(
        en: 'Company',
        hi: 'कंपनी',
        de: 'Unternehmen',
        fr: 'Entreprise',
        es: 'Empresa',
        it: 'Azienda',
      );

  String get startMonthYearHint => _t(
        en: 'Start date',
        hi: 'आरंभ तिथि',
        de: 'Startdatum',
        fr: 'Date de début',
        es: 'Fecha de inicio',
        it: 'Data di inizio',
      );

  String get endMonthYearHint => _t(
        en: 'End date',
        hi: 'समाप्ति तिथि',
        de: 'Enddatum',
        fr: 'Date de fin',
        es: 'Fecha de fin',
        it: 'Data di fine',
      );

  String get present => _t(
        en: 'Present',
        hi: 'वर्तमान',
        de: 'Heute',
        fr: 'Actuel',
        es: 'Actual',
        it: 'Attuale',
      );

  String get durationOptionalLabel => _t(
        en: 'Duration (optional)',
        hi: 'अवधि (वैकल्पिक)',
        de: 'Dauer (optional)',
        fr: 'Durée (optionnel)',
        es: 'Duración (opcional)',
        it: 'Durata (opzionale)',
      );

  String get bulletPointsHint => _t(
        en: 'Bullet points (one per line)',
        hi: 'बुलेट पॉइंट्स (प्रति लाइन एक)',
        de: 'Aufzählungspunkte (einer pro Zeile)',
        fr: 'Puces (une par ligne)',
        es: 'Viñetas (una por línea)',
        it: 'Punti elenco (uno per riga)',
      );

  String get degreeLabel => _t(
        en: 'Degree',
        hi: 'डिग्री',
        de: 'Abschluss',
        fr: 'Diplôme',
        es: 'Título',
        it: 'Titolo',
      );

  String get institutionLabel => _t(
        en: 'Institution',
        hi: 'संस्थान',
        de: 'Institution',
        fr: 'Établissement',
        es: 'Institución',
        it: 'Istituto',
      );

  String get graduationMonthYearHint => _t(
        en: 'Graduation (month/year)',
        hi: 'स्नातक (माह/वर्ष)',
        de: 'Abschluss (Monat/Jahr)',
        fr: 'Diplôme (mois/année)',
        es: 'Graduación (mes/año)',
        it: 'Laurea (mese/anno)',
      );

  String get editTextTitle => _t(
        en: 'Edit Text',
        hi: 'टेक्स्ट संपादित करें',
        de: 'Text bearbeiten',
        fr: 'Modifier le texte',
        es: 'Editar texto',
        it: 'Modifica testo',
      );

  String pageIndicator(int page, int total) => _t(
        en: 'Page $page of $total',
        hi: 'पृष्ठ $page / $total',
        de: 'Seite $page von $total',
        fr: 'Page $page sur $total',
        es: 'Página $page de $total',
        it: 'Pagina $page di $total',
      );

  // ---- Cover letter ----
  String get aiCoverLetterTitle => _t(
        en: 'AI Cover Letter',
        hi: 'AI कवर लेटर',
        de: 'KI-Anschreiben',
        fr: 'Lettre IA',
        es: 'Carta con IA',
        it: 'Lettera IA',
      );

  String get coverLetterSubtitle => _t(
        en: 'Generate a professional cover letter instantly',
        hi: 'तुरंत एक प्रोफेशनल कवर लेटर बनाएं',
        de: 'Erstelle sofort ein professionelles Anschreiben',
        fr: 'Générez instantanément une lettre professionnelle',
        es: 'Genera al instante una carta profesional',
        it: 'Genera subito una lettera professionale',
      );

  String get tellUsAboutJob => _t(
        en: 'Tell us about the job',
        hi: 'नौकरी के बारे में बताएं',
        de: 'Erzähle uns von der Stelle',
        fr: 'Parlez-nous du poste',
        es: 'Cuéntanos sobre el puesto',
        it: 'Parlaci del lavoro',
      );

  String get tailoredCoverLetterHint => _t(
        en: 'We’ll craft a cover letter tailored for this role.',
        hi: 'हम इस भूमिका के लिए एक टेलर्ड कवर लेटर तैयार करेंगे।',
        de: 'Wir erstellen ein passgenaues Anschreiben für diese Rolle.',
        fr: 'Nous créerons une lettre adaptée à ce poste.',
        es: 'Crearemos una carta adaptada a este puesto.',
        it: 'Creeremo una lettera su misura per questo ruolo.',
      );

  String get companyName => _t(
        en: 'Company Name',
        hi: 'कंपनी का नाम',
        de: 'Unternehmensname',
        fr: "Nom de l'entreprise",
        es: 'Nombre de la empresa',
        it: 'Nome azienda',
      );

  String get jobPosition => _t(
        en: 'Job Position',
        hi: 'जॉब पोज़िशन',
        de: 'Position',
        fr: 'Poste',
        es: 'Puesto',
        it: 'Posizione',
      );

  String get yourSkillsComma => _t(
        en: 'Your Skills (comma separated)',
        hi: 'आपके कौशल (कॉमा से अलग करें)',
        de: 'Deine Skills (durch Kommas getrennt)',
        fr: 'Vos compétences (séparées par des virgules)',
        es: 'Tus habilidades (separadas por comas)',
        it: 'Le tue competenze (separate da virgole)',
      );

  String get generating => _t(
        en: 'Generating…',
        hi: 'जेनरेट हो रहा है…',
        de: 'Wird erstellt…',
        fr: 'Génération…',
        es: 'Generando…',
        it: 'Generazione…',
      );

  String get generateWithAi => _t(
        en: 'Generate with AI',
        hi: 'AI से जेनरेट करें',
        de: 'Mit KI erstellen',
        fr: 'Générer avec IA',
        es: 'Generar con IA',
        it: 'Genera con IA',
      );

  String get coverLetterFormIncompleteMessage => _t(
        en:
            'Please add your name, company, job title, and skills before generating.',
        hi:
            'जेनरेट करने से पहले अपना नाम, कंपनी, जॉब टाइटल और कौशल भरें।',
        de:
            'Bitte Name, Unternehmen, Stellentitel und Skills ausfüllen, bevor du generierst.',
        fr:
            'Renseignez votre nom, l’entreprise, l’intitulé du poste et vos compétences avant de générer.',
        es:
            'Completa tu nombre, empresa, puesto y habilidades antes de generar.',
        it:
            'Inserisci nome, azienda, titolo del ruolo e competenze prima di generare.',
      );

  String get coverLetterTitle => _t(
        en: 'Cover letter',
        hi: 'कवर लेटर',
        de: 'Anschreiben',
        fr: 'Lettre',
        es: 'Carta',
        it: 'Lettera',
      );

  String get saveCoverLetter => _t(
        en: 'Save cover letter',
        hi: 'कवर लेटर सेव करें',
        de: 'Anschreiben speichern',
        fr: 'Enregistrer la lettre',
        es: 'Guardar carta',
        it: 'Salva lettera',
      );

  String get fileNameHint => _t(
        en: 'File name (without .pdf)',
        hi: 'फ़ाइल नाम (.pdf के बिना)',
        de: 'Dateiname (ohne .pdf)',
        fr: 'Nom de fichier (sans .pdf)',
        es: 'Nombre de archivo (sin .pdf)',
        it: 'Nome file (senza .pdf)',
      );

  String get save => _t(
        en: 'Save',
        hi: 'सेव',
        de: 'Speichern',
        fr: 'Enregistrer',
        es: 'Guardar',
        it: 'Salva',
      );

  String get copiedToClipboard => _t(
        en: 'Copied to clipboard',
        hi: 'क्लिपबोर्ड पर कॉपी हो गया',
        de: 'In die Zwischenablage kopiert',
        fr: 'Copié dans le presse-papiers',
        es: 'Copiado al portapapeles',
        it: 'Copiato negli appunti',
      );

  String savedAsPdf(String fileName) => _t(
        en: 'Saved as $fileName.pdf',
        hi: '$fileName.pdf के रूप में सेव हुआ',
        de: 'Gespeichert als $fileName.pdf',
        fr: 'Enregistré sous $fileName.pdf',
        es: 'Guardado como $fileName.pdf',
        it: 'Salvato come $fileName.pdf',
      );

  String get copy => _t(
        en: 'Copy',
        hi: 'कॉपी',
        de: 'Kopieren',
        fr: 'Copier',
        es: 'Copiar',
        it: 'Copia',
      );

  String get pasteFromClipboard => _t(
        en: 'Paste',
        hi: 'पेस्ट',
        de: 'Einfügen',
        fr: 'Coller',
        es: 'Pegar',
        it: 'Incolla',
      );

  String get share => _t(
        en: 'Share',
        hi: 'शेयर',
        de: 'Teilen',
        fr: 'Partager',
        es: 'Compartir',
        it: 'Condividi',
      );

  String get download => _t(
        en: 'Download',
        hi: 'डाउनलोड',
        de: 'Download',
        fr: 'Télécharger',
        es: 'Descargar',
        it: 'Scarica',
      );

  String _t({
    required String en,
    String? hi,
    String? de,
    String? fr,
    String? es,
    String? it,
  }) {
    return switch (_lang) {
      'hi' => hi ?? en,
      'de' => de ?? en,
      'fr' => fr ?? en,
      'es' => es ?? en,
      'it' => it ?? en,
      _ => en,
    };
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

