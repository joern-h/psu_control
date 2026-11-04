import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:psu_protocol/psu_protocol.dart';
import 'package:psu_service/psu_service.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'device',
      abbr: 'd',
      defaultsTo: '/dev/ttyPowerSupply',
      help: 'Serial device node of the PSU.',
    )
    ..addOption(
      'bind',
      abbr: 'b',
      defaultsTo: '127.0.0.1',
      help: 'Address to listen on.',
    )
    ..addOption(
      'port',
      abbr: 'p',
      defaultsTo: '$defaultServicePort',
      help: 'TCP port to listen on.',
    )
    ..addOption(
      'poll-ms',
      defaultsTo: '200',
      help: 'Measurement interval in milliseconds.',
    )
    ..addOption(
      'history',
      defaultsTo: '3600',
      help: 'Seconds of samples to retain for new clients.',
    )
    ..addOption(
      'log-file',
      help: 'Append log output to this file instead of stderr.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Log every client connection.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }
  if (args['help'] as bool) {
    stdout.writeln('Usage: psu_service [options]\n\n${parser.usage}');
    return;
  }

  IOSink logSink = stderr;
  if (args['log-file'] case final String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    logSink = file.openWrite(mode: FileMode.append);
  }
  void log(String m) =>
      logSink.writeln('[${DateTime.now().toIso8601String()}] $m');

  final controller = PsuController(
    devicePath: args['device'] as String,
    pollInterval: Duration(milliseconds: int.parse(args['poll-ms'] as String)),
    historyLength: Duration(seconds: int.parse(args['history'] as String)),
    log: log,
  );
  late final PsuWsServer server;
  Future<void> shutdown(String reason) async {
    log('$reason, shutting down');
    await server.stop();
    await controller.stop();
    await logSink.flush();
    exit(0);
  }

  server = PsuWsServer(
    controller,
    log: log,
    onShutdownRequested: () => shutdown('shutdown requested'),
  );

  final bind = InternetAddress(args['bind'] as String);
  final port = int.parse(args['port'] as String);
  // Connect to the PSU first so the initial state is known before clients
  // are accepted; a missing device fails fast and we still start listening.
  await controller.start();
  try {
    await server.start(bind, port);
  } on SocketException catch (e) {
    log(
      'cannot listen on ${bind.address}:$port: ${e.osError?.message ?? e.message} (is another psu_service running?)',
    );
    await logSink.flush();
    exit(1);
  }

  ProcessSignal.sigint.watch().listen((s) => shutdown('received $s'));
  ProcessSignal.sigterm.watch().listen((s) => shutdown('received $s'));
}
