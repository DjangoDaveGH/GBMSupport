import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/features/config/domain/assignment_rules.dart';

/// Reads/writes `config/assignment_rules` — the category → eligible-staff
/// map the onTicketCreated Cloud Function uses to auto-assign incoming
/// tickets. Writes are merge-only so server-owned fields (`strategy`,
/// `openStatuses`) survive an edit from the app.
class AssignmentRulesRepository {
  final FirebaseFirestore _db;

  AssignmentRulesRepository(this._db);

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('config').doc('assignment_rules');

  Stream<AssignmentRules> watch() =>
      _doc.snapshots().map((d) => AssignmentRules.fromMap(d.data()));

  Future<void> update(AssignmentRules rules) => _doc.set(
        {...rules.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}
