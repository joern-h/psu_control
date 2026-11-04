import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:psu_protocol/psu_protocol.dart';

import '../presets.dart';
import '../psu_connection.dart';
import '../theme.dart';

/// Editable list of setpoint presets. Tapping a preset applies it.
class PresetsPanel extends StatelessWidget {
  const PresetsPanel({
    super.key,
    required this.connection,
    required this.store,
  });

  final PsuConnection connection;
  final PresetStore store;

  Future<void> _apply(BuildContext context, Preset p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await connection.setVoltage(p.voltage);
      if (p.current case final c?) await connection.setCurrent(c);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(BuildContext context, {int? index}) async {
    final existing = index == null ? null : store.presets[index];
    final result = await showDialog<Preset>(
      context: context,
      builder: (_) => _PresetDialog(initial: existing),
    );
    if (result == null) return;
    if (index == null) {
      await store.add(result);
    } else {
      await store.update(index, result);
    }
  }

  Future<void> _delete(BuildContext context, int index) async {
    final p = store.presets[index];
    await store.remove(index);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${p.name}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.add(p)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, connection]),
      builder: (context, _) {
        final presets = store.presets;
        final enabled = connection.psuConnected;
        final state = connection.state;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Presets', style: theme.textTheme.labelLarge),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Add preset',
                      icon: const Icon(Icons.add),
                      onPressed: () => _edit(context),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) {
                        if (v == 'reset') store.resetToDefaults();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'reset',
                          child: Text('Reset to defaults'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (store.error case final err?)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: Text(
                      err,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (presets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                    child: Text(
                      'No presets yet. Use + to add one.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: presets.length,
                    onReorderItem: store.move,
                    itemBuilder: (context, i) {
                      final p = presets[i];
                      final active =
                          enabled &&
                          p.matches(state.setVoltage, state.setCurrent);
                      return _PresetTile(
                        key: ValueKey('${p.name}-${p.voltage}-${p.current}-$i'),
                        index: i,
                        preset: p,
                        active: active,
                        enabled: enabled,
                        onApply: () => _apply(context, p),
                        onEdit: () => _edit(context, index: i),
                        onDelete: () => _delete(context, i),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    super.key,
    required this.index,
    required this.preset,
    required this.active,
    required this.enabled,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final Preset preset;
  final bool active;
  final bool enabled;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final values = preset.current == null
        ? '${preset.voltage.toStringAsFixed(3)} V'
        : '${preset.voltage.toStringAsFixed(3)} V  ·  ${preset.current!.toStringAsFixed(3)} A';
    return Material(
      color: active
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onApply : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: active
                      ? palette.voltage
                      : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: enabled ? null : theme.disabledColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      values,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: tabularFigures,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit dialog with validation against the PSU limits.
class _PresetDialog extends StatefulWidget {
  const _PresetDialog({this.initial});

  final Preset? initial;

  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _voltage = TextEditingController(
    text: widget.initial?.voltage.toStringAsFixed(3) ?? '',
  );
  late final _current = TextEditingController(
    text: widget.initial?.current?.toStringAsFixed(3) ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _voltage.dispose();
    _current.dispose();
    super.dispose();
  }

  static double? _num(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  String? _validateVoltage(String? s) {
    final v = _num(s ?? '');
    if (v == null) return 'Enter a voltage';
    if (v < 0 || v > maxVoltage) return '0 – $maxVoltage V';
    return null;
  }

  String? _validateCurrent(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final a = _num(s);
    if (a == null) return 'Enter a current or leave empty';
    if (a < 0 || a > maxCurrent) return '0 – $maxCurrent A';
    return null;
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final voltage = _num(_voltage.text)!;
    final current = _current.text.trim().isEmpty ? null : _num(_current.text);
    var name = _name.text.trim();
    if (name.isEmpty) {
      name = current == null
          ? '${_fmt(voltage)} V'
          : '${_fmt(voltage)} V / ${_fmt(current)} A';
    }
    Navigator.of(context)
        .pop(Preset(name: name, voltage: voltage, current: current));
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add preset' : 'Edit preset'),
      content: Form(
        key: _form,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Optional, defaults to the values',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _voltage,
                decoration: const InputDecoration(
                  labelText: 'Voltage',
                  suffixText: 'V',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: numeric,
                validator: _validateVoltage,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _current,
                decoration: const InputDecoration(
                  labelText: 'Current limit',
                  suffixText: 'A',
                  helperText: 'Optional, keeps the current setpoint if empty',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: numeric,
                validator: _validateCurrent,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
