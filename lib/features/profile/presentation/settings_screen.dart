import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

/// Matches the reference Settings screen's section layout, minus Biometric
/// Login (removed — this app has no working security control behind it) and
/// with "Change Password" relabeled "Request Password" (it only ever sent a
/// reset-link email, never an in-app change). Request Password, Logout, and
/// Two-Factor Authentication are fully functional. Two-Factor Authentication
/// is real (toggles `users/{uid}.twoFactorEnabled` and gates login via the
/// router), but its code delivery is interim — see OtpVerifyScreen's doc
/// comment.
class SettingsScreen extends ConsumerWidget {
  /// When true, renders just the list content with no Scaffold/AppBar of
  /// its own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const SettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;

    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Account'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.lock_reset_rounded,
              label: 'Request Password',
              onTap: appUser == null
                  ? null
                  : () async {
                      await ref.read(authServiceProvider).sendPasswordResetEmail(appUser.email);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password reset link sent to your email.')),
                        );
                      }
                    },
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('Security'),
          _SettingsCard(children: [
            if (appUser != null) _TwoFactorSwitch(appUser: appUser),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('Preferences'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.notifications_none_rounded,
              label: 'Notification Preferences',
              onTap: () => context.push('/notifications'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(icon: Icons.language_rounded, label: 'Language', trailing: 'English', onTap: null),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('Other'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              onTap: () => context.push('/knowledge-base'),
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About App',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Oracle Hyperion Support Centre',
                applicationVersion: '1.0.0',
                applicationLegalese: 'Ministry of Finance — PFM-Systems Division',
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Logout'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Version 1.0.0', style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: body);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
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
  final String? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({required this.icon, required this.label, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppTheme.accentBlue),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: trailing != null
          ? Text(trailing!, style: Theme.of(context).textTheme.bodySmall)
          : (onTap != null ? const Icon(Icons.chevron_right_rounded, size: 20) : null),
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
    );
  }
}

/// Real, working toggle for `users/{uid}.twoFactorEnabled` — unlike a plain
/// on/off switch backed by nothing, this is controlled directly by the live
/// `AppUser` (not local widget state), so it stays correct if the flag
/// ever changes from elsewhere (e.g. an admin action in a future phase).
class _TwoFactorSwitch extends ConsumerStatefulWidget {
  final AppUser appUser;

  const _TwoFactorSwitch({required this.appUser});

  @override
  ConsumerState<_TwoFactorSwitch> createState() => _TwoFactorSwitchState();
}

class _TwoFactorSwitchState extends ConsumerState<_TwoFactorSwitch> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).setTwoFactorEnabled(widget.appUser.id, value);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.verified_user_outlined, size: 20, color: AppTheme.accentBlue),
      title: Text('Two-Factor Authentication', style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        widget.appUser.twoFactorEnabled
            ? 'On — codes shown on-screen until email delivery is set up.'
            : 'Off — turn on to require a verification code at login.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      isThreeLine: true,
      trailing: _saving
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(value: widget.appUser.twoFactorEnabled, onChanged: _toggle),
      shape: const RoundedRectangleBorder(),
    );
  }
}
