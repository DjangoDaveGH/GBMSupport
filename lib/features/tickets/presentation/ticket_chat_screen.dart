import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/routing/safe_pop.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/chat_receipt.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';
import 'package:intl/intl.dart';

/// Mockup's dedicated Chat/Conversation screen — replaces the old
/// "Conversation" tab + popup-dialog comment box inside Ticket Detail with
/// a real chat UI: a header showing who you're talking to (with a live
/// online/offline dot from `AppUser.isRecentlyActive`), image-capable
/// message bubbles, and a persistent input bar.
class TicketChatScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketChatScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends ConsumerState<TicketChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  PlatformFile? _pickedImage;
  bool _sending = false;

  /// Where the viewer's own read receipt stood *before* this screen marked
  /// it forward just now — captured once, up front, so the "Unread
  /// messages" divider still has something to compare against. Null while
  /// still loading (no divider shown yet) or once there's nothing to mark
  /// (e.g. viewer unknown).
  DateTime? _readBeforeOpening;
  bool _capturedReadBefore = false;
  String? _lastMarkedReadForCommentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureAndMarkRead());
  }

  Future<void> _captureAndMarkRead() async {
    final viewer = ref.read(currentAppUserProvider).valueOrNull;
    if (viewer == null) return;
    final repo = ref.read(ticketRepositoryProvider);
    final previous = await repo.getChatReceipt(widget.ticketId, viewer.id);
    if (mounted) {
      setState(() {
        _readBeforeOpening = previous;
        _capturedReadBefore = true;
      });
    }
    await repo.markChatRead(widget.ticketId, viewer.id);
  }

  /// Called whenever the comment list changes while this screen stays open
  /// (e.g. the other party sends a message live) — keeps the receipt moving
  /// forward so ticks on *their* view of your messages update in real time,
  /// without re-touching it once per rebuild for the same latest comment.
  void _markReadIfNewComment(List<TicketActivity> comments) {
    if (comments.isEmpty) return;
    final latestId = comments.last.id;
    if (latestId == _lastMarkedReadForCommentId) return;
    _lastMarkedReadForCommentId = latestId;
    final viewer = ref.read(currentAppUserProvider).valueOrNull;
    if (viewer == null) return;
    ref.read(ticketRepositoryProvider).markChatRead(widget.ticketId, viewer.id);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() => _selectImage(ImageSource.camera);

  Future<void> _uploadMedia() => _selectImage(ImageSource.gallery);

  /// Opens the native picker directly for the requested action. Keeping the
  /// camera and gallery actions separate is important on web and mobile:
  /// neither platform guarantees that a secondary "take photo" option is
  /// exposed by a generic file-picker dialog.
  Future<void> _selectImage(ImageSource source) async {
    try {
      final xFile = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      if (!mounted) return;
      setState(() => _pickedImage = PlatformFile(name: xFile.name, size: bytes.length, bytes: bytes));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Could not open the camera. Check camera permission and try again.'
                : 'Could not open your media library. Check permission and try again.',
          ),
        ),
      );
    }
  }

  Future<String?> _uploadImage(String userId) async {
    final file = _pickedImage;
    if (file == null || file.bytes == null) return null;
    final storage = ref.read(firebaseStorageProvider);
    final storageRef = storage.ref(
      'chat/$userId/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
    );
    // storage.rules requires an image/* contentType on this path — putData
    // leaves it unset otherwise, which the rule would then reject outright.
    final snapshot = await storageRef.putData(
      file.bytes!,
      SettableMetadata(contentType: _imageContentType(file.name)),
    );
    return snapshot.ref.getDownloadURL();
  }

  String _imageContentType(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _send(AppUser viewer) async {
    final text = _textController.text.trim();
    if (text.isEmpty && _pickedImage == null) return;

    setState(() => _sending = true);
    String? attachmentUrl;
    var attachmentFailed = false;
    if (_pickedImage != null) {
      try {
        attachmentUrl = await _uploadImage(viewer.id);
      } catch (_) {
        // Storage may not be provisioned yet — send the text anyway rather
        // than blocking the whole message, same non-fatal pattern used for
        // ticket attachments elsewhere in this app.
        attachmentFailed = true;
      }
    }

    // An image-only message (no caption) whose upload just failed has
    // nothing left to send — posting anyway would write a real, permanent,
    // content-less chat bubble with no indication a picture was ever
    // intended. Bail out and let the user retry instead.
    if (attachmentFailed && text.isEmpty) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not attach the image (attachment storage isn't available yet). Add a caption or try again.")),
        );
      }
      return;
    }

    try {
      await ref.read(ticketRepositoryProvider).addComment(
            ticketId: widget.ticketId,
            actorId: viewer.id,
            note: text,
            attachmentUrl: attachmentUrl,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    _textController.clear();
    setState(() {
      _pickedImage = null;
      _sending = false;
    });
    if (attachmentFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent, but the image could not be attached (attachment storage isn\'t available yet).')),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
    final viewer = ref.watch(currentAppUserProvider).valueOrNull;

    return Scaffold(
      body: ticketAsync.when(
        loading: () => const Scaffold(body: BrandedLoaderCenter()),
        error: (e, _) => const Scaffold(body: Center(child: Text('We could not load this ticket.'))),
        data: (ticket) {
          if (ticket == null || viewer == null) return const BrandedLoaderCenter();
          return _ChatBody(
            ticket: ticket,
            viewer: viewer,
            textController: _textController,
            scrollController: _scrollController,
            pickedImage: _pickedImage,
            sending: _sending,
            onTakePhoto: _takePhoto,
            onUploadMedia: _uploadMedia,
            onRemoveImage: () => setState(() => _pickedImage = null),
            onSend: _send,
            readBeforeOpening: _readBeforeOpening,
            capturedReadBefore: _capturedReadBefore,
            onCommentsChanged: _markReadIfNewComment,
          );
        },
      ),
    );
  }
}

