import 'package:flutter/material.dart';
import '../../../models/vehicle_model.dart';
import '../../../theme/ncst_theme.dart';

class TestQrPresetsBar extends StatelessWidget {
  final List<VehicleRecord> presets;
  final ValueChanged<VehicleRecord> onPresetSelected;
  final VoidCallback onGuestPassSelected;

  const TestQrPresetsBar({
    super.key,
    required this.presets,
    required this.onPresetSelected,
    required this.onGuestPassSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NcstColors.white,
        border: Border(
          top: BorderSide(color: NcstColors.slate200, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(Icons.qr_code_scanner_rounded, color: NcstColors.navy, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'TEST QR PRESETS (AUTO-SCANS ON VIEW)',
                          style: TextStyle(
                            color: NcstColors.navy,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${presets.length} Presets',
                style: const TextStyle(
                  fontSize: 11,
                  color: NcstColors.slate400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...presets.map((v) {
                  final isKriz = v.ownerName.contains('Monares');
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: isKriz
                          ? const CircleAvatar(
                              radius: 10,
                              backgroundImage: AssetImage('assets/images/kriz_monares.jpg'),
                            )
                          : const Icon(Icons.qr_code, size: 15, color: NcstColors.navy),
                      label: Text(
                        isKriz
                            ? '🎓 Kriz Monares (Student • ${v.plateNumber})'
                            : '${v.plateNumber} (${v.ownerName.contains('Reyes') ? 'Prof. Reyes' : v.ownerName.replaceAll(',', '').split(' ').first})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isKriz ? NcstColors.navyDark : NcstColors.slate800,
                        ),
                      ),
                      backgroundColor: isKriz ? NcstColors.gold.withValues(alpha: 0.2) : NcstColors.slate50,
                      side: BorderSide(
                        color: isKriz ? NcstColors.gold : NcstColors.slate200,
                        width: isKriz ? 1.5 : 1,
                      ),
                      onPressed: () => onPresetSelected(v),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.qr_code_2, size: 16, color: NcstColors.navy),
                    label: const Text(
                      '⚡ NDK-4821 (QR Pass: 2 Drivers)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: NcstColors.navyDark,
                      ),
                    ),
                    backgroundColor: NcstColors.gold.withValues(alpha: 0.25),
                    side: const BorderSide(color: NcstColors.gold, width: 1.5),
                    onPressed: () {
                      final jsonMap = {
                        'ownerStudentId': 'NCST-2024-05182',
                        'ownerFullName': 'Juan C. Dela Cruz',
                        'plateNumber': 'NDK-4821',
                        'stickerYear': '2026',
                        'vehicleCategory': '4-Wheel',
                        'makeModelColor': 'White Toyota Vios',
                        'authorizedDrivers': [
                          {
                            'fullName': 'Juan C. Dela Cruz',
                            'relationship': 'Self (Owner)',
                            'licenseNo': 'N01-22-849201',
                          },
                          {
                            'fullName': 'Maria Elena Dela Cruz',
                            'relationship': 'Spouse',
                            'licenseNo': 'N02-23-441199',
                          },
                        ],
                      };
                      onPresetSelected(VehicleRecord.fromQrJson(jsonMap, rawPayload: 'QR_JSON_PAYLOAD'));
                    },
                  ),
                ),
                // Extra chip for testing blocked / unregistered visitor vehicle pass
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 15, color: NcstColors.crimson),
                    label: const Text(
                      '+ Unknown / Guest Pass',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: NcstColors.crimson,
                      ),
                    ),
                    backgroundColor: NcstColors.crimsonLight,
                    side: BorderSide(color: NcstColors.crimson.withValues(alpha: 0.3)),
                    onPressed: onGuestPassSelected,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
