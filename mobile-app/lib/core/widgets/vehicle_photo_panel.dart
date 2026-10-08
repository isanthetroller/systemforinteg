import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/ncst_theme.dart';
import 'driver_photo_view.dart';

/// A vehicle photo large enough for a guard to compare with the vehicle in front of the gate. Tap to enlarge.
/// Used for the photo on file of a registered vehicle and for the photo taken at entry of a visitor's vehicle.
class VehiclePhotoPanel extends StatelessWidget {
  final String photoData;
  final String caption;

  /// What the vehicle is (make, model, colour), shown under the caption so the guard knows what to look for.
  final String? detail;
  final double height;

  const VehiclePhotoPanel({
    super.key,
    required this.photoData,
    this.caption = 'Compare this photo with the vehicle at the gate',
    this.detail,
    this.height = 190,
  });

  /// The picture's bytes when [photoData] is a base64 string or data URL, otherwise null.
  static Uint8List? decode(String photoData) {
    var raw = photoData.trim();
    if (raw.isEmpty) return null;
    final isInline = raw.startsWith('data:image/') || raw.startsWith('/9j/') || raw.startsWith('iVBORw');
    if (!isInline) return null;
    try {
      final comma = raw.indexOf(',');
      final b64 = (comma != -1 ? raw.substring(comma + 1) : raw).trim().replaceAll(RegExp(r'\s'), '');
      return base64Decode(b64.padRight((b64.length + 3) ~/ 4 * 4, '='));
    } catch (_) {
      return null;
    }
  }

  Widget _image(double h, BoxFit fit) {
    final bytes = decode(photoData);
    if (bytes != null) {
      return Image.memory(bytes, width: double.infinity, height: h, fit: fit, errorBuilder: (_, _, _) => _missing(h));
    }
    // A file on the server or a bundled asset: the shared thumbnail widget knows how to load those
    return LayoutBuilder(
      builder: (context, box) => VehiclePhotoThumb(photoData: photoData, width: box.maxWidth.isFinite ? box.maxWidth : 340, height: h),
    );
  }

  Widget _missing(double h) => Container(
        height: h,
        color: NcstColors.slate100,
        alignment: Alignment.center,
        child: const Icon(Icons.directions_car_filled_outlined, color: NcstColors.slate400, size: 40),
      );

  void _enlarge(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: SizedBox(width: double.infinity, child: _image(420, BoxFit.contain)),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('vehiclePhotoPanel'),
      onTap: () => _enlarge(context),
      child: Container(
        decoration: BoxDecoration(
          color: NcstColors.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NcstColors.slate200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: height, child: _image(height, BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt_outlined, size: 14, color: NcstColors.navy),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caption,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: NcstColors.navy),
                        ),
                        if (detail != null && detail!.isNotEmpty)
                          Text(
                            detail!,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: NcstColors.slate700),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.zoom_out_map_rounded, size: 14, color: NcstColors.slate500),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
