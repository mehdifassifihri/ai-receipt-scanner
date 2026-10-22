import 'dart:typed_data';
import 'package:camera/camera.dart' show XFile;

/// Keeps the original file and image bytes for upload, review, and preview.
class ReceiptSelection {
  const ReceiptSelection({required this.file, required this.bytes});
  factory ReceiptSelection.fromBytes(Uint8List bytes) => ReceiptSelection(
    file: XFile.fromData(bytes, mimeType: 'image/jpeg', name: 'receipt.jpg'),
    bytes: bytes,
  );
  final XFile file;
  final Uint8List bytes;
}
