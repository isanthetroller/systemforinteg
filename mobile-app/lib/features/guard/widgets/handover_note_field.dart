import 'package:flutter/material.dart';

/// Text box for the handover note. It owns (and disposes) its controller, so it is safe inside a dialog that is still
/// animating away when the dialog's result comes back.
class HandoverNoteField extends StatefulWidget {
  final String label;
  final int lines;
  final ValueChanged<String> onChanged;

  const HandoverNoteField({
    super.key,
    required this.onChanged,
    this.label = 'Handover note (optional)',
    this.lines = 4,
  });

  @override
  State<HandoverNoteField> createState() => _HandoverNoteFieldState();
}

class _HandoverNoteFieldState extends State<HandoverNoteField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.lines,
      maxLength: 2000,
      onChanged: widget.onChanged,
      decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, labelText: widget.label),
    );
  }
}
