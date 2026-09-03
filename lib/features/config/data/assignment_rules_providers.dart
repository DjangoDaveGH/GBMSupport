import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/config/data/assignment_rules_repository.dart';
import 'package:hyport/features/config/domain/assignment_rules.dart';

final assignmentRulesRepositoryProvider = Provider<AssignmentRulesRepository>((ref) {
  return AssignmentRulesRepository(ref.watch(firestoreProvider));
});

final assignmentRulesProvider = StreamProvider.autoDispose<AssignmentRules>((ref) {
  return ref.watch(assignmentRulesRepositoryProvider).watch();
});
