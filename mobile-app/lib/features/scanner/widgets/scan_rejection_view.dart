import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/scanned_visitor_pass.dart';
import '../../../models/vehicle_model.dart';
import '../../../theme/ncst_theme.dart';
import 'scan_notice_strip.dart';

enum ScanRejectionType {
  blocked,
  duplicateEntry,
  duplicateExit,
  notFound,
  invalidQr,
  networkError,
  unknown,
}

class ScanRejectionDetails {
  final ScanRejectionType type;
  final String title;
  final String message;
  final String resolutionInstructions;
  final VehicleRecord? vehicle;
  final ScannedVisitorPass? visitor;
  final String? rawQr;
  final String? plateNumber;
  final String? ownerName;
  final String? statusBadge;
  final String? reason;

  /// Parking nearly full, which case holds the vehicle, ... (from the server's verify answer)
  final List<ScanNotice> notices;

  ScanRejectionDetails({
    required this.type,
    required this.title,
    required this.message,
    String? resolutionInstructions,
    this.vehicle,
    this.visitor,
    this.rawQr,
    this.plateNumber,
    this.ownerName,
    this.statusBadge,
    this.reason,
    this.notices = const [],
  }) : resolutionInstructions = resolutionInstructions ??
            (type == ScanRejectionType.blocked
                ? 'The vehicle owner must resolve all issues with administration before the vehicle can proceed.'
                : (type == ScanRejectionType.duplicateEntry
                    ? 'Vehicle is already recorded as inside campus. It must exit through Guard 2 before another entry can be recorded.'
                    : (type == ScanRejectionType.duplicateExit
                        ? 'Vehicle has already exited or has no active campus entry record. Vehicle must enter through Guard 1.'
                        : (type == ScanRejectionType.networkError
                            ? 'Check the device internet connection or contact system administrator.'
                            : 'Ensure a valid campus pass or registered vehicle QR is scanned.'))));

  bool get isBlocked => type == ScanRejectionType.blocked;
  bool get isDuplicate =>
      type == ScanRejectionType.duplicateEntry ||
      type == ScanRejectionType.duplicateExit;
}

/// Dedicated, non-overridable UI feedback for rejected QR scans.
/// Communicates clearly why the vehicle cannot proceed and provides
/// a safe reset action to scan another pass or vehicle.
class ScanRejectionView extends StatelessWidget {
  final ScanRejectionDetails details;
  final VoidCallback onScanAnother;
  final VoidCallback? onInspect;
  final VoidCallback? onIssueViolation;
  final String? buttonLabel;
  final String? inspectButtonLabel;

  const ScanRejectionView({
    super.key,
    required this.details,
    required this.onScanAnother,
    this.onInspect,
    this.onIssueViolation,
    this.buttonLabel,
    this.inspectButtonLabel,
  });

  Color get _headerColor {
    switch (details.type) {
      case ScanRejectionType.blocked:
      case ScanRejectionType.networkError:
        return NcstColors.crimson;
      case ScanRejectionType.duplicateEntry:
      case ScanRejectionType.duplicateExit:
        return NcstColors.goldDark;
      case ScanRejectionType.notFound:
      case ScanRejectionType.invalidQr:
      case ScanRejectionType.unknown:
        return NcstColors.slate700;
    }
  }

  IconData get _headerIcon {
    switch (details.type) {
      case ScanRejectionType.blocked:
        return Icons.block_rounded;
      case ScanRejectionType.duplicateEntry:
      case ScanRejectionType.duplicateExit:
        return Icons.history_toggle_off_rounded;
      case ScanRejectionType.networkError:
        return Icons.wifi_off_rounded;
      case ScanRejectionType.notFound:
      case ScanRejectionType.invalidQr:
      case ScanRejectionType.unknown:
        return Icons.help_outline_rounded;
    }
  }

