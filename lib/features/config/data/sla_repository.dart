import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';

class SlaRepository {
  final FirebaseFirestore _db;

  SlaRepository(this._db);

  DocumentReference<Map<String, dynamic>> get _doc => _db.collection('config').doc('sla');

  Stream<SlaPolicy> watch() {
    return _doc.snapshots().map((doc) => SlaPolicy.fromMap(doc.data()));
  }

  Future<void> update(SlaPolicy policy) => _doc.set(policy.toMap(), SetOptions(merge: true));
}
