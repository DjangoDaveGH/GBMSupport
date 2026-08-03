/// "Can this browser install us as a PWA right now?" — real implementation
/// on web (pwa_install_web.dart, backed by the JS bridge in
/// web/index.html), a no-op stub everywhere else (pwa_install_stub.dart),
/// so `PwaInstallButton` can be dropped into shared shell widgets without
/// those widgets needing their own `kIsWeb` branching.
library;

export 'pwa_install_stub.dart' if (dart.library.js_interop) 'pwa_install_web.dart';
