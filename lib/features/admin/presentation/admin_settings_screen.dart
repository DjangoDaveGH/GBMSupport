import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Phase 4 mockup screen 28 — application/system-wide settings, distinct
/// from the per-user account Settings reachable from Profile. SLA
/// Management, Auto-Assignment, Ticket Settings, and Announcements are
/// real; General/Notifications/Security/System are honestly labeled as not
/// configurable in this build rather than presented as working controls —
/// same policy as the per-user Settings screen's Biometric/2FA rows.
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.tune_rounded,
              label: 'General',
              subtitle: 'App preferences, language, timezone',
              onTap: () => _showComingSoon(context, 'General', 'App-wide preferences like language and timezone aren\'t configurable in this build yet.'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.rule_folder_outlined,
              label: 'SLA Management',
              subtitle: 'SLA policies and response times',
              onTap: () => context.push('/admin-settings/sla'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.auto_awesome_motion_outlined,
              label: 'Auto-Assignment',
              subtitle: 'Which staff handle each ticket category',
              onTap: () => context.push('/admin-settings/assignment'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.confirmation_number_outlined,
              label: 'Ticket Settings',
              subtitle: 'Categories, priorities, workflows',
              onTap: () => context.push('/admin-settings/tickets'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.campaign_outlined,
              label: 'Announcements',
              subtitle: 'Send a system-wide notice to all users',
              onTap: () => context.push('/admin-settings/announcements'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              subtitle: 'Email, push, in-app notifications',
              onTap: () => _showComingSoon(
                context,
                'Notifications',
                'Org-wide notification templates and channels aren\'t configurable here yet. Each user manages their own preferences from Profile → Settings.',
              ),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.security_rounded,
              label: 'Security',
              subtitle: 'Password policy, 2FA, sessions',
              onTap: () => _showComingSoon(
                context,
                'Security',
                'Org-wide password policy and session controls aren\'t configurable here yet. Users can turn on their own two-factor login from Profile → Settings.',
              ),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.dns_outlined,
              label: 'System',
              subtitle: 'System configuration and logs',
              onTap: () => _showComingSoon(context, 'System', 'System configuration and audit logs aren\'t exposed in this build yet.'),
            ),
          ]),
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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppTheme.accentBlue),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
    );
  }
}
