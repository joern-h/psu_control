import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A stored setpoint combination. [current] is optional: a preset without a
/// current limit leaves the current setpoint untouched when applied.
@immutable
class Preset {
  const Preset({required this.name, required this.voltage, this.current});

  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
    name: json['name'] as String,
    voltage: (json['voltage'] as num).toDouble(),
    current: (json['current'] as num?)?.toDouble(),
  );

  final String name;
  final double voltage;
  final double? current;

  Map<String, dynamic> toJson() => {
    'name': name,
    'voltage': voltage,
    if (current != null) 'current': current,
  };

  /// True when the PSU setpoints equal this preset (within 1 mV / 1 mA).
  bool matches(double setVoltage, double setCurrent) =>
      (setVoltage - voltage).abs() < 0.0005 &&
      (current == null || (setCurrent - current!).abs() < 0.0005);
}

/// Holds the preset list and persists it as JSON in the user's config dir.
class PresetStore extends ChangeNotifier {
  PresetStore({String? path}) : path = path ?? defaultPath;

  final String path;
  List<Preset> _presets = const [];
  String? _error;

  List<Preset> get presets => List.unmodifiable(_presets);
  String? get error => _error;

  static String get defaultPath {
    final env = Platform.environment;
    final config = env['XDG_CONFIG_HOME'] ?? '${env['HOME'] ?? '.'}/.config';
    return '$config/psu_control/presets.json';
  }

  static const defaults = [
    Preset(name: '5 V', voltage: 5),
    Preset(name: '9 V', voltage: 9),
    Preset(name: '12 V', voltage: 12),
    Preset(name: '24 V', voltage: 24),
    Preset(name: '48 V', voltage: 48),
  ];

  /// Loads the file; falls back to [defaults] (and writes them) if missing.
  Future<void> load() async {
    final file = File(path);
    try {
      if (!file.existsSync()) {
        _presets = List.of(defaults);
        await _save();
      } else {
        final json = jsonDecode(await file.readAsString()) as List<dynamic>;
        _presets = [
          for (final p in json) Preset.fromJson(p as Map<String, dynamic>),
        ];
      }
      _error = null;
    } on Object catch (e) {
      _error = 'cannot read $path: $e';
      _presets = List.of(defaults);
    }
    notifyListeners();
  }

  Future<void> add(Preset p) => _mutate((l) => l.add(p));

  Future<void> update(int index, Preset p) => _mutate((l) => l[index] = p);

  Future<void> remove(int index) => _mutate((l) => l.removeAt(index));

  /// [to] is the index in the list after [from] has been removed (as
  /// `ReorderableListView.onReorderItem` reports it).
  Future<void> move(int from, int to) =>
      _mutate((l) => l.insert(to, l.removeAt(from)));

  Future<void> resetToDefaults() => _mutate(
    (l) => l
      ..clear()
      ..addAll(defaults),
  );

  Future<void> _mutate(void Function(List<Preset> list) change) async {
    final next = List.of(_presets);
    change(next);
    _presets = next;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(
        '${encoder.convert([for (final p in _presets) p.toJson()])}\n',
      );
      _error = null;
    } on Object catch (e) {
      _error = 'cannot write $path: $e';
      notifyListeners();
    }
  }
}
