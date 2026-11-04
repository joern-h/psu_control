import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'messages.dart';
import 'models.dart';

/// Thrown when the service answers a request with an error.
class PsuServiceException implements Exception {
  PsuServiceException(this.message);
  final String message;

  @override
  String toString() => 'PsuServiceException: $message';
}

/// WebSocket client for `psu_service`, usable from Flutter and plain Dart.
///
/// Create it, call [connect], then use the typed methods. Events arrive on
/// [samples] and [states]; both are broadcast streams.
class PsuClient {
  PsuClient({
    this.url = defaultServiceUrl,
    this.timeout = const Duration(seconds: 5),
  });

  final String url;
  final Duration timeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _nextId = 1;
  final _pending = <int, Completer<Response>>{};
  final _samples = StreamController<Sample>.broadcast();
  final _states = StreamController<PsuState>.broadcast();
  final _disconnected = Completer<void>();

  Stream<Sample> get samples => _samples.stream;
  Stream<PsuState> get states => _states.stream;

  /// Completes when the connection to the service is closed or fails.
  Future<void> get done => _disconnected.future;

  bool get isConnected => _channel != null && !_disconnected.isCompleted;

  /// Opens the WebSocket. Throws if the service is not reachable.
  Future<void> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready.timeout(timeout);
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object e) => _close(e),
      onDone: () => _close(null),
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic raw) {
    final json = jsonDecode(raw as String) as Map<String, dynamic>;
    if (isEventMessage(json)) {
      switch (Event.fromJson(json)) {
        case SampleEvent(:final sample):
          _samples.add(sample);
        case StateEvent(:final state):
          _states.add(state);
      }
      return;
    }
    final response = Response.fromJson(json);
    _pending.remove(response.id)?.complete(response);
  }

  void _close(Object? error) {
    if (!_disconnected.isCompleted) _disconnected.complete();
    for (final c in _pending.values) {
      c.completeError(
        PsuServiceException(error?.toString() ?? 'connection closed'),
      );
    }
    _pending.clear();
    _channel = null;
  }

  Future<Object?> _call(
    RequestType type, [
    Map<String, dynamic> params = const {},
  ]) async {
    final channel = _channel;
    if (channel == null || _disconnected.isCompleted) {
      throw PsuServiceException('not connected to $url');
    }
    final id = _nextId++;
    final completer = Completer<Response>();
    _pending[id] = completer;
    channel.sink.add(
      jsonEncode(Request(id: id, type: type, params: params).toJson()),
    );
    final response = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw PsuServiceException('request ${type.name} timed out');
      },
    );
    if (!response.ok) throw PsuServiceException(response.error!);
    return response.result;
  }

  Future<PsuState> getState() async => PsuState.fromJson(
    await _call(RequestType.getState) as Map<String, dynamic>,
  );

  /// Returns the samples retained by the service, oldest first.
  Future<List<Sample>> getHistory({Duration? maxAge}) async {
    final result = await _call(RequestType.getHistory, {
      if (maxAge != null) 'seconds': maxAge.inSeconds,
    }) as List<dynamic>;
    return [for (final s in result) Sample.fromJson(s as Map<String, dynamic>)];
  }

  Future<PsuState> setVoltage(double volts) async => PsuState.fromJson(
    await _call(RequestType.setVoltage, {'value': volts})
        as Map<String, dynamic>,
  );

  Future<PsuState> setCurrent(double amps) async => PsuState.fromJson(
    await _call(RequestType.setCurrent, {'value': amps})
        as Map<String, dynamic>,
  );

  Future<PsuState> setOutput(bool on) async => PsuState.fromJson(
    await _call(RequestType.setOutput, {'on': on}) as Map<String, dynamic>,
  );

  /// Sends a raw SCPI command. Returns the reply for queries, null otherwise.
  Future<String?> scpi(String command) async =>
      await _call(RequestType.scpi, {'command': command}) as String?;

  /// Asks the service to exit. The connection closes shortly afterwards.
  Future<void> shutdownService() async {
    await _call(RequestType.shutdown);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _close(null);
    await _samples.close();
    await _states.close();
  }
}
