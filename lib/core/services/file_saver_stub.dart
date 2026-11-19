import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveFileToDevice(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}
