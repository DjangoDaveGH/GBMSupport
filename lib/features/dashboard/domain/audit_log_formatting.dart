import 'package:hyport/core/models/audit_log.dart';

/// Shared with DesktopAuditLogsScreen's Admin Actions tab (this used to be
/// private to that file) so the dashboards' "Recent System Activity" panel
/// renders the exact same labels rather than a second, driftable copy.
String adminActionLabel(String action) => switch (action) {
      'user_created' => 'User Created',
      'user_role_changed' => 'Role Changed',
      'user_activated' => 'User Activated',
      'user_deactivated' => 'User Deactivated',
      'user_updated' => 'User Updated',
      _ => action,
    };

String describeAdminAction(AuditLog a, String targetName) {
  final details = a.metadata.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  return details.isEmpty ? targetName : '$targetName ($details)';
}
