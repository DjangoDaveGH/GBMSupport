import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:hyport/features/dashboard/domain/report_section_data.dart';

/// Minimal Word (.docx) and PowerPoint (.pptx) builders for report
/// downloads. Both formats are zipped XML (Office Open XML), so they're
/// generated here with `archive` rather than adding a heavy dependency.
/// Content is the same [ReportSectionData] the screen and PDF use.

const _navy = '0B3578';
const _gold = 'F2B705';
const _band = 'EEF2F8';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final e in parts.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

// ---------------------------------------------------------------- DOCX ----

Uint8List buildReportDocx({
  required String title,
  required List<String> subtitleLines,
  required List<ReportSectionData> sections,
}) {
  String run(String text, {bool bold = false, int? halfPts, String? color}) {
    final props = [
      if (bold) '<w:b/>',
      if (color != null) '<w:color w:val="$color"/>',
      if (halfPts != null) '<w:sz w:val="$halfPts"/>',
    ].join();
    return '<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}'
        '<w:t xml:space="preserve">${_x(text)}</w:t></w:r>';
  }

  String para(
    String runs, {
    String? style,
    String? align,
    int after = 120,
    bool keepNext = false,
  }) =>
      '<w:p><w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
      '${keepNext ? '<w:keepNext/>' : ''}'
      '<w:spacing w:after="$after"/>'
      '${align == null ? '' : '<w:jc w:val="$align"/>'}</w:pPr>$runs</w:p>';

  String cell(String text, {bool bold = false, String? fill, String? align}) =>
      '<w:tc><w:tcPr><w:tcW w:w="4500" w:type="dxa"/>'
      '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
      '</w:tcPr>${para(run(text, bold: bold, color: fill == _navy ? 'FFFFFF' : null), align: align, after: 0)}</w:tc>';

  final body = StringBuffer()
    ..write(para(run(title, bold: true, halfPts: 36, color: _navy)))
    ..writeAll(
      subtitleLines.map((l) => para(run(l, halfPts: 18, color: '666666'))),
    );

  for (final s in sections) {
    body.write(
      para(
        run(s.title, bold: true, halfPts: 26, color: _navy),
        after: 80,
        keepNext: true,
      ),
    );
    const border = 'w:val="single" w:sz="4" w:space="0" w:color="C9D3E3"';
    body.write(
      '<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/>'
      '<w:tblBorders><w:top $border/><w:left $border/><w:bottom $border/>'
      '<w:right $border/><w:insideH $border/><w:insideV $border/></w:tblBorders>'
      '<w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="100" w:type="dxa"/>'
      '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar>'
      '</w:tblPr><w:tblGrid><w:gridCol w:w="4500"/><w:gridCol w:w="4500"/></w:tblGrid>'
      '<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>${cell('Item', bold: true, fill: _navy)}'
      '${cell('Value', bold: true, fill: _navy, align: 'right')}</w:tr>',
    );
    var i = 0;
    for (final (label, value) in s.rows) {
      final fill = (i++).isOdd ? _band : null;
      body.write(
        '<w:tr>${cell(label, fill: fill)}${cell(value, fill: fill, align: 'right')}</w:tr>',
      );
    }
    if (s.rows.isEmpty) {
      body.write('<w:tr>${cell('No data')}${cell('')}</w:tr>');
    }
    body.write('</w:tbl>${para('', after: 200)}');
  }

  return _zip({
    '[Content_Types].xml':
        '$_xmlHead<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>',
    '_rels/.rels':
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/document.xml':
        '$_xmlHead<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1200" w:right="1200" w:bottom="1200" w:left="1200" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>',
  });
}

// ---------------------------------------------------------------- PPTX ----

const _pptRowsPerSlide = 10;
const _slideW = 12192000;
const _slideH = 6858000;
const _nsP =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const _emptyTree =
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

