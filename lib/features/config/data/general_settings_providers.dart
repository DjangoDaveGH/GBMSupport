import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/config/domain/general_settings.dart';

final generalSettingsDocProvider = Provider<DocumentReference<Map<String, dynamic>>>((ref) {
  return ref.watch(firestoreProvider).collection('config').doc('general');
});

final generalSettingsProvider = StreamProvider.autoDispose<GeneralSettings>((ref) {
  return ref.watch(generalSettingsDocProvider).snapshots().map((doc) => GeneralSettings.fromMap(doc.data()));
});

final generalSettingsRepositoryProvider = Provider<GeneralSettingsRepository>((ref) {
  return GeneralSettingsRepository(ref.watch(generalSettingsDocProvider));
});

class GeneralSettingsRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  GeneralSettingsRepository(this._doc);

  Future<void> update(GeneralSettings settings) => _doc.set(settings.toMap(), SetOptions(merge: true));

  Future<void> setLogoUrl(String url) => _doc.set({'logoUrl': url}, SetOptions(merge: true));
}
