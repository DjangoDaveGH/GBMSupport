import 'dart:js_interop';

/// Static-interop bindings for the plain-JS bridge set up in web/index.html
/// (there's no Dart-native API for the browser's `beforeinstallprompt`
/// flow). Paths resolve against the global JS scope, i.e.
/// `window.hyportPwaInstall.available` / `window.hyportPwaInstallPrompt()`.
@JS('hyportPwaInstall.available')
external bool? get _available;

@JS('hyportPwaInstall.installed')
external bool? get _installed;

@JS('hyportPwaInstallPrompt')
external JSPromise<JSString> _promptJS();

class PwaInstall {
  const PwaInstall._();

  static bool get isSupported => true;

  static bool get canInstall => (_available ?? false) && !(_installed ?? false);

  static Future<String> promptInstall() async {
    final outcome = await _promptJS().toDart;
    return outcome.toDart;
  }
}