String _textBox(
  int id,
  String text, {
  required int x,
  required int y,
  required int cx,
  required int cy,
  int size = 1800,
  bool bold = false,
  String color = '333333',
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
    '<p:txBody><a:bodyPr wrap="square" rtlCol="0"/><a:lstStyle/><a:p><a:r>'
    '<a:rPr lang="en-US" sz="$size"${bold ? ' b="1"' : ''} dirty="0">'
    '<a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr>'
    '<a:t>${_x(text)}</a:t></a:r></a:p></p:txBody></p:sp>';

String _bar(int id, {required int y, required int cy, required String color}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Bar $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="0" y="$y"/><a:ext cx="$_slideW" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
    '<a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';

String _tableCell(String text, {bool bold = false, String? fill, bool right = false}) =>
    '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>'
    '${right ? '<a:pPr algn="r"/>' : ''}'
    '${text.isEmpty ? '<a:endParaRPr lang="en-US" sz="1400"/>' : '<a:r><a:rPr lang="en-US" sz="1400"${bold ? ' b="1"' : ''} dirty="0">'
              '<a:solidFill><a:srgbClr val="${fill == _navy ? 'FFFFFF' : '222222'}"/></a:solidFill></a:rPr>'
              '<a:t>${_x(text)}</a:t></a:r>'}'
    '</a:p></a:txBody><a:tcPr>'
    '${fill == null ? '<a:noFill/>' : '<a:solidFill><a:srgbClr val="$fill"/></a:solidFill>'}'
    '</a:tcPr></a:tc>';

String _slide(String shapes) =>
    '$_xmlHead<p:sld $_nsP><p:cSld><p:spTree>$_emptyTree$shapes</p:spTree></p:cSld>'
    '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';

Uint8List buildReportPptx({
  required String title,
  required List<String> subtitleLines,
  required List<ReportSectionData> sections,
}) {
  final slides = <String>[];

  // Title slide.
  slides.add(
    _slide(
      _bar(2, y: 0, cy: _slideH, color: _navy) +
          _bar(3, y: 3900000, cy: 60000, color: _gold) +
          _textBox(4, title, x: 700000, y: 2300000, cx: 10800000, cy: 1300000,
              size: 4000, bold: true, color: 'FFFFFF') +
          _textBox(5, subtitleLines.join('  ·  '), x: 700000, y: 4100000,
              cx: 10800000, cy: 800000, size: 1600, color: 'DCE4F2'),
    ),
  );

  // One slide per section, paginated so long tables (e.g. many officers)
  // don't run off the bottom of the slide.
  for (final s in sections) {
    final rows = s.rows.isEmpty ? [('No data', '')] : s.rows;
    final pages = (rows.length / _pptRowsPerSlide).ceil();
    for (var p = 0; p < pages; p++) {
      final chunk = rows.skip(p * _pptRowsPerSlide).take(_pptRowsPerSlide);
      final heading = pages > 1 ? '${s.title} (${p + 1}/$pages)' : s.title;
      const rowH = 400000;
      final tableRows = StringBuffer(
        '<a:tr h="$rowH">${_tableCell('Item', bold: true, fill: _navy)}'
        '${_tableCell('Value', bold: true, fill: _navy, right: true)}</a:tr>',
      );
      var i = 0;
      for (final (label, value) in chunk) {
        final fill = (i++).isOdd ? _band : null;
        tableRows.write(
          '<a:tr h="$rowH">${_tableCell(label, fill: fill)}'
          '${_tableCell(value, fill: fill, right: true)}</a:tr>',
        );
      }
      final table =
          '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="6" name="Table"/>'
          '<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
          '<p:xfrm><a:off x="700000" y="1500000"/><a:ext cx="10800000" cy="${rowH * (i + 1)}"/></p:xfrm>'
          '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
          '<a:tbl><a:tblPr firstRow="1" bandRow="1"/><a:tblGrid><a:gridCol w="7200000"/><a:gridCol w="3600000"/></a:tblGrid>'
          '$tableRows</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
      slides.add(
        _slide(
          _bar(2, y: 0, cy: 1100000, color: _navy) +
              _bar(3, y: 1100000, cy: 40000, color: _gold) +
              _textBox(4, heading, x: 700000, y: 250000, cx: 9000000,
                  cy: 650000, size: 2600, bold: true, color: 'FFFFFF') +
              _textBox(5, title, x: 700000, y: 6250000, cx: 10800000,
                  cy: 400000, size: 1000, color: '888888') +
              table,
        ),
      );
    }
  }

  final parts = <String, String>{
    '[Content_Types].xml':
        '$_xmlHead<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '${[for (var i = 1; i <= slides.length; i++) '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'].join()}'
        '</Types>',
    '_rels/.rels':
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '</Relationships>',
    'ppt/presentation.xml':
        '$_xmlHead<p:presentation $_nsP saveSubsetFonts="1">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>${[for (var i = 1; i <= slides.length; i++) '<p:sldId id="${255 + i}" r:id="rId${i + 2}"/>'].join()}</p:sldIdLst>'
        '<p:sldSz cx="$_slideW" cy="$_slideH"/><p:notesSz cx="6858000" cy="9144000"/>'
        '</p:presentation>',
    'ppt/_rels/presentation.xml.rels':
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
        '${[for (var i = 1; i <= slides.length; i++) '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>'].join()}'
        '</Relationships>',
    'ppt/slideMasters/slideMaster1.xml':
        '$_xmlHead<p:sldMaster $_nsP><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
        '<p:spTree>$_emptyTree</p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" '
        'accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>',
    'ppt/slideMasters/_rels/slideMaster1.xml.rels':
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
        '</Relationships>',
    'ppt/slideLayouts/slideLayout1.xml':
        '$_xmlHead<p:sldLayout $_nsP type="blank" preserve="1"><p:cSld name="Blank">'
        '<p:spTree>$_emptyTree</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>',
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels':
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>',
    'ppt/theme/theme1.xml': _theme,
  };
  for (var i = 0; i < slides.length; i++) {
    parts['ppt/slides/slide${i + 1}.xml'] = slides[i];
    parts['ppt/slides/_rels/slide${i + 1}.xml.rels'] =
        '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '</Relationships>';
  }
  return _zip(parts);
}

const _fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
const _line =
    '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>';
const _effect = '<a:effectStyle><a:effectLst/></a:effectStyle>';

const _theme =
    '$_xmlHead<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Hyport">'
    '<a:themeElements><a:clrScheme name="Hyport">'
    '<a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="$_navy"/></a:dk2><a:lt2><a:srgbClr val="$_band"/></a:lt2>'
    '<a:accent1><a:srgbClr val="$_navy"/></a:accent1><a:accent2><a:srgbClr val="$_gold"/></a:accent2>'
    '<a:accent3><a:srgbClr val="1E5BB8"/></a:accent3><a:accent4><a:srgbClr val="2E9E5B"/></a:accent4>'
    '<a:accent5><a:srgbClr val="D9534F"/></a:accent5><a:accent6><a:srgbClr val="7A7A7A"/></a:accent6>'
    '<a:hlink><a:srgbClr val="1E5BB8"/></a:hlink><a:folHlink><a:srgbClr val="6B4FA0"/></a:folHlink>'
    '</a:clrScheme><a:fontScheme name="Hyport">'
    '<a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
    '</a:fontScheme><a:fmtScheme name="Hyport">'
    '<a:fillStyleLst>$_fill$_fill$_fill</a:fillStyleLst>'
    '<a:lnStyleLst>$_line$_line$_line</a:lnStyleLst>'
    '<a:effectStyleLst>$_effect$_effect$_effect</a:effectStyleLst>'
    '<a:bgFillStyleLst>$_fill$_fill$_fill</a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>';
