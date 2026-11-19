import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/file_saver.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/dashboard/data/report_providers.dart';
import 'package:hyport/features/dashboard/data/report_view_repository.dart';
import 'package:hyport/features/dashboard/domain/report_csv.dart';
import 'package:hyport/features/dashboard/domain/report_office_export.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// File formats a report can be downloaded in.
enum ReportFormat {
  pdf('PDF', 'pdf', 'application/pdf', Icons.picture_as_pdf_outlined),
  docx(
    'Word (.docx)',
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    Icons.article_outlined,
  ),
  pptx(
    'PowerPoint (.pptx)',
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    Icons.slideshow_outlined,
  ),
  csv('CSV', 'csv', 'text/csv', Icons.table_chart_outlined);

  final String label;
  final String extension;
  final String mimeType;
  final IconData icon;

  const ReportFormat(this.label, this.extension, this.mimeType, this.icon);

  /// Recovers the format from a stored file URL/name (Recent Reports icon).
  static ReportFormat? fromUrl(String url) {
    final path = Uri.decodeComponent(Uri.tryParse(url)?.path ?? url);
    final lower = path.toLowerCase();
    for (final f in values) {
      if (lower.endsWith('.${f.extension}')) return f;
    }
    return null;
  }
}

final reportExporterProvider = Provider<ReportExporter>((ref) {
  return ReportExporter(
    ref.watch(firebaseStorageProvider),
    ref.watch(reportViewRepositoryProvider),
  );
});

/// Builds a report file from the same [ReportSectionData] the screen shows,
/// saves it straight to the user's device (a browser download on web, the
/// save/share sheet on mobile), and keeps a copy in Storage so "Recent
/// Reports" can re-open it later. See DECISIONS.md ("Reports export").
class ReportExporter {
  final FirebaseStorage _storage;
  final ReportViewRepository _views;

  ReportExporter(this._storage, this._views);

  /// [csvRows] overrides the default CSV layout (the report's sections);
  /// the admin "tickets CSV" export uses it.
  Future<void> export({
    required ReportFormat format,
    required String uid,
    required String reportType,
    required String reportLabel,
    required List<ReportSectionData> sections,
    List<String> subtitleLines = const [],
    String? fileBaseName,
    List<List<String>>? csvRows,
  }) async {
    final generated = DateTime.now();
    final subtitle = [
      ...subtitleLines,
      'Generated ${DateFormat('d MMM yyyy, HH:mm').format(generated)}',
    ];
    final bytes = switch (format) {
      ReportFormat.pdf => await buildReportPdf(reportLabel, subtitle, sections),
      ReportFormat.docx => buildReportDocx(
        title: reportLabel,
        subtitleLines: subtitle,
        sections: sections,
      ),
      ReportFormat.pptx => buildReportPptx(
        title: reportLabel,
        subtitleLines: subtitle,
        sections: sections,
      ),
      // UTF-8 BOM so Excel reads non-ASCII names correctly.
      ReportFormat.csv => Uint8List.fromList(
        utf8.encode(
          '﻿${csvFromRows(csvRows ?? reportSectionsToRows(reportLabel, subtitleLines.isEmpty ? 'All time' : subtitleLines.join(' · '), sections))}',
        ),
      ),
    };
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(generated);
    final fileName =
        '${_slug(fileBaseName ?? reportLabel)}_$stamp.${format.extension}';

    // Start the history upload alongside the save; a failed upload must not
    // stop the user getting their file.
    final upload = _uploadAndLog(
      bytes,
      uid: uid,
      fileName: fileName,
      format: format,
      reportType: reportType,
      reportLabel: reportLabel,
    );
    await saveFileToDevice(
      bytes,
      fileName: fileName,
      mimeType: format.mimeType,
    );
    await upload;
  }

  Future<void> _uploadAndLog(
    Uint8List bytes, {
    required String uid,
    required String fileName,
    required ReportFormat format,
    required String reportType,
    required String reportLabel,
  }) async {
    try {
      final snapshot = await _storage
          .ref('reports/$uid/${DateTime.now().millisecondsSinceEpoch}_$fileName')
          .putData(bytes, SettableMetadata(contentType: format.mimeType));
      final url = await snapshot.ref.getDownloadURL();
      await _views.logView(
        viewedBy: uid,
        reportType: reportType,
        reportLabel: '$reportLabel (${format.extension.toUpperCase()})',
        pdfUrl: url,
      );
    } catch (e) {
      debugPrint('Report history upload failed: $e');
    }
  }
}

String _slug(String s) => s
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

Future<Uint8List> buildReportPdf(
  String reportLabel,
  List<String> subtitleLines,
  List<ReportSectionData> sections,
) async {
  final doc = pw.Document();
  const navy = PdfColor.fromInt(0xFF0B3578);
  const band = PdfColor.fromInt(0xFFEEF2F8);

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          reportLabel,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: navy,
          ),
        ),
        pw.SizedBox(height: 4),
        for (final line in subtitleLines)
          pw.Text(
            line,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        pw.SizedBox(height: 16),
        for (final section in sections) ...[
          pw.Text(
            section.title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Value'],
            data: section.rows.isEmpty
                ? const [
                    ['No data', ''],
                  ]
                : section.rows.map((r) => [r.$1, r.$2]).toList(),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: navy),
            oddRowDecoration: const pw.BoxDecoration(color: band),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {1: pw.Alignment.centerRight},
            headerAlignments: {1: pw.Alignment.centerRight},
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
          ),
          pw.SizedBox(height: 14),
        ],
      ],
    ),
  );

  return doc.save();
}
