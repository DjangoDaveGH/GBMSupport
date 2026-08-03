import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/config/data/sla_repository.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';

final slaRepositoryProvider = Provider<SlaRepository>((ref) {
  return SlaRepository(ref.watch(firestoreProvider));
});

final slaPolicyProvider = StreamProvider.autoDispose<SlaPolicy>((ref) {
  return ref.watch(slaRepositoryProvider).watch();
});
