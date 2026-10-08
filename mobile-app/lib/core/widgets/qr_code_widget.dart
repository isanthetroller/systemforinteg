import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/ncst_theme.dart';

/// A standard, scannable QR code (ISO 18004) for [data]. The version grows with the amount of data, and the error
/// correction is "medium" like the QR codes of the web portals, so a code shown here reads the same as one shown there.
class QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;
  final bool showBorder;

  const QrCodeWidget({
    super.key,
    required this.data,
    this.size = 200,
    this.foregroundColor = NcstColors.navyDark,
    this.backgroundColor = Colors.white,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: showBorder ? Border.all(color: NcstColors.slate200, width: 1.5) : null,
      ),
      padding: EdgeInsets.all(size * 0.05),
      child: QrImageView(
        key: const Key('realQrCode'),
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        backgroundColor: backgroundColor,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: foregroundColor),
        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: foregroundColor),
        padding: EdgeInsets.zero,
        gapless: true,
      ),
    );
  }
}
