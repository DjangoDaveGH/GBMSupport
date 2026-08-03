import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/features/dashboard/domain/report_view.dart';

/// Reports are computed live from ticket data, not exported/stored files
/// (no Firebase Storage yet — see DECISIONS.md), so this just logs which
/// report a given admin looked at recently for the "Recent Reports"
/// section, scoped strictly to that admin.
class ReportViewRepository {
  final FirebaseFirestore _db;

  ReportViewRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _views => _db.collection('report_views');

  Future<void> logView({
    required String viewedBy,
    required String reportType,
    required String reportLabel,
  }) {
    final ref = _views.doc();
    return ref.set(
      ReportView(id: ref.id, reportType: reportType, reportLabel: reportLabel, viewedBy: viewedBy, viewedAt: DateTime.now())
          .toMap(),
    );
  }

  Stream<List<ReportView>> watchRecent(String uid, {int limit = 5}) {
    return _views
        .where('viewedBy', isEqualTo: uid)
        .orderBy('viewedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ReportView.fromMap(d.id, d.data())).toList());
  }
}
