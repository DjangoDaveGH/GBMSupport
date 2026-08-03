import 'package:cloud_firestore/cloud_firestore.dart';

/// Self-service "Request Access" submissions (RequestAccessScreen). These
/// are NOT accounts — Section 10 still holds (no self-signup): a request
/// just lands in `access_requests` for PFM-Systems to review, who then
/// provision the real account via AddUserScreen/adminCreateUser as before.
/// There's no review/approval UI wired up yet — see DECISIONS.md.
class AccessRequestRepository {
  final FirebaseFirestore _db;

  AccessRequestRepository(this._db);

  Future<void> submit({
    required String fullName,
    required String email,
    required String phone,
    required String institutionType,
    required String institutionName,
  }) {
    return _db.collection('access_requests').add({
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'institutionType': institutionType,
      'institutionName': institutionName,
      'status': 'pending',
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }
}
