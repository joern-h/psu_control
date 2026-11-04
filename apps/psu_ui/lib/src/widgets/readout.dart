import 'package:flutter/material.dart';
import 'package:psu_protocol/psu_protocol.dart';

import '../theme.dart';

/// Live measurement tiles: voltage, current, power.
class Readout extends StatelessWidget {
  const Readout({super.key, required this.state, required this.enabled});

  final PsuState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final m = state.lastSample;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Output', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                _OutputBadge(on: state.outputOn, enabled: enabled),
              ],
            ),
            const SizedBox(height: 12),
            _Value(
              label: 'Voltage',
              value: m?.voltage,
              unit: 'V',
              decimals: 3,
              accent: palette.voltage,
              enabled: enabled,
            ),
            const SizedBox(height: 8),
            _Value(
              label: 'Current',
              value: m?.current,
              unit: 'A',
              decimals: 3,
              accent: palette.current,
              enabled: enabled,
            ),
            const SizedBox(height: 8),
            _Value(
              label: 'Power',
              value: m?.power,
              unit: 'W',
              decimals: 2,
              accent: null,
              enabled: enabled,
            ),
            const SizedBox(height: 12),
            Text(
              'Setpoint ${state.setVoltage.toStringAsFixed(3)} V / ${state.setCurrent.toStringAsFixed(3)} A\n'
              'OVP ${state.ovpLimit.toStringAsFixed(1)} V   ·   OCP ${state.ocpLimit.toStringAsFixed(2)} A',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontFeatures: tabularFigures),
            ),
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    required this.unit,
    required this.decimals,
    required this.accent,
    required this.enabled,
  });

  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final Color? accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value == null || !enabled
        ? '–.${'–' * decimals}'
        : value!.toStringAsFixed(decimals);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 4,
          height: 36,
          margin: const EdgeInsets.only(right: 12, bottom: 4),
          decoration: BoxDecoration(
            color: accent ?? theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
        Text(
          text,
          style: theme.textTheme.displaySmall?.copyWith(
            fontFeatures: tabularFigures,
            color: enabled ? null : theme.disabledColor,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            unit,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _OutputBadge extends StatelessWidget {
  const _OutputBadge({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.disabledColor
        : on
        ? const Color(0xFF0CA30C)
        : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.power : Icons.power_off, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            !enabled ? 'N/A' : (on ? 'ON' : 'OFF'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
