/// Default TCP port the service listens on (loopback only).
const int defaultServicePort = 8765;

/// Default WebSocket URL of the service.
const String defaultServiceUrl = 'ws://127.0.0.1:$defaultServicePort';

/// Hard limits of the Owon SPE6103.
const double maxVoltage = 60.0;
const double maxCurrent = 10.0;

/// One measurement sample taken from the power supply.
class Sample {
  const Sample({
    required this.timestamp,
    required this.voltage,
    required this.current,
  });

  factory Sample.fromJson(Map<String, dynamic> json) => Sample(
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
    voltage: (json['v'] as num).toDouble(),
    current: (json['i'] as num).toDouble(),
  );

  final DateTime timestamp;

  /// Measured output voltage in volts.
  final double voltage;

  /// Measured output current in amperes.
  final double current;

  /// Output power in watts (V * I).
  double get power => voltage * current;

  Map<String, dynamic> toJson() => {
    't': timestamp.millisecondsSinceEpoch,
    'v': voltage,
    'i': current,
  };
}

/// Snapshot of the power supply state as known by the service.
class PsuState {
  const PsuState({
    required this.connected,
    this.identity,
    this.setVoltage = 0,
    this.setCurrent = 0,
    this.outputOn = false,
    this.ovpLimit = 0,
    this.ocpLimit = 0,
    this.lastSample,
    this.error,
  });

  factory PsuState.fromJson(Map<String, dynamic> json) => PsuState(
    connected: json['connected'] as bool,
    identity: json['identity'] as String?,
    setVoltage: (json['setVoltage'] as num?)?.toDouble() ?? 0,
    setCurrent: (json['setCurrent'] as num?)?.toDouble() ?? 0,
    outputOn: json['outputOn'] as bool? ?? false,
    ovpLimit: (json['ovpLimit'] as num?)?.toDouble() ?? 0,
    ocpLimit: (json['ocpLimit'] as num?)?.toDouble() ?? 0,
    lastSample: json['lastSample'] == null
        ? null
        : Sample.fromJson(json['lastSample'] as Map<String, dynamic>),
    error: json['error'] as String?,
  );

  /// Whether the service currently has a working serial link to the PSU.
  final bool connected;

  /// Reply to `*IDN?`, e.g. `OWON,SPE6103,12345678,FV:V5.5.0`.
  final String? identity;

  /// Voltage setpoint in volts.
  final double setVoltage;

  /// Current limit setpoint in amperes.
  final double setCurrent;

  /// Whether the output terminals are enabled.
  final bool outputOn;

  /// Over-voltage protection threshold in volts.
  final double ovpLimit;

  /// Over-current protection threshold in amperes.
  final double ocpLimit;

  /// Most recent measurement, if any.
  final Sample? lastSample;

  /// Last serial error message, if the link is down.
  final String? error;

  PsuState copyWith({
    bool? connected,
    String? identity,
    double? setVoltage,
    double? setCurrent,
    bool? outputOn,
    double? ovpLimit,
    double? ocpLimit,
    Sample? lastSample,
    String? error,
    bool clearError = false,
  }) => PsuState(
    connected: connected ?? this.connected,
    identity: identity ?? this.identity,
    setVoltage: setVoltage ?? this.setVoltage,
    setCurrent: setCurrent ?? this.setCurrent,
    outputOn: outputOn ?? this.outputOn,
    ovpLimit: ovpLimit ?? this.ovpLimit,
    ocpLimit: ocpLimit ?? this.ocpLimit,
    lastSample: lastSample ?? this.lastSample,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, dynamic> toJson() => {
    'connected': connected,
    'identity': identity,
    'setVoltage': setVoltage,
    'setCurrent': setCurrent,
    'outputOn': outputOn,
    'ovpLimit': ovpLimit,
    'ocpLimit': ocpLimit,
    'lastSample': lastSample?.toJson(),
    'error': error,
  };
}
