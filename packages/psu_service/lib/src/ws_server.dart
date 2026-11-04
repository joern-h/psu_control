import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:psu_protocol/psu_protocol.dart';

import 'psu_controller.dart';

/// WebSocket front end of the service. Every connected client receives all
/// sample and state events; requests are answered individually.
class PsuWsServer {
  PsuWsServer(this.controller, {Log? log, this.onShutdownRequested})
    : _log = log ?? ((_) {});

  final PsuController controller;
  final Log _log;

  /// Called after a client's `shutdown` request has been acknowledged.
  final void Function()? onShutdownRequested;

  HttpServer? _server;
  final _clients = <WebSocket>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];

  Future<void> start(InternetAddress address, int port) async {
    _server = await HttpServer.bind(address, port);
    _log('listening on ws://${address.address}:$port');

    _subscriptions.add(
      controller.samples.listen((s) => _broadcast(SampleEvent(s))),
    );
    _subscriptions.add(
      controller.states.listen((s) => _broadcast(StateEvent(s))),
    );

    _server!.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.upgradeRequired
          ..write('psu_service: WebSocket endpoint')
          ..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _onClient(socket, request.connectionInfo?.remoteAddress.address ?? '?');
    });
  }

  void _onClient(WebSocket socket, String peer) {
    _clients.add(socket);
    _log('client connected ($peer), ${_clients.length} total');
    // Push the current state immediately so the client does not have to ask.
    socket.add(jsonEncode(StateEvent(controller.state).toJson()));

    socket.listen(
      (raw) => _handle(socket, raw),
      onDone: () {
        _clients.remove(socket);
        _log('client disconnected ($peer), ${_clients.length} total');
      },
      onError: (Object e) {
        _clients.remove(socket);
        _log('client error ($peer): $e');
      },
      cancelOnError: true,
    );
  }

  Future<void> _handle(WebSocket socket, dynamic raw) async {
    Request request;
    try {
      request = Request.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );
    } on Object catch (e) {
      socket.add(
        jsonEncode(Response.error(-1, 'malformed request: $e').toJson()),
      );
      return;
    }

    Response response;
    try {
      response = Response.ok(request.id, await _dispatch(request));
    } on Object catch (e) {
      response = Response.error(request.id, e.toString());
    }
    if (socket.readyState == WebSocket.open) {
      socket.add(jsonEncode(response.toJson()));
    }
    if (request.type == RequestType.shutdown && response.ok) {
      _log('shutdown requested by client');
      onShutdownRequested?.call();
    }
  }

  Future<Object?> _dispatch(Request request) async {
    final p = request.params;
    switch (request.type) {
      case RequestType.getState:
        return controller.state.toJson();
      case RequestType.getHistory:
        final seconds = p['seconds'] as num?;
        final samples = controller.history(
          maxAge: seconds == null ? null : Duration(seconds: seconds.toInt()),
        );
        return [for (final s in samples) s.toJson()];
      case RequestType.setVoltage:
        return (await controller.setVoltage(_number(p, 'value'))).toJson();
      case RequestType.setCurrent:
        return (await controller.setCurrent(_number(p, 'value'))).toJson();
      case RequestType.setOutput:
        final on = p['on'];
        if (on is! bool) throw const FormatException('"on" must be a boolean');
        return (await controller.setOutput(on)).toJson();
      case RequestType.scpi:
        final command = p['command'];
        if (command is! String || command.trim().isEmpty) {
          throw const FormatException('"command" must be a non-empty string');
        }
        return controller.scpi(command);
      case RequestType.shutdown:
        return null;
    }
  }

  double _number(Map<String, dynamic> p, String key) {
    final v = p[key];
    if (v is num) return v.toDouble();
    throw FormatException('"$key" must be a number');
  }

  void _broadcast(Event event) {
    if (_clients.isEmpty) return;
    final payload = jsonEncode(event.toJson());
    for (final c in _clients.toList()) {
      if (c.readyState == WebSocket.open) c.add(payload);
    }
  }

  Future<void> stop() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    for (final c in _clients.toList()) {
      await c.close(WebSocketStatus.goingAway, 'service shutting down');
    }
    await _server?.close(force: true);
  }
}
