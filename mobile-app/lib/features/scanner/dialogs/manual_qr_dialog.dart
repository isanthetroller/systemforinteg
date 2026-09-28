import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class ManualQrDialog extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const ManualQrDialog({
    super.key,
    required this.onSubmit,
  });

  static Future<void> show(BuildContext context, ValueChanged<String> onSubmit) {
    return showDialog(
      context: context,
      builder: (ctx) => ManualQrDialog(onSubmit: onSubmit),
    );
  }

  @override
  State<ManualQrDialog> createState() => _ManualQrDialogState();
}

class _ManualQrDialogState extends State<ManualQrDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    Navigator.of(context).pop();
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.qr_code_scanner_rounded, color: NcstColors.navy, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Enter QR Pass / Plate Number',
              style: TextStyle(
                color: NcstColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type or paste a QR code string or plate number to verify gate clearance:',
            style: TextStyle(fontSize: 12.5, color: NcstColors.slate600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Enter plate number or scan code',
              prefixIcon: const Icon(Icons.qr_code, color: NcstColors.navy),
              filled: true,
              fillColor: NcstColors.slate50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: NcstColors.slate200),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: NcstColors.slate600)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: NcstColors.navy,
            foregroundColor: NcstColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _submit,
          child: const Text('Verify QR Pass'),
        ),
      ],
    );
  }
}
