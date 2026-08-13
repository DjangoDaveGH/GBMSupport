/// Non-web platforms (Android, etc.) — there's no browser install prompt,
/// so this is always a no-op. See pwa_install.dart for the conditional
/// export that picks this vs. the real web implementation.
class PwaInstall {
  const PwaInstall._();

  static bool get isSupported => false;

  static bool get canInstall => false;

  static bool get isInstalled => false;

  static Future<String> promptInstall() async => 'unavailable';
}
