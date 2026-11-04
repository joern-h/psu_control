import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:psu_protocol/psu_protocol.dart';

Future<void> main(List<String> arguments) async {
  // A closed stdout pipe (e.g. `psu watch | head`) surfaces as an async
  // EPIPE error on the stdout sink; treat it as a normal end, not a crash.
  runZonedGuarded(() => _main(arguments), (e, st) {
    if (e is FileSystemException && e.osError?.errorCode == 32) exit(0);
    stderr.writeln('error: $e');
    exit(1);
  });
}

Future<void> _main(List<String> arguments) async {
  final runner =
      CommandRunner<int>('psu', 'Control the Owon SPE6103 through psu_service.')
        ..argParser.addOption(
          'url',
          abbr: 'u',
          defaultsTo: defaultServiceUrl,
          help: 'WebSocket URL of psu_service.',
        )
        ..argParser.addFlag(
          'autostart',
          defaultsTo: true,
          help: 'Start psu_service if it is not running.',
        )
        ..addCommand(StatusCommand())
        ..addCommand(SetCommand())
        ..addCommand(OnCommand())
        ..addCommand(OffCommand())
        ..addCommand(CycleCommand())
        ..addCommand(WatchCommand())
        ..addCommand(ScpiCommand())
        ..addCommand(ServiceCommand());

  try {
    exit(await runner.run(arguments) ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  } on PsuServiceException catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(1);
  } on Object catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}

/// Shared connect/close plumbing for all commands.
abstract class PsuCommand extends Command<int> {
  Future<int> runWithClient(PsuClient client);

  @override
  Future<int> run() async {
    final url = globalResults!['url'] as String;
    final client = PsuClient(url: url);
    try {
      await client.connect();
    } on Object catch (e) {
      if (!(globalResults!['autostart'] as bool)) {
        stderr.writeln('cannot reach psu_service at $url: $e');
        return 2;
      }
      try {
        await ServiceLauncher(
          url: url,
          log: (m) => stderr.writeln(m),
        ).ensureRunning();
        await client.connect();
      } on Object catch (e) {
        stderr.writeln('cannot reach or start psu_service at $url: $e');
        return 2;
      }
    }
    try {
      return await runWithClient(client);
    } finally {
      await client.close();
    }
  }
}

String fmtV(double v) => '${v.toStringAsFixed(3)} V';
String fmtA(double a) => '${a.toStringAsFixed(3)} A';
String fmtW(double w) => '${w.toStringAsFixed(2)} W';

void printState(PsuState s) {
  if (!s.connected) {
    stdout.writeln(
      'PSU:      not connected${s.error == null ? '' : ' (${s.error})'}',
    );
    return;
  }
  final m = s.lastSample;
  stdout
    ..writeln('PSU:      ${s.identity}')
    ..writeln('Output:   ${s.outputOn ? 'ON' : 'OFF'}')
    ..writeln('Setpoint: ${fmtV(s.setVoltage)}  ${fmtA(s.setCurrent)}')
    ..writeln('Limits:   OVP ${fmtV(s.ovpLimit)}  OCP ${fmtA(s.ocpLimit)}');
  if (m != null) {
    stdout.writeln(
      'Measured: ${fmtV(m.voltage)}  ${fmtA(m.current)}  ${fmtW(m.power)}',
    );
  }
}

class StatusCommand extends PsuCommand {
  @override
  final name = 'status';
  @override
  final description =
      'Show setpoints, output state and the latest measurement.';

  @override
  Future<int> runWithClient(PsuClient client) async {
    printState(await client.getState());
    return 0;
  }
}

class SetCommand extends PsuCommand {
  SetCommand() {
    argParser
      ..addOption(
        'voltage',
        abbr: 'v',
        help: 'Voltage setpoint in volts (0-$maxVoltage).',
      )
      ..addOption(
        'current',
        abbr: 'c',
        help: 'Current limit in amperes (0-$maxCurrent).',
      );
  }

