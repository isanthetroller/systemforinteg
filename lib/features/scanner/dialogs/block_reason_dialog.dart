import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../theme/ncst_theme.dart';

class BlockReasonDialog extends StatelessWidget {
  final ValueChanged<String> onReasonSelected;
  final List<String> reasons;

  const BlockReasonDialog({
    super.key,
    required this.onReasonSelected,
    this.reasons = AppConstants.defaultBlockReasons,
  });

  static Future<void> show(BuildContext context, ValueChanged<String> onReasonSelected) {
    return showDialog(
      context: context,
      builder: (ctx) => BlockReasonDialog(onReasonSelected: onReasonSelected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: const [
          Icon(Icons.block, color: NcstColors.crimson, size: 24),
          SizedBox(width: 8),
          Text(
            'Block Vehicle Entry',
            style: TextStyle(
              color: NcstColors.crimson,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select reason for entry denial:',
            style: TextStyle(color: NcstColors.slate600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...reasons.map(
            (reason) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.radio_button_unchecked, size: 18, color: NcstColors.slate400),
              title: Text(
                reason,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.of(context).pop();
                onReasonSelected(reason);
              },
            ),
          ),
        ],
      ),
    );
  }
}
