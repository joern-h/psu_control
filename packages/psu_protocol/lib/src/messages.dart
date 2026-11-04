import 'models.dart';

/// Request types a client may send to the service.
enum RequestType {
  getState,
  getHistory,
  setVoltage,
  setCurrent,
  setOutput,

  /// Raw SCPI pass-through, mainly for debugging. Queries (ending in `?`)
  /// return the reply string, other commands return null.
  scpi,

  /// Ask the service to exit gracefully.
  shutdown,
}

/// A request from a client to the service.
///
/// Wire format: `{"id": 1, "type": "setVoltage", "value": 12.0}`.
class Request {
  const Request({required this.id, required this.type, this.params = const {}});

  factory Request.fromJson(Map<String, dynamic> json) => Request(
    id: json['id'] as int,
    type: RequestType.values.byName(json['type'] as String),
    params: Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('type'),
  );

  final int id;
  final RequestType type;
  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, ...params};
}

/// A reply to a [Request]. Carries either a [result] or an [error].
///
/// Wire format: `{"id": 1, "ok": true, "result": {...}}`.
class Response {
  const Response.ok(this.id, [this.result]) : error = null;
  const Response.error(this.id, String this.error) : result = null;

  factory Response.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    if (json['ok'] == true) return Response.ok(id, json['result']);
    return Response.error(id, json['error'] as String? ?? 'unknown error');
  }

  final int id;
  final Object? result;
  final String? error;

  bool get ok => error == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ok': ok,
    if (ok) 'result': result else 'error': error,
  };
}

/// Unsolicited events pushed by the service to every connected client.
///
/// Wire format: `{"event": "sample", "data": {...}}`.
sealed class Event {
  const Event();

  static Event fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return switch (json['event'] as String) {
      'sample' => SampleEvent(Sample.fromJson(data)),
      'state' => StateEvent(PsuState.fromJson(data)),
      final other => throw FormatException('unknown event "$other"'),
    };
  }

  Map<String, dynamic> toJson();
}

/// A new measurement sample.
class SampleEvent extends Event {
  const SampleEvent(this.sample);
  final Sample sample;

  @override
  Map<String, dynamic> toJson() => {'event': 'sample', 'data': sample.toJson()};
}

/// The PSU state changed (setpoint, output, connection, ...).
class StateEvent extends Event {
  const StateEvent(this.state);
  final PsuState state;

  @override
  Map<String, dynamic> toJson() => {'event': 'state', 'data': state.toJson()};
}

/// Distinguishes a [Response] from an [Event] on the wire.
bool isEventMessage(Map<String, dynamic> json) => json.containsKey('event');
