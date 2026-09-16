import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last screen the user was on to disk (not just memory), so
/// that when Android reclaims the app's process in the background — which
/// throws away all in-memory state, including go_router's navigation stack
/// — the next launch resumes there instead of always landing back on the
/// dashboard. That "cold start" looks identical to a deliberate relaunch
/// from the user's perspective (same splash screen), which is exactly why
/// it used to always fall through to /home; see app_router.dart's redirect,
/// which saves on every navigation and consumes this once at startup.
class LastRouteService {
  static const _key = 'last_route';

  /// Routes that are unsafe or confusing to resume straight into — a
  /// mid-wizard step, an action sheet, a one-off editor. Everything else
  /// (ticket detail, ticket chat, knowledge base, admin screens, ...) is
  /// fine to reopen directly; the redirect's own role checks still run
  /// against the restored location before it's granted, in case the
  /// account's access changed while the app was gone.
  static const _excludedPrefixes = [
    '/tickets/new',
    '/tickets/filters',
    '/tickets/closed',
    '/knowledge-base/new',
    '/admin/users/new',
  ];
  static const _excludedSuffixes = ['/assign'];

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static void save(String location) {
    if (_excludedPrefixes.any(location.startsWith)) return;
    if (_excludedSuffixes.any(location.endsWith)) return;
    _prefs?.setString(_key, location);
  }

  /// Reads back the saved location without clearing it — restoration should
  /// survive more than one cold start in a row (e.g. the OS kills the app
  /// again a minute later, before the user has navigated anywhere new).
  static String? restore() => _prefs?.getString(_key);

  /// Called on sign-out so a shared device doesn't drop the next person who
  /// signs in into a screen from someone else's session.
  static void clear() => _prefs?.remove(_key);
}
