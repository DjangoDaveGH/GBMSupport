import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final reportPdfExporterProvider = Provider<ReportPdfExporter>((ref) {
  return ReportPdfExporter(ref.watch(firebaseStorageProvider));
});

/// Renders a report's sections (the same data ReportDetailScreen shows on
/// screen — see report_section_data.dart) to a PDF and uploads it to
/// Storage, so "Recent Reports" can offer a real, revisitable download
/// instead of just a view log. See DECISIONS.md ("Reports PDF export").
class ReportPdfExporter {
  final FirebaseStorage _storage;

  ReportPdfExporter(this._storage);

  Future<String> exportAndUpload({
    required String uid,
    required String reportType,
    required String reportLabel,
    required List<ReportSectionData> sections,
  }) async {
    final bytes = await _buildPdf(reportLabel, sections);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$reportType.pdf';
    final storageRef = _storage.ref('reports/$uid/$fileName');
    final snapshot = await storageRef.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    return snapshot.ref.getDownloadURL();
  }

  Future<Uint8List> _buildPdf(String reportLabel, List<ReportSectionData> sections) async {
    final doc = pw.Document();
    final generatedAt = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: reportLabel),
          pw.Text(
            'Generated ${generatedAt.toIso8601String()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),
          for (final section in sections) ...[
            pw.Header(level: 1, text: section.title),
            pw.TableHelper.fromTextArray(
              headers: const ['', ''],
              headerCount: 0,
              data: section.rows.map((r) => [r.$1, r.$2]).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {1: pw.Alignment.centerRight},
              border: null,
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4),
            ),
            pw.SizedBox(height: 12),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
