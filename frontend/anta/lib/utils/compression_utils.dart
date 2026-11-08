import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CompressionUtils {
  static Uint8List compress(String data) {
    final compressed = gzip.encode(utf8.encode(data));
    return compressed is Uint8List
        ? compressed
        : Uint8List.fromList(compressed);
  }

  static String decompress(Uint8List compressedData) {
    final decompressed = gzip.decode(compressedData);
    return utf8.decode(decompressed);
  }

  static String compressToBase64(String data) {
    return base64Encode(gzip.encode(utf8.encode(data)));
  }

  static String decompressFromBase64(String base64Data) {
    return utf8.decode(gzip.decode(base64Decode(base64Data)));
  }

  static double getCompressionRatio(String original, Uint8List compressed) {
    final originalSize = utf8.encode(original).length;
    final compressedSize = compressed.length;
    return compressedSize / originalSize;
  }

  /// Whether [data] is over [threshold] bytes in UTF-8. A code unit is one
  /// to three bytes, so only a length in between needs the encoding.
  static bool shouldCompress(String data, {int threshold = 1024}) {
    if (data.length * 3 <= threshold) return false;
    if (data.length > threshold) return true;
    return utf8.encode(data).length > threshold;
  }
}
