import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/admin/domain/announcement.dart';

/// Most files an announcement can carry. Must match
/// MAX_ANNOUNCEMENT_ATTACHMENTS in functions/index.js.
const maxAnnouncementAttachments = 10;

/// Per-file limit. Must stay under storage.rules' 15 MB.
const maxAnnouncementFileBytes = 10 * 1024 * 1024;

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return AnnouncementRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
    FirebaseFunctions.instance,
  );
});

final announcementsProvider = StreamProvider.autoDispose<List<Announcement>>((
  ref,
) {
  return ref.watch(announcementRepositoryProvider).watchAll();
});

/// Create, list, edit and delete announcements. Writes go through Cloud
/// Functions (see functions/index.js); only attachment uploads go straight
/// to Storage, under `announcements/{id}/`.
class AnnouncementRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  AnnouncementRepository(this._db, this._storage, this._functions);

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('announcements');

  Stream<List<Announcement>> watchAll({int limit = 50}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => Announcement.fromMap(d.id, d.data()))
            .toList(),
      );

  /// A fresh id, so attachments can be uploaded into the announcement's
  /// folder before it is sent.
  String newId() => _col.doc().id;

  Future<String> uploadAttachment({
    required String announcementId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[\\/#?]'), '_');
    final ref = _storage.ref(
      'announcements/$announcementId/${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    final snapshot = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return snapshot.ref.getDownloadURL();
  }

  /// Best-effort removal of a file uploaded for an announcement that hasn't
  /// been sent yet (the admin removed it from the draft).
  Future<void> deleteUnsentAttachment(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
  );

  /// Returns how many users it was sent to.
  Future<int> send({
    required String announcementId,
    required NotificationType type,
    required String topic,
    required String message,
    required AnnouncementAudience audience,
    required List<String> attachmentUrls,
  }) async {
    final result = await _callable('adminBroadcastNotification').call({
      'announcementId': announcementId,
      'type': type.wireValue,
      'topic': topic,
      'message': message,
      'audience': audience.wireValue,
      'attachmentUrls': attachmentUrls,
    });
    return (result.data as Map)['sent'] as int? ?? 0;
  }

  Future<void> update({
    required String announcementId,
    required NotificationType type,
    required String topic,
    required String message,
    required List<String> attachmentUrls,
  }) => _callable('adminUpdateAnnouncement').call({
    'announcementId': announcementId,
    'type': type.wireValue,
    'topic': topic,
    'message': message,
    'attachmentUrls': attachmentUrls,
  });

  Future<void> delete(String announcementId) => _callable(
    'adminDeleteAnnouncement',
  ).call({'announcementId': announcementId});
}
