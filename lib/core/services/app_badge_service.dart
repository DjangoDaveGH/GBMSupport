import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

/// Sets the unread-count badge on the app's launcher / dock / taskbar icon.
///
///  - Android / iOS: via app_badge_plus (OEM launcher badge; iOS shows it
///    natively, most Android launchers show a dot or count).
///  - Web: app_badge_plus routes to `navigator.setAppBadge`, which only has
///    an effect once the PWA is installed. Background pushes update it
///    separately from the service worker (web/firebase-messaging-sw.js).
///
/// Every call is best-effort — a launcher without badge support just makes
/// this a no-op, and any plugin error is swallowed so notification handling
/// never breaks over a cosmetic badge.
class AppBadgeService {
  AppBadgeService._();

  static Future<void> set(int count) async {
    try {
      if (count > 0) {
        await AppBadgePlus.updateBadge(count);
      } else {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (e) {
      debugPrint('AppBadgeService.set($count) failed: $e');
    }
  }
}
