import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/evidence_button.dart';
import '../../../services/evidence_service.dart';
import '../../../theme/ncst_theme.dart';

/// Lets a guard issue a violation to a vehicle (type + notes). The vehicle is then on hold: it can neither enter nor
/// leave campus until an administrator resolves the violation, and the owner is notified by e-mail and in the
/// student portal.
class IssueViolationDialog extends StatefulWidget {
  final String plateNumber;
  final void Function(String type, String notes) onSubmit;

  /// Called with the evidence photo (or null) when one was taken; sent to the server after the violation exists.
  final void Function(PendingEvidence? photo)? onEvidence;

  const IssueViolationDialog({
    super.key,
    required this.plateNumber,
    required this.onSubmit,
    this.onEvidence,
  });

  static Future<void> show(
    BuildContext context, {
    required String plateNumber,
    required void Function(String type, String notes) onSubmit,
    void Function(PendingEvidence? photo)? onEvidence,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => IssueViolationDialog(plateNumber: plateNumber, onSubmit: onSubmit, onEvidence: onEvidence),
    );
  }

  @override
  State<IssueViolationDialog> createState() => _IssueViolationDialogState();
}

class _IssueViolationDialogState extends State<IssueViolationDialog> {
  String? _type;
  final TextEditingController _notes = TextEditingController();
  String? _error;
  PendingEvidence? _photo;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final type = _type;
    final notes = _notes.text.trim();
    if (type == null) {
      setState(() => _error = 'Choose the type of violation.');
      return;
    }
    if (type == 'Other' && notes.isEmpty) {
      setState(() => _error = 'Describe the violation in the notes when choosing "Other".');
      return;
    }
    Navigator.of(context).pop();
    widget.onEvidence?.call(_photo);
    widget.onSubmit(type, notes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.gavel_rounded, color: NcstColors.crimson, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Issue Violation • ${widget.plateNumber}',
              style: const TextStyle(color: NcstColors.crimson, fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The vehicle will be put on hold: it cannot enter or leave campus until an administrator resolves the '
            'violation. The owner is notified by email and in the student portal.',
            style: TextStyle(color: NcstColors.slate600, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: const Key('violationTypeField'),
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Violation type',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: AppConstants.violationTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() {
              _type = v;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('violationNotesField'),
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (what happened, where?)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (widget.onEvidence != null) ...[
            const SizedBox(height: 12),
            EvidenceButton(
              expectedPlate: widget.plateNumber,
              label: 'Add photo evidence',
              onChanged: (p) => _photo = p,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: NcstColors.crimson, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('issueViolationSubmit'),
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: NcstColors.crimson, foregroundColor: NcstColors.white),
          child: const Text('Issue Violation'),
        ),
      ],
    );
  }
}
