import 'package:flutter/material.dart';
import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/vehicle_model.dart';
import '../../../theme/ncst_theme.dart';

class ScannedPersonCard extends StatelessWidget {
  final VehicleRecord vehicle;
  final String driverName;
  final String relationship;
  final String photoUrl;

  const ScannedPersonCard({
    super.key,
    required this.vehicle,
    required this.driverName,
    required this.relationship,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, size: 18, color: NcstColors.green),
                      SizedBox(width: 6),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SCANNED QR PASS VERIFIED',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: NcstColors.slate700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NcstColors.gold,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NcstColors.goldDark.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'STICKER ${vehicle.stickerYear}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: NcstColors.navyDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Driver Photo Box
            DriverPhotoView(
              photoUrl: photoUrl,
              size: isCompact ? 160 : 190,
            ),
            const SizedBox(height: 16),

            // Driver Name
            Text(
              driverName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: NcstColors.slate900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (relationship == 'Registered Owner' || relationship.contains('Owner'))
                        ? NcstColors.navy.withValues(alpha: 0.1)
                        : NcstColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    relationship.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: (relationship == 'Registered Owner' || relationship.contains('Owner'))
                          ? NcstColors.navy
                          : NcstColors.goldDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (vehicle.isParsedFromQr)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: NcstColors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.verified, size: 12, color: NcstColors.green),
                        SizedBox(width: 3),
                        Text(
                          'IN QR PASS',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: NcstColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: NcstColors.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NcstColors.slate200),
              ),
              child: Column(
                children: [
                  Text(
                    'Registered Owner: ${vehicle.ownerName}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NcstColors.slate800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID / Student No: ${vehicle.ownerIdNumber}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: NcstColors.slate500,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 14),

            // License Plate
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Registered Plate',
                    style: TextStyle(color: NcstColors.slate600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: PlateBadge(
                    plateNumber: vehicle.plateNumber,
                    isProminent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Vehicle Type & Make Model
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Vehicle Specs',
                    style: TextStyle(color: NcstColors.slate600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        vehicle.vehicleType.toLowerCase().contains('motorcycle')
                            ? Icons.two_wheeler
                            : Icons.directions_car,
                        size: 16,
                        color: NcstColors.navy,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${vehicle.vehicleType} • ${vehicle.makeModelColor}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: NcstColors.slate800,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Attached Vehicle Picture (Saved in QR)
            if (vehicle.vehiclePicture != null && vehicle.vehiclePicture!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NcstColors.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NcstColors.slate200),
                ),
                child: Row(
                  children: [
                    VehiclePhotoThumb(
                      photoData: vehicle.vehiclePicture!,
                      width: 68,
                      height: 50,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.camera_alt_outlined, size: 12, color: NcstColors.navy),
                              SizedBox(width: 4),
                              Text(
                                'VEHICLE PHOTO IN QR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: NcstColors.navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vehicle.makeModelColor,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: NcstColors.slate700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
