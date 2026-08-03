import 'package:cloud_firestore/cloud_firestore.dart';

class ReportView {
  final String id;
  final String reportType;
  final String reportLabel;
  final String viewedBy;
  final DateTime viewedAt;

  const ReportView({
    required this.id,
    required this.reportType,
    required this.reportLabel,
    required this.viewedBy,
    required this.viewedAt,
  });

  factory ReportView.fromMap(String id, Map<String, dynamic> map) {
    return ReportView(
      id: id,
      reportType: map['reportType'] as String? ?? '',
      reportLabel: map['reportLabel'] as String? ?? '',
      viewedBy: map['viewedBy'] as String? ?? '',
      viewedAt: (map['viewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'reportType': reportType,
        'reportLabel': reportLabel,
        'viewedBy': viewedBy,
        'viewedAt': FieldValue.serverTimestamp(),
      };
}