  @override
  final name = 'set';
  @override
  final description = 'Set voltage and/or current limit.';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final v = argResults!['voltage'] as String?;
    final c = argResults!['current'] as String?;
    if (v == null && c == null) {
      throw UsageException('specify --voltage and/or --current', usage);
    }
    PsuState? state;
    if (v != null) state = await client.setVoltage(_parse(v, 'voltage'));
    if (c != null) state = await client.setCurrent(_parse(c, 'current'));
    stdout.writeln(
      'Setpoint: ${fmtV(state!.setVoltage)}  ${fmtA(state.setCurrent)}',
    );
    return 0;
  }

  double _parse(String s, String what) =>
      double.tryParse(s.replaceAll(',', '.')) ??
      (throw UsageException('invalid $what "$s"', usage));
}

class OnCommand extends PsuCommand {
  @override
  final name = 'on';
  @override
  final description = 'Enable the output.';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final s = await client.setOutput(true);
    stdout.writeln('Output: ${s.outputOn ? 'ON' : 'OFF'}');
    return 0;
  }
}

class OffCommand extends PsuCommand {
  @override
  final name = 'off';
  @override
  final description = 'Disable the output.';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final s = await client.setOutput(false);
    stdout.writeln('Output: ${s.outputOn ? 'ON' : 'OFF'}');
    return 0;
  }
}

class CycleCommand extends PsuCommand {
  @override
  final name = 'cycle';
  @override
  final description =
      'Power-cycle the output: [sleep,] off, wait, on. Only allowed while the output is on.';
  @override
  String get invocation => 'psu cycle [waiting_seconds] [sleep_seconds]';
  @override
  String get usageFooter => '''
Positional arguments:
  waiting_seconds  Off time between off and on (default 3).
  sleep_seconds    Delay before switching off (default 0).''';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final rest = argResults!.rest;
    if (rest.length > 2) {
      throw UsageException('too many arguments', usage);
    }
    final waiting = rest.isNotEmpty
        ? _seconds(rest[0], 'waiting_seconds')
        : 3.0;
    final sleep = rest.length > 1 ? _seconds(rest[1], 'sleep_seconds') : 0.0;

    final state = await client.getState();
    if (!state.connected) {
      stderr.writeln('PSU is not connected');
      return 2;
    }
    if (!state.outputOn) {
      stderr.writeln('output is OFF; cycle only works while the output is on');
      return 1;
    }
    if (sleep > 0) {
      stdout.writeln('Sleeping ${sleep}s before switching off ...');
      await _delay(sleep);
    }
    var s = await client.setOutput(false);
    stdout.writeln('Output: ${s.outputOn ? 'ON' : 'OFF'}');
    if (s.outputOn) {
      stderr.writeln('failed to switch the output off, aborting');
      return 1;
    }
    stdout.writeln('Waiting ${waiting}s ...');
    await _delay(waiting);
    s = await client.setOutput(true);
    stdout.writeln('Output: ${s.outputOn ? 'ON' : 'OFF'}');
    return s.outputOn ? 0 : 1;
  }

  double _seconds(String raw, String what) {
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null || v < 0 || !v.isFinite) {
      throw UsageException('invalid $what "$raw"', usage);
    }
    return v;
  }

  Future<void> _delay(double seconds) =>
      Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));
}

class WatchCommand extends PsuCommand {
  WatchCommand() {
    argParser
      ..addFlag(
        'csv',
        help: 'Print "iso-timestamp,volts,amps,watts" lines instead of a live display.',
      )
      ..addOption(
        'seconds',
        abbr: 's',
        help: 'Stop after this many seconds (default: until Ctrl-C).',
      );
  }

  @override
  final name = 'watch';
  @override
  final description = 'Stream live measurements.';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final csv = argResults!['csv'] as bool;
    final secs = argResults!['seconds'] as String?;
    final done = Completer<void>();
    final sigint = ProcessSignal.sigint.watch().listen((_) => done.complete());
    if (secs != null) {
      Timer(Duration(milliseconds: (double.parse(secs) * 1000).round()), () {
        if (!done.isCompleted) done.complete();
      });
    }
    unawaited(
      client.done.then((_) {
        if (!done.isCompleted) done.complete();
      }),
    );

