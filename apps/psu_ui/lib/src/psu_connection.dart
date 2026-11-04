import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:psu_protocol/psu_protocol.dart';

/// Keeps a [PsuClient] alive (reconnecting on failure), mirrors the service
/// state and retains a bounded sample history for the charts.
class PsuConnection extends ChangeNotifier {
  PsuConnection({
    this.url = defaultServiceUrl,
    this.historyLength = const Duration(minutes: 30),
    this.reconnectDelay = const Duration(seconds: 2),
    this.autoStartService = true,
  });

  final String url;
  final Duration historyLength;
  final Duration reconnectDelay;

  /// Launch `psu_service` when it is not reachable (see [ServiceLauncher]).
  final bool autoStartService;

  PsuClient? _client;
  bool _startingService = false;
  DateTime? _lastStartAttempt;
  bool _disposed = false;
  bool _serviceReachable = false;
  String? _lastError;
  PsuState _state = const PsuState(connected: false);
  final List<Sample> _history = [];

  /// Whether the WebSocket to the service is open.
  bool get serviceReachable => _serviceReachable;

  /// Whether the service has a working serial link to the PSU.
  bool get psuConnected => _serviceReachable && _state.connected;

  /// True while a service launch attempt is in progress.
  bool get startingService => _startingService;

  PsuState get state => _state;
  String? get lastError => _lastError;

  /// Samples oldest first.
  List<Sample> get history => _history;

  void start() {
    _loop();
  }

  Future<void> _loop() async {
    while (!_disposed) {
      final client = PsuClient(url: url);
      try {
        await client.connect();
        _client = client;
        _serviceReachable = true;
        _lastError = null;
        notifyListeners();

        final stateSub = client.states.listen(_onState);
        final sampleSub = client.samples.listen(_onSample);
        try {
          _state = await client.getState();
          _mergeHistory(await client.getHistory(maxAge: historyLength));
          notifyListeners();
          await client.done;
        } finally {
          await stateSub.cancel();
          await sampleSub.cancel();
        }
      } on Object catch (e) {
        _lastError = e.toString();
        if (autoStartService && _client == null) await _tryStartService();
      }
      _client = null;
      _serviceReachable = false;
      _state = _state.copyWith(connected: false);
      notifyListeners();
      await client.close().catchError((_) {});
      if (!_disposed) await Future<void>.delayed(reconnectDelay);
    }
  }

  /// Attempts to launch the service at most once every 15 seconds.
  Future<void> _tryStartService() async {
    final now = DateTime.now();
    if (_lastStartAttempt != null &&
        now.difference(_lastStartAttempt!) < const Duration(seconds: 15)) {
      return;
    }
    _lastStartAttempt = now;
    _startingService = true;
    notifyListeners();
    try {
      await ServiceLauncher(url: url).ensureRunning();
      _lastError = null;
    } on Object catch (e) {
      _lastError = e.toString();
    } finally {
      _startingService = false;
      notifyListeners();
    }
  }

  void _onState(PsuState s) {
    _state = s;
    notifyListeners();
  }

  void _onSample(Sample s) {
    _history.add(s);
    _trim();
    _state = _state.copyWith(lastSample: s);
    notifyListeners();
  }

  void _mergeHistory(List<Sample> samples) {
    final existing = _history.toList();
    _history
      ..clear()
      ..addAll(samples);
    final lastT = samples.isEmpty ? null : samples.last.timestamp;
    for (final s in existing) {
      if (lastT == null || s.timestamp.isAfter(lastT)) _history.add(s);
    }
    _trim();
  }

  void _trim() {
    if (_history.isEmpty) return;
    final cutoff = _history.last.timestamp.subtract(historyLength);
    var drop = 0;
    while (drop < _history.length &&
        _history[drop].timestamp.isBefore(cutoff)) {
      drop++;
    }
    if (drop > 0) _history.removeRange(0, drop);
  }

  PsuClient _require() {
    final c = _client;
    if (c == null) throw PsuServiceException('service not reachable');
    return c;
  }

  Future<void> setVoltage(double volts) async =>
      _onState(await _require().setVoltage(volts));
  Future<void> setCurrent(double amps) async =>
      _onState(await _require().setCurrent(amps));
  Future<void> setOutput(bool on) async =>
      _onState(await _require().setOutput(on));

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close();
    super.dispose();
  }
}
