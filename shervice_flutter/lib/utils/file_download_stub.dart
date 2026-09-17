import 'dart:typed_data';

Future<void> downloadFileBytes({
  required String fileName,
  required Uint8List bytes,
}) async {
  throw UnsupportedError(
    'File downloads are only supported on web or mobile platforms configured for output.',
  );
}
