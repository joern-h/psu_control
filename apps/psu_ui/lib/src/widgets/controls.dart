import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:psu_protocol/psu_protocol.dart';

import '../psu_connection.dart';

/// Setpoint entry and the output switch.
class Controls extends StatefulWidget {
  const Controls({super.key, required this.connection});

  final PsuConnection connection;

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  final _voltage = TextEditingController();
  final _current = TextEditingController();
  final _voltageFocus = FocusNode();
  final _currentFocus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _syncFromState();
    widget.connection.addListener(_syncFromState);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_syncFromState);
    _voltage.dispose();
    _current.dispose();
    _voltageFocus.dispose();
    _currentFocus.dispose();
    super.dispose();
  }

  /// Mirrors the setpoints into the fields unless the user is editing them.
  void _syncFromState() {
    final s = widget.connection.state;
    if (!_voltageFocus.hasFocus) {
      _voltage.text = s.setVoltage.toStringAsFixed(3);
    }
    if (!_currentFocus.hasFocus) {
      _current.text = s.setCurrent.toStringAsFixed(3);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double? _parse(String text, double max, String what) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what must be between 0 and $max')),
      );
      return null;
    }
    return v;
  }

  void _applyVoltage() {
    final v = _parse(_voltage.text, maxVoltage, 'Voltage');
    if (v == null) return;
    _run(() => widget.connection.setVoltage(v));
    _voltageFocus.unfocus();
  }

  void _applyCurrent() {
    final a = _parse(_current.text, maxCurrent, 'Current');
    if (a == null) return;
    _run(() => widget.connection.setCurrent(a));
    _currentFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.connection.psuConnected && !_busy;
    final on = widget.connection.state.outputOn;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Setpoints', style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            _SetpointField(
              controller: _voltage,
              focusNode: _voltageFocus,
              label: 'Voltage',
              unit: 'V',
              max: maxVoltage,
              enabled: enabled,
              onApply: _applyVoltage,
            ),
            const SizedBox(height: 12),
            _SetpointField(
              controller: _current,
              focusNode: _currentFocus,
              label: 'Current limit',
              unit: 'A',
              max: maxCurrent,
              enabled: enabled,
              onApply: _applyCurrent,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: on
                      ? const Color(0xFFD03B3B)
                      : const Color(0xFF0CA30C),
                  foregroundColor: Colors.white,
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: enabled
                    ? () => _run(() => widget.connection.setOutput(!on))
                    : null,
                icon: Icon(on ? Icons.power_off : Icons.power_settings_new),
                label: Text(on ? 'OUTPUT OFF' : 'OUTPUT ON'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetpointField extends StatelessWidget {
  const _SetpointField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.unit,
    required this.max,
    required this.enabled,
    required this.onApply,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String unit;
  final double max;
  final bool enabled;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit,
              helperText: '0 – $max $unit',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onApply(),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: FilledButton.tonal(
            onPressed: enabled ? onApply : null,
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}
