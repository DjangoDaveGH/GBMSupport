import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/admin/data/announcement_repository.dart';
import 'package:hyport/features/admin/domain/announcement.dart';
import 'package:hyport/features/tickets/presentation/attachment_utils.dart';
import 'package:hyport/features/tickets/presentation/ticket_attachments_section.dart';
import 'package:intl/intl.dart';

/// PFM Management creates, edits and deletes system-wide announcements
/// (downtime / planned maintenance / deadline reminder) for a chosen
/// audience, optionally with files attached (images, PDFs, Office
/// documents...). Sending, editing and deleting all go through Cloud
/// Functions (see functions/index.js): a single WriteBatch caps at 500
/// writes (well under the active user count), only the Admin SDK can send
/// the FCM push, and edits/deletes must reach every recipient's copy.
class AnnouncementsScreen extends ConsumerStatefulWidget {
  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const AnnouncementsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

const _allowedExtensions = [
  'png', 'jpg', 'jpeg', 'gif', 'webp', //
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'txt', 'zip',
];

const _contentTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'csv': 'text/csv',
  'txt': 'text/plain',
  'zip': 'application/zip',
};

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A file in the composer: either already uploaded ([url] set) or uploading.
class _DraftFile {
  final String name;
  final int? size;
  String? url;
  bool uploading;

  /// Uploaded during this draft/edit session (so cancelling can clean it up).
  final bool isNew;

  _DraftFile({
    required this.name,
    this.size,
    this.url,
    this.uploading = false,
    this.isNew = true,
  });
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final _topicController = TextEditingController();
  final _messageController = TextEditingController();
  NotificationType _category = NotificationType.systemDowntime;
  AnnouncementAudience _audience = AnnouncementAudience.all;
  final List<_DraftFile> _files = [];
  bool _busy = false;
  String? _error;
  String? _success;

  /// Id the draft's files are uploaded under: a fresh id for a new
  /// announcement, or the announcement's own id while editing.
  late String _draftId;
  Announcement? _editing;

  static const _topicPresets = [
    'System Downtime',
    'Planned Maintenance',
    'Deadline Reminder',
  ];

