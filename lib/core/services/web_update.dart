/// Web-only app update controls with a no-op native fallback.
library;

export 'web_update_stub.dart'
    if (dart.library.js_interop) 'web_update_web.dart';
