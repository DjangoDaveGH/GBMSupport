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
  ///
  /// Exact paths, not prefixes: '/tickets/:id' shares a first segment with
  /// these, and a Firestore auto-ID can start with any letters — a prefix
  /// match would silently stop remembering a ticket whose id begins "new…".
  static const _excludedPaths = {
    '/tickets/new',
    '/tickets/filters',
    '/tickets/closed',
    '/knowledge-base/new',
    '/admin/users/new',
  };
  static const _excludedSuffixes = ['/assign'];

  static SharedPreferences? _prefs;
  static Future<void>? _initFuture;

  /// Kicked off unawaited from main() so it never blocks the first frame —
  /// but app_router.dart's redirect must still be able to wait for it
  /// specifically at the one moment it actually needs the result (resuming
  /// on splash), rather than silently treating "not ready yet" the same as
  /// "nothing saved" and falling back to /home. Safe to call from both
  /// places: the second caller just awaits the same in-flight future.
  static Future<void> ensureInitialized() {
    return _initFuture ??= _init();
  }

  static Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Bounded wait: a hung/unavailable SharedPreferences must never hang
      // the router's redirect forever. restore() below just returns null
      // (same as "nothing saved yet") if this never populates _prefs.
    }
  }

  static void save(String location) {
    if (_excludedPaths.contains(location)) return;
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
