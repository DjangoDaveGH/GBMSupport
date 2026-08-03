/// Application-wide display preferences (Phase 5 mockup screen 37's
/// "General Settings" panel). Stored as a single `config/general` doc —
/// real and editable, unlike Security/Notifications/Roles & Permissions
/// which stay honestly labeled as not configurable in this build.
class GeneralSettings {
  final String appName;
  final String timezone;
  final String dateFormat;
  final String timeFormat;

  const GeneralSettings({
    this.appName = 'Oracle Hyperion Support Centre',
    this.timezone = 'GMT+00:00 Accra',
    this.dateFormat = 'MMM d, yyyy',
    this.timeFormat = '24-hour',
  });

  factory GeneralSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GeneralSettings();
    return GeneralSettings(
      appName: map['appName'] as String? ?? 'Oracle Hyperion Support Centre',
      timezone: map['timezone'] as String? ?? 'GMT+00:00 Accra',
      dateFormat: map['dateFormat'] as String? ?? 'MMM d, yyyy',
      timeFormat: map['timeFormat'] as String? ?? '24-hour',
    );
  }

  Map<String, dynamic> toMap() => {
        'appName': appName,
        'timezone': timezone,
        'dateFormat': dateFormat,
        'timeFormat': timeFormat,
      };
}
