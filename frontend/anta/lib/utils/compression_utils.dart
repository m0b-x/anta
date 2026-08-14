import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CompressionUtils {
  static Uint8List compress(String data) {
    final bytes = utf8.encode(data);
    return Uint8List.fromList(gzip.encode(bytes));
  }

  static String decompress(Uint8List compressedData) {
    final decompressed = gzip.decode(compressedData);
    return utf8.decode(decompressed);
  }

  static String compressToBase64(String data) {
    final compressed = compress(data);
    return base64Encode(compressed);
  }

  static String decompressFromBase64(String base64Data) {
    final compressed = base64Decode(base64Data);
    return decompress(Uint8List.fromList(compressed));
  }

  static double getCompressionRatio(String original, Uint8List compressed) {
    final originalSize = utf8.encode(original).length;
    final compressedSize = compressed.length;
    return compressedSize / originalSize;
  }

  static bool shouldCompress(String data, {int threshold = 1024}) {
    return utf8.encode(data).length > threshold;
  }
}