  AnnouncementRepository get _repo => ref.read(announcementRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _draftId = _repo.newId();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _uploading => _files.any((f) => f.uploading);

  String _friendlyError(Object e, String action) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? 'Could not $action (${e.code}).';
    }
    return 'Could not $action: $e';
  }

  void _resetComposer() {
    _topicController.clear();
    _messageController.clear();
    _files.clear();
    _editing = null;
    _category = NotificationType.systemDowntime;
    _audience = AnnouncementAudience.all;
    _draftId = _repo.newId();
  }

  /// Leaves edit mode (or clears a new draft), deleting files uploaded in
  /// this session that were never saved.
  void _discardDraft() {
    for (final f in _files.where((f) => f.isNew && f.url != null)) {
      _repo.deleteUnsentAttachment(f.url!);
    }
    setState(() {
      _resetComposer();
      _error = null;
      _success = null;
    });
  }

  void _startEditing(Announcement a) {
    // Drop anything uploaded for the abandoned draft first.
    for (final f in _files.where((f) => f.isNew && f.url != null)) {
      _repo.deleteUnsentAttachment(f.url!);
    }
    setState(() {
      _editing = a;
      _draftId = a.id;
      _category = announcementTypes.contains(a.type)
          ? a.type
          : NotificationType.systemDowntime;
      _audience = a.audience;
      _topicController.text = a.topic;
      _messageController.text = a.message;
      _files
        ..clear()
        ..addAll(
          a.attachmentUrls.map(
            (u) => _DraftFile(name: attachmentFileName(u), url: u, isNew: false),
          ),
        );
      _error = null;
      _success = null;
    });
    Scrollable.ensureVisible(
      _composerKey.currentContext ?? context,
      duration: const Duration(milliseconds: 250),
    );
  }

  final _composerKey = GlobalKey();

  Future<void> _pickFiles() async {
    final room = maxAnnouncementAttachments - _files.length;
    if (room <= 0) {
      setState(
        () => _error =
            'You can attach up to $maxAnnouncementAttachments files.',
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (result == null || !mounted) return;

    final problems = <String>[];
    final picked = result.files.take(room).toList();
    if (result.files.length > room) {
      problems.add(
        'Only $room more file${room == 1 ? '' : 's'} could be attached',
      );
    }
    for (final file in picked) {
      final bytes = file.bytes;
      final ext = attachmentExtension(file.name);
      if (bytes == null) {
        problems.add('${file.name} could not be read');
        continue;
      }
      if (bytes.length > maxAnnouncementFileBytes) {
        problems.add(
          '${file.name} is over ${_formatSize(maxAnnouncementFileBytes)}',
        );
        continue;
      }
      if (ext == 'pdf' && !isPdfBytes(bytes)) {
        problems.add('${file.name} is not a valid PDF');
        continue;
      }
      final draft = _DraftFile(
        name: file.name,
        size: bytes.length,
        uploading: true,
      );
      setState(() => _files.add(draft));
      final uploadId = _draftId;
      _repo
          .uploadAttachment(
            announcementId: uploadId,
            fileName: file.name,
            bytes: bytes,
            contentType: _contentTypes[ext],
          )
          .then(
            (url) {
              if (!mounted || !_files.contains(draft) || _draftId != uploadId) {
                // Removed (or draft discarded) while uploading.
                _repo.deleteUnsentAttachment(url);
                return;
              }
              setState(() {
                draft.url = url;
                draft.uploading = false;
              });
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() {
                _files.remove(draft);
                _error = 'Could not upload ${file.name}: $e';
              });
            },
          );
    }
    if (problems.isNotEmpty) {
      setState(() => _error = '${problems.join('. ')}.');
    }
  }

  void _removeFile(_DraftFile f) {
    // A new upload can be deleted right away. A file already saved on the
    // announcement is only deleted once the edit is saved.
    if (f.isNew && f.url != null) _repo.deleteUnsentAttachment(f.url!);
    setState(() => _files.remove(f));
  }

  Future<void> _submit() async {
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
    if (_uploading) {
      setState(() => _error = 'Wait for the attachments to finish uploading.');
      return;
    }
    final editing = _editing;
    final urls = [for (final f in _files) f.url!];
    final fileLine = urls.isEmpty
        ? ''
        : '\n\n${urls.length} attachment${urls.length == 1 ? '' : 's'}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editing == null ? 'Send announcement?' : 'Save changes?'),
        content: Text(
          editing == null
              ? 'This sends a push notification and in-app alert to '
                    '${_audience.label.toLowerCase()}.\n\n"$topic"\n$message$fileLine'
              : 'This updates the announcement for everyone who received it '
                    '(${editing.recipientCount} user${editing.recipientCount == 1 ? '' : 's'}). '
                    'They won\'t get another push notification.\n\n"$topic"\n$message$fileLine',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(editing == null ? 'Send' : 'Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      if (editing == null) {
        final sent = await _repo.send(
          announcementId: _draftId,
          type: _category,
          topic: topic,
          message: message,
          audience: _audience,
          attachmentUrls: urls,
        );
        if (!mounted) return;
        setState(() {
          _resetComposer();
          _success =
              'Announcement sent to $sent user${sent == 1 ? '' : 's'}.';
        });
      } else {
        await _repo.update(
          announcementId: editing.id,
          type: _category,
          topic: topic,
          message: message,
          attachmentUrls: urls,
        );
        if (!mounted) return;
        setState(() {
          _resetComposer();
          _success = 'Announcement updated.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _friendlyError(
            e,
            editing == null ? 'send announcement' : 'save changes',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Announcement a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text(
          '"${a.topic}" will be removed from all ${a.recipientCount} '
          'recipient${a.recipientCount == 1 ? '' : 's'}\' notifications, '
          'and its attachments will be deleted. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _repo.delete(a.id);
      if (!mounted) return;
      if (_editing?.id == a.id) {
        setState(_resetComposer);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Announcement deleted.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyError(e, 'delete announcement'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: Colors.black54),
    ),
  );

  Widget _buildComposer() {
    final editing = _editing;
    final theme = Theme.of(context);
    return Column(
      key: _composerKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                editing == null ? 'Send Announcement' : 'Edit Announcement',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (editing != null)
              TextButton.icon(
                onPressed: _busy ? null : _discardDraft,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel edit'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          editing == null
              ? 'Sends a push notification and in-app alert to the audience you choose below.'
              : 'Changes appear in every recipient\'s notifications. No new push is sent, and the audience can\'t be changed.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: AppSpacing.lg),
        _label('Send To'),
        DropdownButtonFormField<AnnouncementAudience>(
          key: ValueKey('audience-${editing?.id}'),
          initialValue: _audience,
          items: [
            for (final a in AnnouncementAudience.values)
              DropdownMenuItem(value: a, child: Text(a.label)),
          ],
          onChanged: editing != null
              ? null
              : (v) => setState(() => _audience = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        _label('Category'),
        DropdownButtonFormField<NotificationType>(
          key: ValueKey('category-${editing?.id}'),
          initialValue: _category,
          items: [
            for (final t in announcementTypes)
              DropdownMenuItem(value: t, child: Text(announcementTypeLabel(t))),
          ],
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        _label('Topic'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _topicPresets)
              ActionChip(
                label: Text(preset),
                onPressed: () =>
                    setState(() => _topicController.text = preset),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _topicController,
          maxLength: 120,
          decoration: const InputDecoration(
            hintText: 'Pick a suggestion above, or type your own topic',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _label('Message'),
        TextField(
          controller: _messageController,
          minLines: 4,
          maxLines: 10,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'e.g. GBMS will be offline for maintenance on...',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _label('Attachments (optional)'),
        for (final f in _files) _DraftFileRow(file: f, onRemove: () => _removeFile(f)),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy || _files.length >= maxAnnouncementAttachments
                ? null
                : _pickFiles,
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('Add files'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Images, PDF, Word, Excel, PowerPoint, CSV, text or ZIP. '
          'Up to $maxAnnouncementAttachments files, ${_formatSize(maxAnnouncementFileBytes)} each.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_success != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_success!, style: const TextStyle(color: AppTheme.success)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy || _uploading ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _uploading
                      ? 'Uploading files…'
                      : editing == null
                      ? 'Send to ${_audience.label}'
                      : 'Save changes',
                ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    final announcementsAsync = ref.watch(announcementsProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sent Announcements', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        announcementsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load announcements: $e'),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'Announcements you send will appear here, where you can edit or delete them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              );
            }
            return Column(
              children: [
                for (final a in items)
                  _AnnouncementCard(
                    announcement: a,
                    isBeingEdited: _editing?.id == a.id,
                    busy: _busy,
                    onEdit: () => _startEditing(a),
                    onDelete: () => _delete(a),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildComposer(),
                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                _buildHistory(),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: content,
    );
  }
}

class _DraftFileRow extends StatelessWidget {
  final _DraftFile file;
  final VoidCallback onRemove;

  const _DraftFileRow({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(attachmentIcon(file.name), size: 20, color: AppTheme.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (file.size != null || file.uploading)
                  Text(
                    file.uploading
                        ? 'Uploading…'
                        : _formatSize(file.size!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (file.uploading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool isBeingEdited;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AnnouncementCard({
    required this.announcement,
    required this.isBeingEdited,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM yyyy, HH:mm');
    final sending = a.status == 'sending';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isBeingEdited
              ? AppTheme.accentBlue
              : theme.colorScheme.outlineVariant,
          width: isBeingEdited ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcementTypeLabel(a.type).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.accentBlue,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(a.topic, style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !busy && !sending,
                tooltip: 'Announcement actions',
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(a.message, style: theme.textTheme.bodyMedium),
          if (a.attachmentUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            TicketAttachmentsSection(attachmentUrls: a.attachmentUrls),
          ],
          const SizedBox(height: 10),
          Text(
            [
              a.audience.label,
              sending
                  ? 'Sending…'
                  : '${a.recipientCount} recipient${a.recipientCount == 1 ? '' : 's'}',
              'Sent ${fmt.format(a.createdAt)}',
              if (a.updatedAt != null) 'Edited ${fmt.format(a.updatedAt!)}',
            ].join('  ·  '),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
