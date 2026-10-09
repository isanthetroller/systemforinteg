import 'package:flutter/material.dart';

import '../../services/evidence_service.dart';
import '../../theme/ncst_theme.dart';

/// "Take photo" row for a guard: opens the camera, reads the plate off the picture and shows at once whether it is
/// the plate on the pass. The photo is only held here; the screen that owns it uploads it after the decision is
/// recorded (so it can be stored with the right gate log or violation).
class EvidenceButton extends StatefulWidget {
  final String expectedPlate;
  final String label;
  final ValueChanged<PendingEvidence?> onChanged;

  const EvidenceButton({
    super.key,
    required this.expectedPlate,
    required this.onChanged,
    this.label = 'Photo of vehicle / plate',
  });

  @override
  State<EvidenceButton> createState() => _EvidenceButtonState();
}

class _EvidenceButtonState extends State<EvidenceButton> {
  PendingEvidence? _photo;
  bool _busy = false;

  Future<void> _take() async {
    setState(() => _busy = true);
    final taken = await EvidenceService.capture(expectedPlate: widget.expectedPlate);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (taken != null) _photo = taken;
    });
    if (taken != null) widget.onChanged(taken);
  }

  void _remove() {
    setState(() => _photo = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    if (photo == null) {
      return OutlinedButton.icon(
        key: const Key('evidenceTakePhoto'),
        onPressed: _busy ? null : _take,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.photo_camera_outlined, size: 18),
        label: Text(widget.label),
        style: OutlinedButton.styleFrom(foregroundColor: NcstColors.navy, side: const BorderSide(color: NcstColors.slate200)),
      );
    }

    final bool? ok = photo.matches;
    final Color tone = ok == true ? NcstColors.green : (ok == false ? NcstColors.crimson : NcstColors.slate600);
    final String verdict = ok == true
        ? 'Plate ${photo.plateRead} matches the pass'
        : ok == false
            ? 'Plate reads ${photo.plateRead}, but the pass is for ${widget.expectedPlate}. Check the vehicle.'
            : 'No plate could be read from the photo. Check it yourself.';
    return Container(
      key: const Key('evidenceResult'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(photo.bytes, width: 56, height: 56, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(verdict, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tone, height: 1.3)),
          ),
          IconButton(
            tooltip: 'Retake photo',
            onPressed: _busy ? null : _take,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Remove photo',
            onPressed: _remove,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
