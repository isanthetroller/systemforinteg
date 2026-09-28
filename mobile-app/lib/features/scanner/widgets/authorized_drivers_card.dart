import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../data/mock_data.dart';
import '../../../models/vehicle_model.dart';
import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';

class AuthorizedDriversCard extends StatelessWidget {
  final VehicleRecord vehicle;
  final String selectedDriverName;
  final VoidCallback onSelectOwner;
  final ValueChanged<AuthorizedDriver> onSelectDriver;

  const AuthorizedDriversCard({
    super.key,
    required this.vehicle,
    required this.selectedDriverName,
    required this.onSelectOwner,
    required this.onSelectDriver,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final cardPadding = EdgeInsets.all(isCompact ? 12 : 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Registered Owner Card
        Card(
          child: Padding(
            padding: cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.badge_outlined, size: 18, color: NcstColors.navy),
                          SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'REGISTERED VEHICLE OWNER',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: NcstColors.slate600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: vehicle.isSyncedWithDb
                            ? NcstColors.green.withValues(alpha: 0.12)
                            : NcstColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        vehicle.isSyncedWithDb
                            ? 'LIVE DATABASE'
                            : (vehicle.isParsedFromQr ? 'SAVED IN QR' : 'ON FILE'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: vehicle.isSyncedWithDb ? NcstColors.green : NcstColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: NcstColors.navy.withValues(alpha: 0.1),
                    backgroundImage: _resolveImage(vehicle.ownerPhotoUrl),
                    child: _resolveImage(vehicle.ownerPhotoUrl) == null
                        ? const Icon(Icons.person, color: NcstColors.navy)
                        : null,
                  ),
                  title: Text(
                    vehicle.ownerName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: NcstColors.slate900,
                    ),
                  ),
                  subtitle: Text(
                    '${vehicle.ownerRole} • ${vehicle.ownerIdNumber}',
                    style: const TextStyle(fontSize: 12, color: NcstColors.slate600),
                  ),
                  trailing: vehicle.authorizedDrivers.isEmpty
                      ? null
                      : TextButton(
                          onPressed: onSelectOwner,
                          style: TextButton.styleFrom(
                            foregroundColor: selectedDriverName == vehicle.ownerName
                                 ? NcstColors.navy
                                 : NcstColors.slate400,
                          ),
                          child: Text(
                            selectedDriverName == vehicle.ownerName ? 'Selected' : 'Select Owner',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Authorized Drivers List (Saved in QR)
        Card(
          child: Padding(
            padding: cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.group_outlined, size: 18, color: NcstColors.navy),
                          SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'AUTHORIZED DRIVERS (IF NOT OWNER)',
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: vehicle.isSyncedWithDb ? NcstColors.green : NcstColors.navy,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        vehicle.isSyncedWithDb
                            ? '${vehicle.authorizedDrivers.length} in Live DB'
                            : (vehicle.isParsedFromQr
                                ? '${vehicle.authorizedDrivers.length} in QR pass'
                                : '${vehicle.authorizedDrivers.length} Registered'),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: NcstColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select the authorized driver operating this vehicle at the gate:',
                  style: TextStyle(fontSize: 12, color: NcstColors.slate600),
                ),
                const SizedBox(height: 12),

                if (vehicle.authorizedDrivers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NcstColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'No alternate drivers registered for this vehicle.',
                        style: TextStyle(fontSize: 12, color: NcstColors.slate400),
                      ),
                    ),
                  )
                else
                  ...vehicle.authorizedDrivers.map((driver) {
                    final isSelected = selectedDriverName == driver.fullName;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isSelected ? NcstColors.navy.withValues(alpha: 0.05) : NcstColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? NcstColors.navy : NcstColors.slate200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: NcstColors.slate200,
                            backgroundImage: _resolveDriverAvatar(driver),
                            child: _resolveDriverAvatar(driver) == null
                                ? const Icon(Icons.person, size: 18, color: NcstColors.slate600)
                                : null,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  driver.fullName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? NcstColors.navy : NcstColors.slate900,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: NcstColors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '✓ IN QR',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: NcstColors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${driver.relationship} • License: ${driver.licenseNo}${driver.phone != null && driver.phone!.isNotEmpty ? ' • Tel: ${driver.phone}' : ''}',
                              style: const TextStyle(fontSize: 11, color: NcstColors.slate600),
                            ),
                          ),
                          trailing: Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? NcstColors.navy : NcstColors.slate400,
                            size: 20,
                          ),
                          onTap: () => onSelectDriver(driver),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  ImageProvider? _resolveDriverAvatar(AuthorizedDriver driver) {
    final driverImg = _resolveImage(driver.photoUrl);
    if (driverImg != null) return driverImg;
    final isOwner = driver.fullName.trim().toLowerCase() == vehicle.ownerName.trim().toLowerCase() ||
        driver.relationship.toLowerCase().contains('self') ||
        driver.relationship.toLowerCase().contains('owner');
    if (isOwner) {
      return _resolveImage(vehicle.ownerPhotoUrl);
    }
    return null;
  }

  ImageProvider? _resolveImage(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('data:image/') ||
        url.startsWith('/9j/') ||
        url.startsWith('iVBORw') ||
        (url.length > 100 && !url.startsWith('http') && !url.startsWith('assets/'))) {
      try {
        final commaIdx = url.indexOf(',');
        final base64Str = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
        final cleanBase64 = base64Str.trim().replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '+');
        final padded = cleanBase64.padRight((cleanBase64.length + 3) ~/ 4 * 4, '=');
        return MemoryImage(base64Decode(padded));
      } catch (_) {
        return null;
      }
    }

    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    final resolvedUrl = ApiConstants.resolveImageUrl(url);
    if (MockData.useNetworkImages && (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://'))) {
      return NetworkImage(resolvedUrl, headers: ApiService.imageHeaders);
    }
    return null;
  }
}
