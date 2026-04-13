class AppStrings {
  final List<String> giftNames;
  final String tapToPay;
  final String tapAtTop;
  final String cancel;
  final String close;
  final String confirm;
  final String goBack;
  final String paymentConfirmed;
  final String takeItemToClose;
  final String closeSlot;
  final String _enjoyPrefix;
  final String _enjoySuffix;
  final String thankYou;
  final String ready;
  final String connecting;

  const AppStrings({
    required this.giftNames,
    required this.tapToPay,
    required this.tapAtTop,
    required this.cancel,
    required this.close,
    required this.confirm,
    required this.goBack,
    required this.paymentConfirmed,
    required this.takeItemToClose,
    required this.closeSlot,
    required String enjoyPrefix,
    required String enjoySuffix,
    required this.thankYou,
    required this.ready,
    required this.connecting,
  }) : _enjoyPrefix = enjoyPrefix,
       _enjoySuffix = enjoySuffix;

  String enjoyItem(String name) => '$_enjoyPrefix$name$_enjoySuffix';

  static AppStrings of(String languageCode) {
    switch (languageCode) {
      case 'pt':
        return _portuguese;
      case 'de':
        return _german;
      default:
        return _english;
    }
  }

  static const _english = AppStrings(
    giftNames: ['Gift 1', 'Gift 2', 'Gift 3'],
    tapToPay: 'Tap NFC card to pay',
    tapAtTop: 'Hold card near top of device',
    cancel: 'Cancel',
    close: 'Close',
    confirm: 'Confirm',
    goBack: 'Go back',
    paymentConfirmed: 'Payment confirmed',
    takeItemToClose: 'Take your item, then tap to close:',
    closeSlot: 'Close\nSlot',
    enjoyPrefix: 'Enjoy your ',
    enjoySuffix: '!',
    thankYou: '🎉  Thank you for your purchase',
    ready: 'Ready',
    connecting: 'Connecting…',
  );

  static const _portuguese = AppStrings(
    giftNames: ['Presente 1', 'Presente 2', 'Presente 3'],
    tapToPay: 'Toque o cartão NFC para pagar',
    tapAtTop: 'Aproxime o cartão ao topo do dispositivo',
    cancel: 'Cancelar',
    close: 'Fechar',
    confirm: 'Confirmar',
    goBack: 'Voltar',
    paymentConfirmed: 'Pagamento confirmado',
    takeItemToClose: 'Retire o seu item e toque para fechar:',
    closeSlot: 'Fechar\nGaveta',
    enjoyPrefix: 'Aproveite o seu ',
    enjoySuffix: '!',
    thankYou: '🎉  Obrigado pela sua compra',
    ready: 'Pronto',
    connecting: 'A ligar…',
  );

  static const _german = AppStrings(
    giftNames: ['Geschenk 1', 'Geschenk 2', 'Geschenk 3'],
    tapToPay: 'NFC-Karte zum Bezahlen antippen',
    tapAtTop: 'Karte an die Oberseite des Geräts halten',
    cancel: 'Abbrechen',
    close: 'Schließen',
    confirm: 'Bestätigen',
    goBack: 'Zurück',
    paymentConfirmed: 'Zahlung bestätigt',
    takeItemToClose: 'Artikel entnehmen, dann tippen zum Schließen:',
    closeSlot: 'Fach\nSchließen',
    enjoyPrefix: 'Viel Spaß mit ',
    enjoySuffix: '!',
    thankYou: '🎉  Vielen Dank für Ihren Kauf',
    ready: 'Bereit',
    connecting: 'Verbinde…',
  );
}
