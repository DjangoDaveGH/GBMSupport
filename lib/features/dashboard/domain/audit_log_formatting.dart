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
  'announcement_sent' => 'Sent Announcement',
  'config_changed' => 'Settings Changed',
  'institution_created' => 'Institution Created',
  'institution_changed' => 'Institution Changed',
  _ => action,
};

const _configLabels = {
  'sla': 'SLA policy',
  'assignment_rules': 'Assignment rules',
  'general': 'General settings',
};

/// What an audit entry is about. User actions show the user's name; settings
/// and institutions show what was changed, since their ids aren't readable.
String adminTargetLabel(AuditLog a, {String? userName}) =>
    switch (a.targetType) {
      'config' => _configLabels[a.targetId] ?? a.targetId,
      'institution' => a.metadata['name']?.toString() ?? a.targetId,
      _ => userName ?? a.targetId,
    };

String describeAdminAction(AuditLog a, String targetName) {
  final details = a.metadata.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  return details.isEmpty ? targetName : '$targetName ($details)';
}
