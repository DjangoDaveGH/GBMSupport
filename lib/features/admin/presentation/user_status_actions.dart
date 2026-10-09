import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

/// Lets an authorized administrator set another user's password directly.
/// The password is never persisted or sent by email; arrange secure delivery
/// to the user outside the app.
Future<void> promptSetUserPassword(BuildContext context, AppUser user) async {
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  var submitting = false;
  var obscure = true;
  String? error;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Set password for ${user.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This changes the account password immediately. Use a unique password of at least 6 characters and share it with the user securely. The password is not emailed or stored in the audit log.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  enabled: !submitting,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setDialogState(() => obscure = !obscure),
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: obscure,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  onSubmitted: (_) {},
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final password = passwordController.text;
                      if (password.length < 6 || password.length > 128) {
                        setDialogState(
                          () => error =
                              'Use a password between 6 and 128 characters.',
                        );
                        return;
                      }
                      if (password != confirmController.text) {
                        setDialogState(
                          () => error = 'The passwords do not match.',
                        );
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await FirebaseFunctions.instance
                            .httpsCallable('adminSetUserPassword')
                            .call({'uid': user.id, 'password': password});
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Password changed for ${user.name}. Share it securely.',
                              ),
                            ),
                          );
                        }
                      } on FirebaseFunctionsException catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error =
                              e.message ??
                              'Could not change the password (${e.code}).';
                        });
                      } catch (_) {
                        setDialogState(() {
                          submitting = false;
                          error =
                              'Could not change the password. Please try again.';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Change password'),
            ),
          ],
        ),
      ),
    );
  } finally {
    passwordController.dispose();
    confirmController.dispose();
  }
}

/// Deactivate/reactivate a user account, shared by the mobile and desktop
/// Users screens. This is the same `adminUpdateUser` callable and `isActive`
/// field the full edit dialog already exposes (see edit_user_dialog.dart) —
/// just surfaced as a one-tap row action with its own confirmation, instead
/// of requiring the admin to open the full editor to flip one switch.
/// There is no hard-delete: tickets reference users by uid (createdBy,
/// assignedTo), and removing the account would orphan that history.
Future<void> confirmSetUserActive(
  BuildContext context,
  AppUser user, {
  required bool active,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        active ? 'Reactivate ${user.name}?' : 'Deactivate ${user.name}?',
      ),
      content: Text(
        active
            ? 'They will be able to sign in again immediately.'
            : 'They will be signed out and unable to sign in until reactivated. Tickets they created or were assigned stay unaffected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: active
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
          child: Text(active ? 'Reactivate' : 'Deactivate'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await FirebaseFunctions.instance.httpsCallable('adminUpdateUser').call({
      'uid': user.id,
      'isActive': active,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? '${user.name} reactivated.' : '${user.name} deactivated.',
          ),
        ),
      );
    }
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Could not update user (${e.code}).'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update user: $e')));
    }
  }
}
