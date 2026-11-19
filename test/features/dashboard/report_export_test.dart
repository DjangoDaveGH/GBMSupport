import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/features/dashboard/data/report_export.dart';
import 'package:hyport/features/dashboard/domain/report_office_export.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';

final _sections = [
  const ReportSectionData('Overview', [('Total Tickets', '42')]),
  ReportSectionData('By Officer <&> "quotes"', [
    for (var i = 0; i < 23; i++) ('Officer $i & Co', '$i resolved'),
  ]),
  const ReportSectionData('Empty', []),
];

Map<String, String> _unzip(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in archive.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>),
  };
}

void main() {
  test('docx is a zip with a document part and escaped text', () {
    final bytes = buildReportDocx(
      title: 'Summary & Co',
      subtitleLines: const ['Last 30 days'],
      sections: _sections,
    );
    final parts = _unzip(bytes);
    expect(parts.keys, contains('[Content_Types].xml'));
    expect(parts.keys, contains('word/document.xml'));
    final doc = parts['word/document.xml']!;
    expect(doc, contains('Summary &amp; Co'));
    expect(doc, contains('By Officer &lt;&amp;&gt; &quot;quotes&quot;'));
    expect(doc, isNot(contains('<&>')));
  });

  test('pptx has a title slide plus paginated section slides', () {
    final bytes = buildReportPptx(
      title: 'SLA Report',
      subtitleLines: const ['All time'],
      sections: _sections,
    );
    final parts = _unzip(bytes);
    // 1 title + Overview + Officer (23 rows -> 3 pages) + Empty = 6.
    final slides = parts.keys
        .where((k) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(k))
        .toList();
    expect(slides, hasLength(6));
    expect(parts['ppt/presentation.xml'], contains('r:id="rId8"'));
    expect(parts['ppt/slides/slide3.xml'], contains('(1/3)'));
    for (final k in [
      'ppt/theme/theme1.xml',
      'ppt/slideMasters/slideMaster1.xml',
      'ppt/slideLayouts/slideLayout1.xml',
      'ppt/slides/_rels/slide6.xml.rels',
    ]) {
      expect(parts.keys, contains(k));
    }
  });

  test('pdf starts with the PDF signature', () async {
    final bytes = await buildReportPdf('Report', const ['x'], _sections);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('ReportFormat.fromUrl reads Storage download URLs', () {
    const url =
        'https://firebasestorage.googleapis.com/v0/b/x/o/reports%2Fuid%2F1_SLA_2026.pptx?alt=media';
    expect(ReportFormat.fromUrl(url), ReportFormat.pptx);
    expect(ReportFormat.fromUrl('https://x/y.txt'), isNull);
  });

  // Writes samples for manual inspection when REPORT_SAMPLES_DIR is set.
  test('write samples', () async {
    final dir = Platform.environment['REPORT_SAMPLES_DIR'];
    if (dir == null) return;
    File('$dir/sample.docx').writeAsBytesSync(
      buildReportDocx(title: 'Sample', subtitleLines: const ['x'], sections: _sections),
    );
    File('$dir/sample.pptx').writeAsBytesSync(
      buildReportPptx(title: 'Sample', subtitleLines: const ['x'], sections: _sections),
    );
    File('$dir/sample.pdf').writeAsBytesSync(
      await buildReportPdf('Sample', const ['x'], _sections),
    );
  });
}
