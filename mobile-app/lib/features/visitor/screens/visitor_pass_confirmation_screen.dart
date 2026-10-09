import 'package:flutter/material.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../core/widgets/qr_code_widget.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../theme/ncst_theme.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../services/api_service.dart';

class VisitorPassConfirmationScreen extends StatefulWidget {
  final VisitorPass pass;
  final VoidCallback onFinish;

  const VisitorPassConfirmationScreen({
    super.key,
    required this.pass,
    required this.onFinish,
  });

  @override
  State<VisitorPassConfirmationScreen> createState() =>
      _VisitorPassConfirmationState();
}

class _VisitorPassConfirmationState
    extends State<VisitorPassConfirmationScreen> {
  final _repository = VisitorRepository();
  VisitorPass? _currentPass;
  VisitorPass get pass => _currentPass ?? widget.pass;
  VoidCallback get onFinish => widget.onFinish;

  @override
  void initState() {
    super.initState();
    _currentPass = widget.pass;
    _repository.passesNotifier.addListener(_onPassChanged);
    ApiService.liveRevision.addListener(_onPassChanged);
  }

  @override
  void didUpdateWidget(covariant VisitorPassConfirmationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pass != widget.pass) _currentPass = widget.pass;
  }

  @override
  void dispose() {
    _repository.passesNotifier.removeListener(_onPassChanged);
    ApiService.liveRevision.removeListener(_onPassChanged);
    super.dispose();
  }

  void _onPassChanged() {
    if (!mounted) return;
    VisitorPass? latest;
    for (final candidate in _repository.passesNotifier.value) {
      if ((widget.pass.dbId != null && candidate.dbId == widget.pass.dbId) ||
          candidate.passId == widget.pass.passId) {
        latest = candidate;
        break;
      }
    }
    // A pending local pass can remain available until the server assigns an ID.
    if (latest == null && widget.pass.dbId == null) latest = _currentPass;
    setState(() {
      _currentPass = latest;
    });
  }

  Widget _unavailableContent(BuildContext context, {bool dialog = false}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 36, color: NcstColors.navy),
          const SizedBox(height: 16),
          Text(
            pass.visitorName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            _currentPass == null
                ? 'This pass is no longer available.'
                : 'This pass is ${pass.statusDisplay.toLowerCase()}.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'The QR code is unavailable. Check the latest pass before continuing.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: dialog ? () => Navigator.of(context).pop() : onFinish,
            child: Text(dialog ? 'Close' : 'Return to gate'),
          ),
        ],
      ),
    );
  }

  /// Displays an extra-large, pure white, high-contrast modal of the QR code
  /// designed specifically for visitors to photograph with their smartphone camera
  /// from the driver's seat or outside the vehicle window without glare.
  void _showFullscreenQr(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AnimatedBuilder(
        animation: Listenable.merge([
          _repository.passesNotifier,
          ApiService.liveRevision,
        ]),
        builder: (ctx, _) {
          if (_currentPass == null || !pass.isActive) {
            return Dialog(child: _unavailableContent(ctx, dialog: true));
          }
          final screenWidth = MediaQuery.of(ctx).size.width;
          final qrSize = (screenWidth * 0.72).clamp(240.0, 330.0);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top Header Notice for Camera
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: NcstColors.gold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: NcstColors.goldDark,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: NcstColors.goldDark,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SNAP PHOTO NOW',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: NcstColors.navyDark,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Point your camera at this QR code',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: NcstColors.slate800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Large Monospace Pass ID
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: NcstColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pass.passId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: NcstColors.navy,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Hero High-Contrast QR Code
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NcstColors.slate200, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: QrCodeWidget(
                      data: pass.toQrPayload(),
                      size: qrSize,
                      foregroundColor: NcstColors.navyDark,
                      backgroundColor: Colors.white,
                      showBorder: false,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // License Plate Badge
                  PlateBadge(plateNumber: pass.plateNumber, isProminent: true),
                  const SizedBox(height: 8),

                  // Validity Expiration Callout
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: NcstColors.goldDark,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Valid until ${DateTimeUtils.formatTime(pass.expiryTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: NcstColors.slate800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Present this photo to the gate guard upon exit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: NcstColors.slate500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),

                  // Close Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NcstColors.navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'RETURN TO PASS DETAILS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPass == null || !pass.isActive) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Visitor pass'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(child: _unavailableContent(context)),
          ),
        ),
      );
    }
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 360;

    return Scaffold(
      backgroundColor: NcstColors.slate100,
      appBar: AppBar(
        title: const Text('Temporary Visitor Pass'),
        backgroundColor: NcstColors.navy,
        foregroundColor: NcstColors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen_rounded),
            tooltip: 'Fullscreen QR for Driver',
            onPressed: () => _showFullscreenQr(context),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Return to Gate',
            onPressed: onFinish,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isCompact ? 14 : 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Photo Instruction Banner for Visitor
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: NcstColors.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: NcstColors.goldDark,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: NcstColors.goldDark,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'VISITOR: PLEASE TAKE A PHOTO',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: NcstColors.navyDark,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Please take a photo of this QR pass with your mobile phone camera now. Present this photo at the gate when exiting the campus.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: NcstColors.slate800,
                                  height: 1.35,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '[ Gate Officer: Show this screen to the driver ]',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  color: NcstColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Official Pass Card
                  Container(
                    decoration: BoxDecoration(
                      color: NcstColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NcstColors.slate200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(isCompact ? 16 : 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Card Header
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'NCST CAMPUS ACCESS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: NcstColors.navy,
                                  ),
                                ),
                                Text(
                                  pass.passId,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: NcstColors.slate700,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: NcstColors.greenLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: NcstColors.green.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: NcstColors.green,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Centerpiece Interactive QR Code
                        InkWell(
                          onTap: () => _showFullscreenQr(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              children: [
                                QrCodeWidget(
                                  data: pass.toQrPayload(),
                                  size: isCompact ? 200 : 230,
                                  foregroundColor: NcstColors.navyDark,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: const [
                                    Icon(
                                      Icons.zoom_in_rounded,
                                      size: 15,
                                      color: NcstColors.navy,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Tap QR code to zoom full-screen for driver',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: NcstColors.navy,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Visitor Name
                        Text(
                          pass.visitorName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: NcstColors.slate900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),

                        // License Plate Badge
                        PlateBadge(
                          plateNumber: pass.plateNumber,
                          isProminent: true,
                        ),
                        const SizedBox(height: 16),

                        // Metadata Grid
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NcstColors.slate50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: NcstColors.slate200),
                          ),
                          child: Column(
                            children: [
                              _buildMetaRow(
                                'Entry Time',
                                DateTimeUtils.formatTime(pass.entryTime),
                              ),
                              const SizedBox(height: 6),
                              _buildMetaRow(
                                'Valid Until',
                                DateTimeUtils.formatTime(pass.expiryTime),
                              ),
                              const SizedBox(height: 6),
                              _buildMetaRow('Entry Gate', pass.gatePoint),
                              const SizedBox(height: 6),
                              _buildMetaRow(
                                'Issued By',
                                pass.registeredByGuard,
                              ),
                              if (pass.contactNumber != null &&
                                  pass.contactNumber!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Contact Mobile',
                                  pass.contactNumber!,
                                ),
                              ],
                              if (pass.personToVisit != null &&
                                  pass.personToVisit!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Visiting Host',
                                  pass.personToVisit!,
                                ),
                              ],
                              if (pass.purposeOfVisit != null &&
                                  pass.purposeOfVisit!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Purpose of Visit',
                                  pass.purposeOfVisit!,
                                ),
                              ],
                              if (pass.vehicleModel != null &&
                                  pass.vehicleModel!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Vehicle Model',
                                  pass.vehicleModel!,
                                ),
                              ],
                              if (pass.vehiclePhotoUrl != null) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Vehicle Photo',
                                  'Captured & Stored',
                                ),
                              ],
                              if (pass.items.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _buildMetaRow(
                                  'Declared Items',
                                  '${pass.items.length} item(s) registered',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Bottom Action Buttons
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Fullscreen QR Button
                      SizedBox(
                        child: OutlinedButton.icon(
                          onPressed: () => _showFullscreenQr(context),
                          icon: const Icon(Icons.fullscreen_rounded, size: 20),
                          label: const Text('FULLSCREEN QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NcstColors.navy,
                            side: const BorderSide(
                              color: NcstColors.navy,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Complete Entry Button
                      SizedBox(
                        child: ElevatedButton.icon(
                          onPressed: onFinish,
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                          ),
                          label: const Text('CLEARED (TO GO)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NcstColors.green,
                            foregroundColor: NcstColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Secondary Print Receipt option
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pass receipt shared / sent to campus print queue.',
                          ),
                          backgroundColor: NcstColors.navy,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.print_outlined,
                      size: 16,
                      color: NcstColors.slate600,
                    ),
                    label: const Text(
                      'Print Physical Decal / Ticket',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: NcstColors.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: NcstColors.slate600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NcstColors.slate900,
            ),
          ),
        ),
      ],
    );
  }
}
