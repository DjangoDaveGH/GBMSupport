import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/offline/connectivity_provider.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';

/// Wraps the app; when connectivity returns and a user is signed in, pushes
/// any locally-queued draft tickets (created while offline) into Firestore
/// and removes them from the local queue. See DraftTicketRepository and
/// Section 6 of the project brief ("Offline and low-bandwidth support").
class OfflineSyncListener extends ConsumerStatefulWidget {
  final Widget child;

  const OfflineSyncListener({super.key, required this.child});

  @override
  ConsumerState<OfflineSyncListener> createState() => _OfflineSyncListenerState();
}

class _OfflineSyncListenerState extends ConsumerState<OfflineSyncListener> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_trySync);
  }

  Future<void> _trySync() async {
    if (_syncing) return;
    final user = ref.read(currentAppUserProvider).valueOrNull;
    if (user == null) return;
    _syncing = true;
    try {
      final draftRepo = ref.read(draftTicketRepositoryProvider);
      final ticketRepo = ref.read(ticketRepositoryProvider);
      final pending = draftRepo.getAllForUser(user.id).where((d) => d.pendingSync).toList();
      for (final draft in pending) {
        try {
          await ticketRepo.createTicket(
            createdBy: draft.createdBy,
            institutionId: draft.institutionId,
            category: draft.category,
            subCategory: draft.subCategory,
            title: draft.title,
            description: draft.description,
            attachmentUrls: const [], // local attachments are uploaded separately, see DECISIONS.md
            priority: draft.priority,
            impact: draft.impact,
            affectsMultipleUsers: draft.affectsMultipleUsers,
          );
          await draftRepo.delete(draft.localId);
        } catch (_) {
          // Leave this draft queued; it will be retried on the next
          // reconnect/rebuild rather than surfacing a transient failure.
        }
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isOnlineProvider, (previous, next) {
      if (next.valueOrNull == true) _trySync();
    });
    ref.listen(currentAppUserProvider, (previous, next) {
      if (next.valueOrNull != null) _trySync();
    });
    return widget.child;
  }
}
