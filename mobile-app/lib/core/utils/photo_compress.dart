import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Shrinks a camera photo so it can travel to the server (which accepts up to 600 KB) without eating the guard's data.
class PhotoCompress {
  PhotoCompress._();

  /// The largest result we send (the server limit is 600 KB).
  static const int maxBytes = 550000;

  /// Re-encodes [bytes] as a JPEG no wider than [maxWidth]. Returns the original bytes when they are already small
  /// enough and cannot be decoded, or null when the photo is too large and cannot be shrunk.
  static Uint8List? shrinkJpeg(Uint8List bytes, {int maxWidth = 1024, int quality = 70}) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final resized = decoded.width > maxWidth ? img.copyResize(decoded, width: maxWidth) : decoded;
        final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
        if (out.length <= maxBytes) return out;
        // Still too big (a very detailed picture): try once more, smaller and rougher
        final smaller = img.copyResize(decoded, width: 720);
        final out2 = Uint8List.fromList(img.encodeJpg(smaller, quality: 50));
        return out2.length <= maxBytes ? out2 : null;
      }
    } catch (e) {
      debugPrint('[PhotoCompress] could not shrink the photo: $e');
    }
    return bytes.length <= maxBytes ? bytes : null;
  }

  /// "data:image/jpeg;base64,...." for sending in a JSON body.
  static String toDataUrl(Uint8List jpeg) => 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}
