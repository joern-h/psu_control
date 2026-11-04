import 'serial_link.dart';

/// SCPI driver for the Owon SPE/SP series (verified on an SPE6103, FW 5.5.0).
///
/// Command terminator is `\n`, replies end with `\r\n`. Set commands do not
/// produce a reply; queries return a single line.
class OwonSpe {
  OwonSpe(this.link);

  final SerialLink link;

  /// `OWON,SPE6103,<serial>,FV:V5.5.0`
  Future<String> identify() => link.query('*IDN?');

  Future<double> getVoltageSetpoint() => _queryDouble('VOLT?');
  Future<double> getCurrentSetpoint() => _queryDouble('CURR?');

  /// Over-voltage protection threshold.
  Future<double> getOvpLimit() => _queryDouble('VOLT:LIM?');

  /// Over-current protection threshold.
  Future<double> getOcpLimit() => _queryDouble('CURR:LIM?');

  Future<bool> getOutput() async =>
      (await link.query('OUTP?')).toUpperCase() == 'ON';

  Future<void> setVoltage(double volts) =>
      link.send('VOLT ${volts.toStringAsFixed(3)}');
  Future<void> setCurrent(double amps) =>
      link.send('CURR ${amps.toStringAsFixed(3)}');
  Future<void> setOutput(bool on) => link.send('OUTP ${on ? 'ON' : 'OFF'}');

  /// Measures output voltage and current in one round trip (`MEAS:ALL?`
  /// replies `<volts>,<amps>`).
  Future<(double volts, double amps)> measure() async {
    final reply = await link.query('MEAS:ALL?');
    final parts = reply.split(',');
    if (parts.length != 2) {
      throw SerialException('unexpected MEAS:ALL? reply "$reply"');
    }
    return (_parse(parts[0], reply), _parse(parts[1], reply));
  }

  /// Raw pass-through. Returns the reply for queries, null for set commands.
  Future<String?> raw(String command) {
    final c = command.trim();
    if (c.endsWith('?')) return link.query(c);
    return link.send(c).then((_) => null);
  }

  Future<double> _queryDouble(String cmd) async {
    final reply = await link.query(cmd);
    return _parse(reply, reply);
  }

  double _parse(String s, String full) =>
      double.tryParse(s.trim()) ??
      (throw SerialException('cannot parse number from "$full"'));
}
