import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// Matches the reference Settings screen's section layout, minus Biometric
/// Login (removed — this app has no working security control behind it).
/// "Change Password" does a real in-app password change (current + new
/// password, via AuthService.changePassword). The old "Request Password"
/// reset-link-email tile was removed from here; a forgotten-password user
/// still has the "Forgot Password?" link on the login screen.
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
              icon: Icons.password_rounded,
              label: 'Change Password',
              onTap: appUser == null ? null : () => _showChangePasswordDialog(context, ref),
            ),
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
                applicationName: 'GBMS Support Centre',
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

  Future<void> _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    return showDialog(context: context, builder: (_) => const _ChangePasswordDialog());
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
            'wrong-password' || 'invalid-credential' => 'Current password is incorrect.',
            'weak-password' => 'New password is too weak.',
            _ => e.message ?? 'Could not change password (${e.code}).',
          });
    } catch (e) {
      setState(() => _error = 'Could not change password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password'),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
                validator: (v) => v != _newController.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
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

