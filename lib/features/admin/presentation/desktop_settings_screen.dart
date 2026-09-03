import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/config/data/general_settings_providers.dart';
import 'package:hyport/features/config/domain/general_settings.dart';

/// Phase 5 mockup screen 37. General Settings is real (see
/// GeneralSettingsRepository); Security/Notifications/Roles & Permissions
/// stay honestly labeled as not configurable in this build, same policy as
/// everywhere else. SLA Management/Auto-Assignment/Ticket Settings/
/// Announcements/Audit Logs push to their own already-built routes rather
/// than duplicating that content inline.
class DesktopSettingsScreen extends StatefulWidget {
  const DesktopSettingsScreen({super.key});

  @override
  State<DesktopSettingsScreen> createState() => _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends State<DesktopSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _NavTile(label: 'General', selected: true, onTap: () {}),
                  _NavTile(label: 'SLA Management', selected: false, onTap: () => context.push('/admin-settings/sla')),
                  _NavTile(label: 'Auto-Assignment', selected: false, onTap: () => context.push('/admin-settings/assignment')),
                  _NavTile(label: 'Ticket Settings', selected: false, onTap: () => context.push('/admin-settings/tickets')),
                  _NavTile(label: 'Announcements', selected: false, onTap: () => context.push('/admin-settings/announcements')),
                  _NavTile(
                    label: 'Security',
                    selected: false,
                    onTap: () => _showComingSoon(context, 'Security', 'Org-wide password policy and session controls aren\'t configurable here yet.'),
                  ),
                  _NavTile(
                    label: 'Notifications',
                    selected: false,
                    onTap: () => _showComingSoon(context, 'Notifications', 'Org-wide notification templates aren\'t configurable here yet.'),
                  ),
                  _NavTile(
                    label: 'Roles & Permissions',
                    selected: false,
                    onTap: () => _showComingSoon(context, 'Roles & Permissions', 'Role/permission matrices are fixed in this build, not editable here yet.'),
                  ),
                  _NavTile(label: 'Audit Logs', selected: false, onTap: () => context.push('/audit-logs')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(child: _GeneralSettingsPanel()),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.navy : AppTheme.ink, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralSettingsPanel extends ConsumerStatefulWidget {
  const _GeneralSettingsPanel();

  @override
  ConsumerState<_GeneralSettingsPanel> createState() => _GeneralSettingsPanelState();
}

class _GeneralSettingsPanelState extends ConsumerState<_GeneralSettingsPanel> {
  late final TextEditingController _appNameController;
  String _timezone = 'GMT+00:00 Accra';
  String _dateFormat = 'MMM d, yyyy';
  String _timeFormat = '24-hour';
  bool _initialized = false;
  bool _saving = false;
  bool _uploadingLogo = false;

  static const _timezones = ['GMT+00:00 Accra', 'GMT+00:00 London', 'GMT-05:00 New York'];
  static const _dateFormats = ['MMM d, yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd'];
  static const _timeFormats = ['24-hour', '12-hour'];

  void _initFrom(GeneralSettings settings) {
    _appNameController = TextEditingController(text: settings.appName);
    _timezone = settings.timezone;
    _dateFormat = settings.dateFormat;
    _timeFormat = settings.timeFormat;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) _appNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage('Could not read that image. Please try another file.');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _showMessage('Logo images must be smaller than 5 MB.');
      return;
    }

    setState(() => _uploadingLogo = true);
    try {
      final extension = file.extension?.toLowerCase();
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final storageRef = ref.read(firebaseStorageProvider).ref('branding/logo');
      final snapshot = await storageRef.putData(bytes, SettableMetadata(contentType: contentType));
      final url = await snapshot.ref.getDownloadURL();
      await ref.read(generalSettingsRepositoryProvider).setLogoUrl(url);
      _showMessage('Application logo updated.');
    } catch (e) {
      _showMessage('Could not update the logo: $e');
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(generalSettingsRepositoryProvider).update(GeneralSettings(
            appName: _appNameController.text.trim(),
            timezone: _timezone,
            dateFormat: _dateFormat,
            timeFormat: _timeFormat,
          ));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(generalSettingsProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: settingsAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Text('Could not load settings: $e'),
        data: (settings) {
          if (!_initialized) _initFrom(settings);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('General Settings', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                Text('Application Name', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                const SizedBox(height: 6),
                TextField(controller: _appNameController),
                const SizedBox(height: 20),
                Text('Application Logo', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (settings.logoUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.network(settings.logoUrl!, width: 40, height: 40, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton(
                      onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                      child: _uploadingLogo
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Choose File'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        settings.logoUrl != null ? 'Logo uploaded.' : 'No logo uploaded yet.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Default Timezone', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _timezone,
                  items: _timezones.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _timezone = v!),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date Format', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _dateFormat,
                            items: _dateFormats.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                            onChanged: (v) => setState(() => _dateFormat = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Time Format', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _timeFormat,
                            items: _timeFormats.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (v) => setState(() => _timeFormat = v!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