  String get _badgeText {
    switch (details.type) {
      case ScanRejectionType.blocked:
        return 'ACCESS DENIED';
      case ScanRejectionType.duplicateEntry:
        return 'ANTI-PASSBACK ALERT';
      case ScanRejectionType.duplicateExit:
        return 'EGRESS DENIED';
      case ScanRejectionType.networkError:
        return 'OFFLINE / TIMEOUT';
      case ScanRejectionType.notFound:
      case ScanRejectionType.invalidQr:
      case ScanRejectionType.unknown:
        return 'INVALID PASS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = details.vehicle;
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _headerColor.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Color Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  color: _headerColor,
                  child: Row(
                    children: [
                      Icon(_headerIcon, color: NcstColors.white, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          details.title,
                          style: const TextStyle(
                            color: NcstColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: NcstColors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _badgeText,
                          style: const TextStyle(
                            color: NcstColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: EdgeInsets.all(isCompact ? 14 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ScanNoticeStrip(notices: details.notices),
                      // Prominent Notice Container
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: details.isBlocked
                              ? NcstColors.crimsonLight
                              : (details.isDuplicate
                                  ? const Color(0xFFFEF3C7)
                                  : NcstColors.slate100),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _headerColor,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  details.isBlocked
                                      ? Icons.gpp_bad_rounded
                                      : (details.isDuplicate
                                          ? Icons.warning_amber_rounded
                                          : Icons.info_outline_rounded),
                                  color: _headerColor,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    details.message,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: details.isBlocked
                                          ? NcstColors.crimson
                                          : (details.isDuplicate
                                              ? const Color(0xFF92400E)
                                              : NcstColors.slate800),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (details.resolutionInstructions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(left: 30),
                                child: Text(
                                  details.resolutionInstructions,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: details.isBlocked
                                        ? NcstColors.crimson
                                        : NcstColors.slate700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Vehicle identification section if record was resolved
                      if (vehicle != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PlateBadge(
                              plateNumber: vehicle.plateNumber,
                              isProminent: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          vehicle.makeModelColor,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: NcstColors.slate800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Owner: ${vehicle.ownerName} • ${vehicle.categoryDisplay}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: NcstColors.slate600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (vehicle.campusStatus != null &&
                            vehicle.campusStatus!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: NcstColors.slate200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Database State: ${vehicle.campusStatus}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: NcstColors.slate800,
                              ),
                            ),
                          ),
                        ],
                        if (vehicle.ownerPhotoUrl != null &&
                            vehicle.ownerPhotoUrl!.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          DriverPhotoView(
                            photoUrl: vehicle.ownerPhotoUrl!,
                            size: 110,
                          ),
                        ],
                        const SizedBox(height: 20),
                      ] else if (details.plateNumber != null || details.ownerName != null || details.statusBadge != null) ...[
                        if (details.plateNumber != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PlateBadge(
                                plateNumber: details.plateNumber!,
                                isProminent: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (details.ownerName != null) ...[
                          Text(
                            details.ownerName!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: NcstColors.slate800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (details.statusBadge != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: NcstColors.slate200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Database State: ${details.statusBadge}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: NcstColors.slate800,
                              ),
                            ),
                          ),
                        ],
                        if (details.reason != null && details.reason!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            details.reason!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: NcstColors.slate600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                      ] else ...[
                        const SizedBox(height: 12),
                      ],

                      // A vehicle that is already inside: who it belongs to and how to reach them
                      if (vehicle != null && details.type == ScanRejectionType.duplicateEntry) ...[
                        OnCampusDetailsCard(vehicle: vehicle),
                        const SizedBox(height: 16),
                      ],

                      // Optional In-Campus Patrol Inspection / Incident Action Button
                      if (onInspect != null) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: onInspect,
                            icon: const Icon(Icons.shield_outlined, size: 20),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                inspectButtonLabel ?? 'INSPECT ON-CAMPUS VEHICLE / REPORT INCIDENT',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NcstColors.crimson,
                              foregroundColor: NcstColors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (onIssueViolation != null) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            key: const Key('issueViolationButton'),
                            onPressed: onIssueViolation,
                            icon: const Icon(Icons.gavel_rounded, size: 20),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'ISSUE VIOLATION',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NcstColors.crimson,
                              side: const BorderSide(color: NcstColors.crimson, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Primary Safe Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: onScanAnother,
                          icon: const Icon(Icons.qr_code_scanner, size: 20),
                          label: Text(
                            buttonLabel ?? 'SCAN ANOTHER VEHICLE',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NcstColors.navy,
                            foregroundColor: NcstColors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full details of a vehicle that is already on campus: owner, how to contact them, the vehicle, who drove it in
/// and when, and the authorized drivers. Shown when the entry guard scans a vehicle that is already inside.
class OnCampusDetailsCard extends StatelessWidget {
  final VehicleRecord vehicle;

  const OnCampusDetailsCard({super.key, required this.vehicle});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String formatTime(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '${_months[t.month - 1]} ${t.day}, $hour12:$minute ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget _row(String label, String value, {Widget? trailing, bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: NcstColors.slate500)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: strong ? 15 : 13,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: NcstColors.slate800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = vehicle.ownerPhone;
    final since = vehicle.onCampusSince;
    final hours = vehicle.hoursInside;
    final drivers = vehicle.authorizedDrivers.where((d) => d.fullName.trim().isNotEmpty).toList();

    return Container(
      key: const Key('onCampusDetails'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NcstColors.slate100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NcstColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VEHICLE ON CAMPUS • CONTACT & DETAILS',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: NcstColors.navy),
          ),
          const SizedBox(height: 8),
          _row('Owner', vehicle.ownerName),
          _row('Role / ID', '${vehicle.ownerRole} • ${vehicle.ownerIdNumber}'),
          if (vehicle.department != null) _row('Department', vehicle.department!),
          _row(
            'Contact no.',
            phone ?? 'No number on file',
            strong: phone != null,
            trailing: phone == null
                ? null
                : IconButton(
                    key: const Key('copyPhoneButton'),
                    tooltip: 'Copy number',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18, color: NcstColors.navy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: phone));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied $phone'), duration: const Duration(seconds: 2)),
                        );
                      }
                    },
                  ),
          ),
          const Divider(height: 18),
          _row('Vehicle', '${vehicle.makeModelColor} • ${vehicle.vehicleType}'),
          _row('Sticker year', vehicle.stickerYear),
          if (since != null)
            _row('Inside since', hours != null ? '${formatTime(since)} (${hours.toStringAsFixed(1)} h)' : formatTime(since)),
          if (vehicle.entryGate != null) _row('Entered at', vehicle.entryGate!),
          if (vehicle.enteredBy != null) _row('Driven in by', vehicle.enteredBy!),
          if (vehicle.admittedBy != null) _row('Admitted by', vehicle.admittedBy!),
          if (drivers.isNotEmpty) ...[
            const Divider(height: 18),
            const Text('Authorized drivers', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: NcstColors.slate500)),
            const SizedBox(height: 4),
            for (final d in drivers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${d.fullName} • ${d.relationship}${(d.phone ?? '').trim().isNotEmpty ? ' • ${d.phone}' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: NcstColors.slate700),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
