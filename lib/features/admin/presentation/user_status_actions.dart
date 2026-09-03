import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

/// Deactivate/reactivate a user account, shared by the mobile and desktop
/// Users screens. This is the same `adminUpdateUser` callable and `isActive`
/// field the full edit dialog already exposes (see edit_user_dialog.dart) —
/// just surfaced as a one-tap row action with its own confirmation, instead
/// of requiring the admin to open the full editor to flip one switch.
/// There is no hard-delete: tickets reference users by uid (createdBy,
/// assignedTo), and removing the account would orphan that history.
Future<void> confirmSetUserActive(BuildContext context, AppUser user, {required bool active}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(active ? 'Reactivate ${user.name}?' : 'Deactivate ${user.name}?'),
      content: Text(
        active
            ? 'They will be able to sign in again immediately.'
            : 'They will be signed out and unable to sign in until reactivated. Tickets they created or were assigned stay unaffected.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: active ? null : FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: Text(active ? 'Reactivate' : 'Deactivate'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await FirebaseFunctions.instance.httpsCallable('adminUpdateUser').call({'uid': user.id, 'isActive': active});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(active ? '${user.name} reactivated.' : '${user.name} deactivated.')));
    }
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Could not update user (${e.code}).')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update user: $e')));
    }
  }
}
