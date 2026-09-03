import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';

/// PFM Management sends a system-wide announcement (downtime / planned
/// maintenance / deadline reminder) to a chosen audience (all users, MDA
/// users only, MMDA users only, or internal staff). Goes through the
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

/// Recipient filter — see functions/index.js's matchesBroadcastAudience for
/// the exact matching logic this maps onto server-side.
enum _Audience { all, mda, mmda, staff }

extension on _Audience {
  String get wireValue => switch (this) {
        _Audience.all => 'all',
        _Audience.mda => 'mda',
        _Audience.mmda => 'mmda',
        _Audience.staff => 'staff',
      };

  String get label => switch (this) {
        _Audience.all => 'All Users',
        _Audience.mda => 'MDA Users',
        _Audience.mmda => 'MMDA Users',
        _Audience.staff => 'Staff (Support / Admin)',
      };
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _topicController = TextEditingController();
  final _messageController = TextEditingController();
  NotificationType _category = NotificationType.systemDowntime;
  _Audience _audience = _Audience.all;
  bool _sending = false;
  String? _error;
  String? _success;

  static const _topicPresets = ['System Downtime', 'Planned Maintenance', 'Deadline Reminder'];

  @override
  void dispose() {
    _topicController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _categoryLabel(NotificationType type) => switch (type) {
        NotificationType.systemDowntime => 'System Downtime',
        NotificationType.maintenance => 'Planned Maintenance',
        NotificationType.deadlineReminder => 'Deadline Reminder',
        _ => type.wireValue,
      };

  Future<void> _confirmAndSend() async {
    final topic = _topicController.text.trim();
    final message = _messageController.text.trim();
    setState(() {
      _error = null;
      _success = null;
    });
    if (topic.isEmpty) {
      setState(() => _error = 'Enter or choose a topic.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = 'Enter a message to send.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send announcement?'),
        content: Text(
          'This sends a push notification and in-app alert to ${_audience.label.toLowerCase()} — this can\'t be undone.\n\n'
          '"$topic"\n$message',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Send')),
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
        'type': _category.wireValue,
        'topic': topic,
        'message': message,
        'audience': _audience.wireValue,
      });
      final sent = (result.data as Map)['sent'] as int? ?? 0;
      if (!mounted) return;
      setState(() => _success = 'Announcement sent to $sent user${sent == 1 ? '' : 's'}.');
      _topicController.clear();
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
          'Sends a push notification and in-app alert to the audience you choose below.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Send To', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 6),
        DropdownButtonFormField<_Audience>(
          initialValue: _audience,
          items: [
            for (final a in _Audience.values) DropdownMenuItem(value: a, child: Text(a.label)),
          ],
          onChanged: (v) => setState(() => _audience = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Category', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 6),
        DropdownButtonFormField<NotificationType>(
          initialValue: _category,
          items: [
            for (final t in [NotificationType.systemDowntime, NotificationType.maintenance, NotificationType.deadlineReminder])
              DropdownMenuItem(value: t, child: Text(_categoryLabel(t))),
          ],
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Topic', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _topicPresets)
              ActionChip(
                label: Text(preset),
                onPressed: () => setState(() => _topicController.text = preset),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _topicController,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Pick a suggestion above, or type your own topic'),
        ),
        const SizedBox(height: AppSpacing.sm),
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
              : Text('Send to ${_audience.label}'),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(appBar: AppBar(title: const Text('Announcements')), body: content);
  }
}