class _ChatBody extends ConsumerWidget {
  final Ticket ticket;
  final AppUser viewer;
  final TextEditingController textController;
  final ScrollController scrollController;
  final PlatformFile? pickedImage;
  final bool sending;
  final VoidCallback onTakePhoto;
  final VoidCallback onUploadMedia;
  final VoidCallback onRemoveImage;
  final Future<void> Function(AppUser viewer) onSend;
  /// Where the viewer's receipt stood before this screen opened — null until
  /// [capturedReadBefore] is true, then possibly still null for a
  /// never-before-opened chat (everything from the other party counts as
  /// unread).
  final DateTime? readBeforeOpening;
  final bool capturedReadBefore;
  final void Function(List<TicketActivity> comments) onCommentsChanged;

  const _ChatBody({
    required this.ticket,
    required this.viewer,
    required this.textController,
    required this.scrollController,
    required this.pickedImage,
    required this.sending,
    required this.onTakePhoto,
    required this.onUploadMedia,
    required this.onRemoveImage,
    required this.onSend,
    required this.readBeforeOpening,
    required this.capturedReadBefore,
    required this.onCommentsChanged,
  });

  /// The other party in this conversation: if the viewer is the requester,
  /// it's the assignee (may be null pre-assignment); otherwise it's always
  /// the requester.
  String? get _partnerId => viewer.id == ticket.createdBy ? ticket.assignedTo : ticket.createdBy;

  /// Once a ticket is resolved or closed, the conversation is over — the
  /// requester can still Reopen from the ticket detail screen (header menu
  /// icon) if support left something unfinished, but the chat itself stops
  /// accepting new messages so it can't turn into an unmonitored channel.
  bool get _chatClosed => ticket.status == TicketStatus.resolved || ticket.status == TicketStatus.closed;

  /// Chat alignment follows the two conversation participants, not only the
  /// exact uid of the person viewing the screen. A staff member may reply to
  /// a ticket from a different support account, and those replies must still
  /// stay on the staff side of the conversation.
  bool _isViewerSide(TicketActivity comment) {
    final isRequesterMessage = comment.actorId == ticket.createdBy;
    return viewer.role.isSupportSide ? !isRequesterMessage : isRequesterMessage;
  }

