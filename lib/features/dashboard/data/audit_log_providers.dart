import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/dashboard/data/audit_log_repository.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(ref.watch(firestoreProvider));
});

final auditLogProvider = StreamProvider.autoDispose<List<TicketActivity>>((ref) {
  return ref.watch(auditLogRepositoryProvider).watchRecent();
});
