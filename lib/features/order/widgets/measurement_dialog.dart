import 'package:flutter/material.dart';

/// A quantity dialog that owns its controller for the lifetime of the dialog
/// route. `showDialog` completes as soon as the route starts closing, before
/// its reverse transition has removed the TextField.
class MeasurementDialog extends StatefulWidget {
  const MeasurementDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.unit,
    required this.submitLabel,
    super.key,
  });

  final String title;
  final String initialValue;
  final String label;
  final String unit;
  final String submitLabel;

  @override
  State<MeasurementDialog> createState() => _MeasurementDialogState();
}

class _MeasurementDialogState extends State<MeasurementDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.unit,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
