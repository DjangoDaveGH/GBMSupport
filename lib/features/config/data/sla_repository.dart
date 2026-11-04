import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';

class SlaRepository {
  final FirebaseFirestore _db;

  SlaRepository(this._db);

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('config').doc('sla');

  Stream<SlaPolicy> watch() {
    return _doc.snapshots().map((doc) => SlaPolicy.fromMap(doc.data()));
  }

  // updatedBy must equal the signed-in admin (firestore.rules). The
  // onConfigWritten Cloud Function reads it to record who changed the setting.
  Future<void> update(SlaPolicy policy) => _doc.set({
    ...policy.toMap(),
    'updatedBy': FirebaseAuth.instance.currentUser?.uid,
  }, SetOptions(merge: true));
}
