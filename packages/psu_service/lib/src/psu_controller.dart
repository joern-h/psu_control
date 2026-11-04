import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:psu_protocol/psu_protocol.dart';

import 'owon_spe.dart';
import 'serial_link.dart';

typedef Log = void Function(String message);

/// Owns the serial link, polls measurements, keeps a bounded history and
/// publishes state changes. Reconnects automatically if the device goes away.
class PsuController {
  PsuController({
    required this.devicePath,
    this.pollInterval = const Duration(milliseconds: 200),
    this.settingsRefreshInterval = const Duration(seconds: 2),
    this.historyLength = const Duration(hours: 1),
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxConsecutiveFailures = 5,
    Log? log,
  }) : _log = log ?? ((_) {});

  final String devicePath;
  final Duration pollInterval;

  /// How often setpoints / output state are re-read so that changes made on
  /// the front panel are picked up.
  final Duration settingsRefreshInterval;
  final Duration historyLength;
  final Duration reconnectDelay;

  /// A single missed reply is tolerated; after this many in a row the device
  /// is considered gone and the connect sequence starts over.
  final int maxConsecutiveFailures;
  final Log _log;

  /// The serial link is kept open across failed attempts. A blocking tty read
  /// cannot be cancelled, so every reopen would leak a reader that later eats
  /// the first reply meant for the new handle (and the device never comes
  /// back). The port is only closed and reopened when the link itself reports
  /// an I/O error or the device node disappears.
  SerialLink? _link;
  OwonSpe? _psu;
  PsuState _state = const PsuState(connected: false);
  final _history = ListQueue<Sample>();
  final _samples = StreamController<Sample>.broadcast();
  final _states = StreamController<PsuState>.broadcast();
  bool _running = false;
  Completer<void>? _stopped;
  final _firstAttempt = Completer<void>();

  PsuState get state => _state;
  Stream<Sample> get samples => _samples.stream;
  Stream<PsuState> get states => _states.stream;

  /// Retained samples, oldest first, optionally limited to the last [maxAge].
  List<Sample> history({Duration? maxAge}) {
    if (maxAge == null) return _history.toList();
    final cutoff = DateTime.now().subtract(maxAge);
    return _history.where((s) => !s.timestamp.isBefore(cutoff)).toList();
  }

  /// Starts the connect/poll loop. The returned future completes once the
  /// first connection attempt has either succeeded or failed, so callers can
  /// delay accepting clients until the initial state is known.
  Future<void> start() {
    if (!_running) {
      _running = true;
      _stopped = Completer<void>();
      _runLoop();
    }
    return _firstAttempt.future;
  }

  Future<void> stop() async {
    _running = false;
    await _stopped?.future;
    await _link?.close();
    await _samples.close();
    await _states.close();
  }

  Future<void> _runLoop() async {
    while (_running) {
      try {
        await _connect();
        if (!_firstAttempt.isCompleted) _firstAttempt.complete();
        await _pollUntilFailure();
      } on Object catch (e) {
        _log('serial link lost: $e');
        _publish(
          _state.copyWith(
            connected: false,
            outputOn: false,
            error: e.toString(),
          ),
        );
        if (!_firstAttempt.isCompleted) _firstAttempt.complete();
      }
      _psu = null;
      await _resetLinkIfBroken();
      if (_running) await Future<void>.delayed(reconnectDelay);
    }
    _stopped?.complete();
  }

  /// Closes the link only if it is unusable; a mere reply timeout keeps it.
  Future<void> _resetLinkIfBroken() async {
    final link = _link;
    if (link == null) return;
    if (link.isOpen && File(devicePath).existsSync()) return;
    _log('closing $devicePath');
    await link.close();
    _link = null;
  }

  Future<void> _connect() async {
    final link = _link ??= SerialLink(devicePath);
    if (!link.isOpen) await link.open();
    final psu = OwonSpe(link);
    final identity = await psu.identify();
    _psu = psu;
    _log('connected to $identity on $devicePath');
    _publish(
      PsuState(
        connected: true,
        identity: identity,
        setVoltage: await psu.getVoltageSetpoint(),
        setCurrent: await psu.getCurrentSetpoint(),
        outputOn: await psu.getOutput(),
        ovpLimit: await psu.getOvpLimit(),
        ocpLimit: await psu.getOcpLimit(),
        lastSample: _state.lastSample,
      ),
    );
  }

  Future<void> _pollUntilFailure() async {
    final psu = _psu!;
    var lastSettingsRefresh = DateTime.now();
    var failures = 0;
    while (_running && (_link?.isOpen ?? false)) {
      final started = DateTime.now();
      try {
        final (v, i) = await psu.measure();
        _addSample(Sample(timestamp: DateTime.now(), voltage: v, current: i));

        if (DateTime.now().difference(lastSettingsRefresh) >=
            settingsRefreshInterval) {
          lastSettingsRefresh = DateTime.now();
          await _refreshSettings();
        }
        failures = 0;
      } on SerialException catch (e) {
        failures++;
        _log('poll failed ($failures/$maxConsecutiveFailures): ${e.message}');
        if (failures >= maxConsecutiveFailures) rethrow;
      }

      final elapsed = DateTime.now().difference(started);
      if (elapsed < pollInterval) {
        await Future<void>.delayed(pollInterval - elapsed);
      }
    }
  }

  Future<void> _refreshSettings() async {
    final psu = _psu!;
    final next = _state.copyWith(
      setVoltage: await psu.getVoltageSetpoint(),
      setCurrent: await psu.getCurrentSetpoint(),
      outputOn: await psu.getOutput(),
    );
    if (next.setVoltage != _state.setVoltage ||
        next.setCurrent != _state.setCurrent ||
        next.outputOn != _state.outputOn) {
      _publish(next);
    } else {
      _state = next;
    }
  }

  void _addSample(Sample sample) {
    _history.addLast(sample);
    final cutoff = sample.timestamp.subtract(historyLength);
    while (_history.isNotEmpty && _history.first.timestamp.isBefore(cutoff)) {
      _history.removeFirst();
    }
    _state = _state.copyWith(lastSample: sample);
    _samples.add(sample);
  }

  void _publish(PsuState next) {
    _state = next;
    _states.add(next);
  }

  OwonSpe _require() {
    final psu = _psu;
    if (psu == null || !(_link?.isOpen ?? false)) {
      throw SerialException(
        'power supply not connected (${_state.error ?? 'no link'})',
      );
    }
    return psu;
  }

  Future<PsuState> setVoltage(double volts) async {
    if (volts.isNaN || volts < 0 || volts > maxVoltage) {
      throw ArgumentError('voltage must be between 0 and $maxVoltage V');
    }
    final psu = _require();
    await psu.setVoltage(volts);
    _publish(_state.copyWith(setVoltage: await psu.getVoltageSetpoint()));
    return _state;
  }

  Future<PsuState> setCurrent(double amps) async {
    if (amps.isNaN || amps < 0 || amps > maxCurrent) {
      throw ArgumentError('current must be between 0 and $maxCurrent A');
    }
    final psu = _require();
    await psu.setCurrent(amps);
    _publish(_state.copyWith(setCurrent: await psu.getCurrentSetpoint()));
    return _state;
  }

  Future<PsuState> setOutput(bool on) async {
    final psu = _require();
    await psu.setOutput(on);
    _publish(_state.copyWith(outputOn: await psu.getOutput()));
    return _state;
  }

  Future<String?> scpi(String command) => _require().raw(command);
}
