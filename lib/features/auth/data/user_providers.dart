import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/data/user_repository.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(firestoreProvider));
});

final assignableUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAssignableUsers();
});

final allUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAllUsers();
});

final userByIdProvider = StreamProvider.autoDispose.family<AppUser?, String>((ref, userId) {
  return ref.watch(userRepositoryProvider).watchUserById(userId);
});
