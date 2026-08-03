import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

const otpValiditySeconds = 300;

/// Generates and checks the one-time codes used for the (self-service,
/// user-toggled) two-factor login step. Codes are generated **client-side**
/// and returned directly to the caller to display on-screen — there's no
/// email dispatch yet, since actually emailing a code needs a Cloud
/// Function (or an email-provider API called from the client, which would
/// mean shipping a secret key to every device — not acceptable). Cloud
/// Functions are blocked on the project's Blaze billing plan not being
/// active yet; see DECISIONS.md. Once that's resolved, `generate` moves
/// server-side and stops returning the code to the client at all.
class OtpRepository {
  final FirebaseFirestore _db;

  OtpRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _codes => _db.collection('otp_codes');

  Future<String> generate(String uid) async {
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    final now = DateTime.now();
    await _codes.doc(uid).set({
      'code': code,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(seconds: otpValiditySeconds))),
    });
    return code;
  }

  Future<bool> verify(String uid, String enteredCode) async {
    final doc = await _codes.doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) return false;
    if ((data['code'] as String?) != enteredCode) return false;
    await _codes.doc(uid).delete();
    return true;
  }
}
