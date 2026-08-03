import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/data/institution_repository.dart';
import 'package:hyport/features/auth/domain/institution.dart';

final institutionRepositoryProvider = Provider<InstitutionRepository>((ref) {
  return InstitutionRepository(ref.watch(firestoreProvider));
});

final institutionListProvider = StreamProvider.autoDispose<List<Institution>>((ref) {
  return ref.watch(institutionRepositoryProvider).watchAll();
});
