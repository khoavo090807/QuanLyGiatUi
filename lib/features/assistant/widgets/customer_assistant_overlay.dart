import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/features/assistant/data/customer_assistant_preferences.dart';
import 'package:app_quanly_giaiui/features/assistant/screens/customer_assistant_screen.dart';

class CustomerAssistantOverlay extends StatefulWidget {
  const CustomerAssistantOverlay({super.key});

  @override
  State<CustomerAssistantOverlay> createState() =>
      _CustomerAssistantOverlayState();
}

class _CustomerAssistantOverlayState extends State<CustomerAssistantOverlay> {
  static const _buttonSize = 58.0;
  Offset? _position;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final position = await CustomerAssistantPreferences.loadPosition();
    if (mounted && position != null) setState(() => _position = position);
  }

  Offset _clamp(Offset position, Size size) => Offset(
    position.dx.clamp(0, math.max(0, size.width - _buttonSize)).toDouble(),
    position.dy.clamp(0, math.max(0, size.height - _buttonSize)).toDouble(),
  );

  Future<void> _openAssistant() => Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const CustomerAssistantScreen(),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final defaultPosition = Offset(
        math.max(0, size.width - _buttonSize - 16).toDouble(),
        math.max(0, size.height - _buttonSize - 20).toDouble(),
      );
      final position = _clamp(_position ?? defaultPosition, size);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            child: GestureDetector(
              onPanUpdate: (details) => setState(() {
                _position = _clamp((_position ?? position) + details.delta, size);
              }),
              onPanEnd: (_) {
                final current = _position ?? position;
                CustomerAssistantPreferences.savePosition(current);
              },
              child: SizedBox(
                width: _buttonSize,
                height: _buttonSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: FloatingActionButton(
                        heroTag: 'customer-ai-assistant',
                        tooltip: 'Mở trợ lý AI',
                        onPressed: _openAssistant,
                        child: const Icon(Icons.smart_toy_outlined),
                      ),
                    ),
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => CustomerAssistantPreferences.setEnabled(false),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
