import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/institution.dart';

class InstitutionRepository {
  final FirebaseFirestore _db;

  InstitutionRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _institutions => _db.collection('institutions');

  Stream<List<Institution>> watchAll() {
    return _institutions.orderBy('name').snapshots().map(
          (snap) => snap.docs.map((d) => Institution.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<void> create({
    required String name,
    required InstitutionType type,
  }) {
    final ref = _institutions.doc();
    return ref.set(
      Institution(id: ref.id, name: name, type: type, focalPersonIds: const []).toMap(),
    );
  }
}
