import 'package:flutter/material.dart';

import '../../../core/widgets/driver_photo_view.dart';
import '../../../core/widgets/vehicle_photo_panel.dart';
import '../../../core/widgets/evidence_button.dart';
import '../../../services/evidence_service.dart';
import 'scan_notice_strip.dart';

import '../../../theme/ncst_theme.dart';

/// Displays the server's suggested movement. Scanning alone never calls onConfirm.
class MovementConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> preview;
  final String guardName;
  final bool saving;
  final bool retryPending;
  final bool invalidated;
  final String? error;
  final void Function(int? driverId, bool itemsVerified) onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onInspect;
  final VoidCallback? onIssueViolation;
  final ValueChanged<PendingEvidence?>? onEvidenceChanged;
  const MovementConfirmationCard({
    super.key,
    required this.preview,
    required this.guardName,
    required this.saving,
    required this.retryPending,
    required this.invalidated,
    required this.onConfirm,
    required this.onCancel,
    this.error,
    this.onInspect,
    this.onIssueViolation,
    this.onEvidenceChanged,
  });

  @override
  State<MovementConfirmationCard> createState() =>
      _MovementConfirmationCardState();
}

class _MovementConfirmationCardState extends State<MovementConfirmationCard> {
  int? _driverId;
  bool _driverChecked = false;
  final Set<int> _checkedItems = {};

  @override
  Widget build(BuildContext context) {
    final movement = Map<String, dynamic>.from(
      widget.preview['movement'] as Map,
    );
    final isVisitor = widget.preview['visitor'] is Map;
    final record = Map<String, dynamic>.from(
      (widget.preview[isVisitor ? 'visitor' : 'vehicle']) as Map,
    );
    final drivers = (record['authorizedDrivers'] as List? ?? []).cast<Map>();
    final items = (record['items'] as List? ?? []).cast<Map>();
    final vip = record['isVip'] == true;
    final needsDriver = !isVisitor && !vip;
    final outgoing = movement['suggestedAction'] == 'OUT';
    final locked = widget.saving || widget.retryPending || widget.invalidated;
    final ready =
        (!needsDriver || (_driverId != null && _driverChecked)) &&
        _checkedItems.length == items.length;
    final selectedDriver = drivers
        .where((d) => '${d['id']}' == '$_driverId')
        .firstOrNull;
    final driverPhoto = (selectedDriver?['photoUrl'] ?? '').toString();
    final plate = record['plateNumber']?.toString() ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScanNoticeStrip(notices: ScanNotice.fromVerify(widget.preview)),
              for (final warning in (widget.preview['warnings'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    warning.toString(),
                    style: const TextStyle(color: NcstColors.goldDark),
                  ),
                ),
              Text(
                outgoing ? 'Confirm vehicle exit' : 'Confirm vehicle entry',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: NcstColors.navy,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                plate,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: NcstColors.slate900,
                ),
              ),
              Text(
                (record['makeModelColor'] ??
                        record['vehicleModel'] ??
                        record['vehicleType'] ??
                        '')
                    .toString(),
              ),
              Text(
                (record['ownerName'] ?? record['visitorName'] ?? '').toString(),
                style: const TextStyle(color: NcstColors.slate600),
              ),
              if (vip)
                const Text(
                  'VIP pass • Driver check not required',
                  style: TextStyle(color: NcstColors.navy),
                ),
              if ((record['vehiclePhoto'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                VehiclePhotoPanel(photoData: record['vehiclePhoto'].toString()),
              ],
              const Divider(height: 32),
              _detail('Current status', movement['currentStatus'].toString()),
              _detail(
                'Suggested action',
                outgoing ? 'OUT — Exit' : 'IN — Entry',
              ),
              _detail('Checkpoint', movement['checkpoint'].toString()),
              _detail('Guard', widget.guardName),
              if (needsDriver) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _driverId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select the authorized driver',
                  ),
                  items: drivers
                      .where((d) => int.tryParse('${d['id']}') != null)
                      .map(
                        (d) => DropdownMenuItem<int>(
                          value: int.parse('${d['id']}'),
                          child: Text(
                            '${d['fullName'] ?? d['full_name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: locked
                      ? null
                      : (id) => setState(() {
                          _driverId = id;
                          _driverChecked = false;
                        }),
                ),
                if (_driverId != null) ...[
                  const SizedBox(height: 12),
                  DriverPhotoView(
                    photoUrl: driverPhoto.isNotEmpty
                        ? driverPhoto
                        : ((selectedDriver?['fullName'] ?? '') ==
                                  record['ownerName']
                              ? (record['ownerPhotoUrl'] ?? '').toString()
                              : ''),
                    size: 150,
                  ),
                  Text(
                    'Relationship: ${selectedDriver?['relationship'] ?? ''}',
                  ),
                  Text(
                    'License: ${selectedDriver?['licenseNo'] ?? 'Not provided'}',
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I checked the selected driver'),
                  value: _driverChecked,
                  onChanged: locked || _driverId == null
                      ? null
                      : (value) =>
                            setState(() => _driverChecked = value == true),
                ),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Check declared items',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (var i = 0; i < items.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${items[i]['name']} × ${items[i]['quantity']}',
                    ),
                    value: _checkedItems.contains(i),
                    onChanged: locked
                        ? null
                        : (checked) => setState(() {
                            checked == true
                                ? _checkedItems.add(i)
                                : _checkedItems.remove(i);
                          }),
                  ),
              ],
              if (widget.onEvidenceChanged != null)
                AbsorbPointer(
                  absorbing: locked,
                  child: EvidenceButton(
                    expectedPlate: plate,
                    onChanged: widget.onEvidenceChanged!,
                  ),
                ),
              if (widget.onInspect != null)
                TextButton.icon(
                  onPressed: locked ? null : widget.onInspect,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View details / Report incident'),
                ),
              if (widget.onIssueViolation != null)
                TextButton.icon(
                  onPressed: locked ? null : widget.onIssueViolation,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Issue violation'),
                ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: NcstColors.crimson),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    widget.saving ||
                        widget.invalidated ||
                        (!ready && !widget.retryPending)
                    ? null
                    : () => widget.onConfirm(_driverId, items.isNotEmpty),
                icon: widget.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(outgoing ? Icons.logout : Icons.login),
                label: Text(
                  widget.saving
                      ? 'Saving…'
                      : widget.retryPending
                      ? 'Retry confirmation'
                      : outgoing
                      ? 'Confirm Exit'
                      : 'Confirm Entry',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: NcstColors.navy,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.saving || widget.retryPending
                    ? null
                    : widget.onCancel,
                child: Text(widget.invalidated ? 'Scan again' : 'Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: NcstColors.slate600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