  /// Sent/Delivered/Read for one of *your own* messages, from the partner's
  /// receipt on this chat — Read implies Delivered, so it's checked first.
  _MessageStatus _statusFor(TicketActivity comment, ChatReceipt? partnerReceipt) {
    final readAt = partnerReceipt?.lastReadAt;
    if (readAt != null && !readAt.isBefore(comment.timestamp)) return _MessageStatus.read;
    final deliveredAt = partnerReceipt?.lastDeliveredAt;
    if (deliveredAt != null && !deliveredAt.isBefore(comment.timestamp)) return _MessageStatus.delivered;
    return _MessageStatus.sent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerId = _partnerId;
    // A requester can't read the assignee's users/{uid} doc (firestore.rules
    // — support-side only). Only look it up when allowed; a requester falls
    // back to the denormalized assignee name stored on the ticket.
    final canReadPartner = viewer.role.isSupportSide;
    final partnerAsync = (partnerId != null && canReadPartner) ? ref.watch(userByIdProvider(partnerId)) : null;
    final fallbackName = (partnerId != null && !canReadPartner && viewer.id == ticket.createdBy)
        ? (ticket.assignedToName ?? 'Support agent')
        : null;
    final activityAsync = ref.watch(ticketActivityProvider(ticket.id));
    final receipts = ref.watch(chatReceiptsProvider(ticket.id)).valueOrNull ?? const {};
    final partnerReceipt = partnerId != null ? receipts[partnerId] : null;

    return Scaffold(
      // Mockup screen's chat body uses a distinct muted slate background
      // (rather than this app's usual white/mist) so the message bubbles
      // stand out — deliberately different from every other screen's
      // background, same way a chat "wallpaper" reads differently from app
      // chrome in most messaging apps.
      backgroundColor: const Color(0xFFAEB6C4),
      appBar: _ChatAppBar(ticketId: ticket.id, partner: partnerAsync?.valueOrNull, fallbackName: fallbackName),
      body: Column(
        children: [
          Expanded(
            child: activityAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load messages: $e', style: const TextStyle(color: Colors.white))),
              data: (activity) {
                final comments = activity.where((a) => a.action == TicketActivityAction.commented).toList()
                  ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
                if (comments.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No messages yet. Say hello below.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scrollController.hasClients) {
                    scrollController.jumpTo(scrollController.position.maxScrollExtent);
                  }
                  onCommentsChanged(comments);
                });

                // First message from the other party that arrived after
                // where the viewer's receipt stood when this screen opened
                // — WhatsApp-style "Unread messages" divider goes right
                // before it. Nothing shown until the receipt read finishes
                // (capturedReadBefore) so it never flashes in the wrong spot.
                int? unreadDividerIndex;
                if (capturedReadBefore) {
                  for (var i = 0; i < comments.length; i++) {
                    final c = comments[i];
                    if (!_isViewerSide(c) &&
                        (readBeforeOpening == null || c.timestamp.isAfter(readBeforeOpening!))) {
                      unreadDividerIndex = i;
                      break;
                    }
                  }
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, i) {
                    final comment = comments[i];
                    final isSelf = _isViewerSide(comment);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i == unreadDividerIndex) const _UnreadDivider(),
                        _MessageBubble(
                          activity: comment,
                          isSelf: isSelf,
                          // Ticks only mean something on your own sent
                          // messages — WhatsApp never shows them on
                          // incoming ones either.
                          status: isSelf ? _statusFor(comment, partnerReceipt) : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_chatClosed)
            _ChatClosedBanner(canCreateTicket: viewer.id == ticket.createdBy)
          else
            _ChatInputBar(
              controller: textController,
              pickedImage: pickedImage,
              sending: sending,
              onTakePhoto: onTakePhoto,
              onUploadMedia: onUploadMedia,
              onRemoveImage: onRemoveImage,
              onSend: () => onSend(viewer),
            ),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String ticketId;
  final AppUser? partner;

  /// Shown when [partner] couldn't be loaded (a requester has no read access
  /// to the assignee's user doc) — the denormalized name from the ticket.
  final String? fallbackName;

  const _ChatAppBar({required this.ticketId, required this.partner, this.fallbackName});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final online = partner?.isRecentlyActive ?? false;
    final displayName = partner?.name ?? fallbackName ?? 'Support Team';
    final subtitle = partner?.role.shortLabel ?? (fallbackName != null ? 'Support agent' : 'Awaiting assignment');
    return AppBar(
      toolbarHeight: 72,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.popOrGo('/tickets'),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.navy.withValues(alpha: 0.12),
            child: displayName == 'Support Team'
                ? const Icon(Icons.support_agent_rounded, color: AppTheme.navy)
                : Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (partner != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: online ? StatusColors.resolved : Theme.of(context).colorScheme.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        online ? 'Online' : 'Offline',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Ticket details',
          onPressed: () => context.push('/tickets/$ticketId'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// WhatsApp-style separator dropped in once, right before the first message
/// from the other party that arrived since the viewer last opened this chat.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white54)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Unread messages',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const Expanded(child: Divider(color: Colors.white54)),
        ],
      ),
    );
  }
}

/// WhatsApp-style tri-state tick for one of *your own* sent messages.
/// [delivered] is set server-side (onTicketActivityCreated Cloud Function)
/// the moment it's processed the message for the partner — the best proxy
/// available for "reached their device" without a client-side delivery ack.
/// [read] is set by the partner's own client when they actually view the
/// chat and implies delivered.
enum _MessageStatus { sent, delivered, read }

class _MessageBubble extends StatelessWidget {
  final TicketActivity activity;
  final bool isSelf;
  /// Only set when [isSelf] — incoming messages never show a tick at all,
  /// same as WhatsApp.
  final _MessageStatus? status;

  const _MessageBubble({required this.activity, required this.isSelf, required this.status});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // Mockup screen shows it this way round: the *other* party's
          // messages are the navy/branded bubble, your own sent messages
          // are plain white — the reverse of the usual "your bubble is the
          // branded one" chat convention, but that's what the mockup does.
          color: isSelf ? Colors.white : AppTheme.navy,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelf ? Theme.of(context).colorScheme.outlineVariant : AppTheme.navy,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (activity.attachmentUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: CachedNetworkImage(
                  imageUrl: activity.attachmentUrl!,
                  width: 200,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const SizedBox(
                    width: 200,
                    height: 140,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => const SizedBox(
                    width: 200,
                    height: 80,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              if (activity.note != null && activity.note!.isNotEmpty) const SizedBox(height: 8),
            ],
            if (activity.note != null && activity.note!.isNotEmpty)
              Text(
                activity.note!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isSelf ? AppTheme.ink : Colors.white,
                    ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(activity.timestamp),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelf ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.white70,
                      ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    status == _MessageStatus.sent ? Icons.done_rounded : Icons.done_all_rounded,
                    size: 15,
                    color: status == _MessageStatus.read
                        ? AppTheme.accentBlue
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces the input bar once [TicketChatScreen] considers the chat closed
/// (ticket resolved/closed) — tells the requester to raise a new ticket
/// instead of continuing an unmonitored conversation; the other party just
/// sees that the conversation has ended.
class _ChatClosedBanner extends StatelessWidget {
  final bool canCreateTicket;

  const _ChatClosedBanner({required this.canCreateTicket});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canCreateTicket
                        ? 'This ticket has been resolved and the chat is now closed. Need more help? Open a new ticket.'
                        : 'This ticket has been resolved and the chat is now closed.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            if (canCreateTicket) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push('/tickets/new'),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Open a new ticket'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final PlatformFile? pickedImage;
  final bool sending;
  final VoidCallback onTakePhoto;
  final VoidCallback onUploadMedia;
  final VoidCallback onRemoveImage;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.controller,
    required this.pickedImage,
    required this.sending,
    required this.onTakePhoto,
    required this.onUploadMedia,
    required this.onRemoveImage,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pickedImage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.image_outlined, size: 16),
                  label: Text(pickedImage!.name, overflow: TextOverflow.ellipsis),
                  onDeleted: onRemoveImage,
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_camera_outlined),
                  color: AppTheme.accentBlue,
                  tooltip: 'Take photo',
                  onPressed: sending ? null : onTakePhoto,
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  color: AppTheme.accentBlue,
                  tooltip: 'Upload media',
                  onPressed: sending ? null : onUploadMedia,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppTheme.navy,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: sending ? null : onSend,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