    var outputOn = (await client.getState()).outputOn;
    final stateSub = client.states.listen((s) => outputOn = s.outputOn);
    if (csv) stdout.writeln('timestamp,voltage,current,power');
    final sampleSub = client.samples.listen((m) {
      if (csv) {
        stdout.writeln(
          '${m.timestamp.toIso8601String()},${m.voltage},${m.current},${m.power.toStringAsFixed(3)}',
        );
      } else {
        final line =
            '${m.timestamp.toIso8601String().substring(11, 23)}  '
            '${outputOn ? 'ON ' : 'OFF'}  ${fmtV(m.voltage)}  ${fmtA(m.current)}  ${fmtW(m.power)}';
        stdout.write(stdout.hasTerminal ? '\r$line\x1b[K' : '$line\n');
      }
    });

    await done.future;
    await sampleSub.cancel();
    await stateSub.cancel();
    await sigint.cancel();
    if (!csv && stdout.hasTerminal) stdout.writeln();
    return 0;
  }
}

class ScpiCommand extends PsuCommand {
  @override
  final name = 'scpi';
  @override
  final description = 'Send a raw SCPI command (queries print their reply).';
  @override
  final invocation = 'psu scpi "<command>"';

  @override
  Future<int> runWithClient(PsuClient client) async {
    final rest = argResults!.rest;
    if (rest.isEmpty) throw UsageException('missing SCPI command', usage);
    final reply = await client.scpi(rest.join(' '));
    if (reply != null) stdout.writeln(reply);
    return 0;
  }
}

/// `psu service start|stop|restart|status` — manages the daemon itself.
class ServiceCommand extends Command<int> {
  ServiceCommand() {
    addSubcommand(_ServiceStart());
    addSubcommand(_ServiceStop());
    addSubcommand(_ServiceRestart());
    addSubcommand(_ServiceStatus());
  }

  @override
  final name = 'service';
  @override
  final description = 'Start, stop or inspect psu_service.';
}

abstract class _ServiceSub extends Command<int> {
  String get url => globalResults!['url'] as String;

  Future<bool> reachable() async {
    final c = PsuClient(url: url, timeout: const Duration(seconds: 2));
    try {
      await c.connect();
      return true;
    } on Object {
      return false;
    } finally {
      await c.close().catchError((_) {});
    }
  }

  Future<int> start() async {
    if (await reachable()) {
      stdout.writeln('psu_service already running at $url');
      return 0;
    }
    await ServiceLauncher(url: url, log: stderr.writeln).ensureRunning();
    stdout.writeln(
      'psu_service started (log: ${ServiceLauncher.defaultLogFile})',
    );
    return 0;
  }

  Future<int> stop() async {
    final c = PsuClient(url: url, timeout: const Duration(seconds: 2));
    try {
      await c.connect();
    } on Object {
      stdout.writeln('psu_service is not running at $url');
      return 0;
    }
    try {
      await c.shutdownService();
    } finally {
      await c.close().catchError((_) {});
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!await reachable()) {
        stdout.writeln('psu_service stopped');
        return 0;
      }
    }
    stderr.writeln('psu_service acknowledged shutdown but is still listening');
    return 1;
  }
}

class _ServiceStart extends _ServiceSub {
  @override
  final name = 'start';
  @override
  final description = 'Start psu_service if it is not running.';
  @override
  Future<int> run() => start();
}

class _ServiceStop extends _ServiceSub {
  @override
  final name = 'stop';
  @override
  final description = 'Ask a running psu_service to exit.';
  @override
  Future<int> run() => stop();
}

class _ServiceRestart extends _ServiceSub {
  @override
  final name = 'restart';
  @override
  final description = 'Stop and start psu_service.';
  @override
  Future<int> run() async {
    final rc = await stop();
    return rc != 0 ? rc : start();
  }
}

class _ServiceStatus extends _ServiceSub {
  @override
  final name = 'status';
  @override
  final description = 'Report whether psu_service is reachable.';
  @override
  Future<int> run() async {
    if (await reachable()) {
      stdout.writeln('psu_service running at $url');
      return 0;
    }
    stdout.writeln('psu_service not running at $url');
    return 3;
  }
}
