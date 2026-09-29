import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

/// Attachment kind, derived from the file extension, used to decide which
/// in-app viewer (if any) [AttachmentViewerScreen] renders for a given URL.
enum AttachmentKind { image, pdf, text, other }

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'};
const _textExtensions = {'txt', 'log', 'csv', 'md'};

/// Firebase Storage download URLs percent-encode the full object path into
/// a single path segment (`.../o/attachments%2F{uid}%2F{millis}_{name}`),
/// and `new_ticket_screen.dart`'s upload prefixes the original filename with
/// a millisecond timestamp to avoid collisions. This recovers the original,
/// human-readable filename for display/download.
String attachmentFileName(String url) {
  try {
    final uri = Uri.parse(url);
    final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final decoded = Uri.decodeComponent(lastSegment);
    final base = decoded.split('/').last;
    final withoutTimestamp = RegExp(r'^\d{10,}_(.+)$').firstMatch(base);
    final name = withoutTimestamp != null ? withoutTimestamp.group(1)! : base;
    return name.isEmpty ? 'attachment' : name;
  } catch (_) {
    return 'attachment';
  }
}

String attachmentExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

AttachmentKind attachmentKind(String fileName) {
  final ext = attachmentExtension(fileName);
  if (_imageExtensions.contains(ext)) return AttachmentKind.image;
  if (ext == 'pdf') return AttachmentKind.pdf;
  if (_textExtensions.contains(ext)) return AttachmentKind.text;
  return AttachmentKind.other;
}

IconData attachmentIcon(String fileName) {
  switch (attachmentKind(fileName)) {
    case AttachmentKind.image:
      return Icons.image_outlined;
    case AttachmentKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case AttachmentKind.text:
      return Icons.description_outlined;
    case AttachmentKind.other:
      final ext = attachmentExtension(fileName);
      if (['doc', 'docx'].contains(ext)) return Icons.article_outlined;
      if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
      if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_outlined;
      if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_outlined;
      return Icons.insert_drive_file_outlined;
  }
}

/// Fetches the attachment's bytes and hands them to the OS share sheet
/// (Save to Files/Photos on iOS, Downloads/Drive on Android, a real browser
/// download on web) so the user ends up with a copy on their device,
/// regardless of platform — separate from [AttachmentViewerScreen]'s in-app
/// preview, which never leaves the app.
Future<void> downloadAttachment(BuildContext context, String url) async {
  final fileName = attachmentFileName(url);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('server returned ${response.statusCode}');
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(response.bodyBytes)],
        fileNameOverrides: [fileName],
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not download "$fileName": $e')));
  }
}
