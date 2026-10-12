import 'dart:js_interop';

@JS('hyportReloadApp')
external void _reloadApp();

Future<void> reloadWebApp() async => _reloadApp();
