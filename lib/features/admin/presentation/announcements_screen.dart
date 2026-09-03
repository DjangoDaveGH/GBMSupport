import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// PFM Management sends a system-wide announcement (downtime / planned
/// maintenance / deadline reminder) to every active user. Goes through the
/// `adminBroadcastNotification` Cloud Function rather than a client-side
/// Firestore write — see functions/index.js: a single WriteBatch caps at
/// 500 writes (well under the active user count), and only the Admin SDK
/// can send the FCM push, so this can't be done from the client at all.
class AnnouncementsScreen extends StatefulWidget {
  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const AnnouncementsScreen({super.key, this.embedded = false});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _messageController = TextEditingController();
  NotificationType _type = NotificationType.systemDowntime;
  bool _sending = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _labelFor(NotificationType type) => switch (type) {
        NotificationType.systemDowntime => 'System Downtime',
        NotificationType.maintenance => 'Planned Maintenance',
        NotificationType.deadlineReminder => 'Deadline Reminder',
        _ => type.wireValue,
      };

  Future<void> _confirmAndSend() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() {
        _error = 'Enter a message to send.';
        _success = null;
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send announcement?'),
        content: Text(
          'This sends a push notification and in-app alert to every active user in the system — this can\'t be undone.\n\n'
          '${_labelFor(_type)}: "$message"',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Send to Everyone')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'adminBroadcastNotification',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );
      final result = await callable.call({
        'type': _type.wireValue,
        'message': message,
      });
      final sent = (result.data as Map)['sent'] as int? ?? 0;
      if (!mounted) return;
      setState(() => _success = 'Announcement sent to $sent user${sent == 1 ? '' : 's'}.');
      _messageController.clear();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Could not send announcement (${e.code}).');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send announcement: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Send Announcement', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Sends a push notification and in-app alert to every active user — for system downtime, planned maintenance, or a deadline reminder.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Type', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 6),
        DropdownButtonFormField<NotificationType>(
          initialValue: _type,
          items: [
            for (final t in [NotificationType.systemDowntime, NotificationType.maintenance, NotificationType.deadlineReminder])
              DropdownMenuItem(value: t, child: Text(_labelFor(t))),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Message', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 6),
        TextField(
          controller: _messageController,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'e.g. GBMS will be offline for maintenance on...'),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_success != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_success!, style: const TextStyle(color: AppTheme.success)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _sending ? null : _confirmAndSend,
          child: _sending
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send to All Users'),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(appBar: AppBar(title: const Text('Announcements')), body: content);
  }
}
