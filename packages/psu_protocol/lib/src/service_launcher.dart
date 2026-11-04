import 'dart:async';
import 'dart:io';

import 'client.dart';
import 'models.dart';

/// Starts `psu_service` on demand so that CLI and UI work without the user
/// launching the daemon by hand.
///
/// Resolution order for the service:
/// 1. `systemctl --user start psu_service` if that unit is installed.
/// 2. The executable named by `$PSU_SERVICE_BIN`.
/// 3. `psu_service` next to the running executable.
/// 4. `~/.local/bin/psu_service`.
/// 5. `psu_service` on `$PATH`.
/// 6. When running from a source checkout: `dart run` on the service package.
class ServiceLauncher {
  ServiceLauncher({this.url = defaultServiceUrl, this.log});

  final String url;
  final void Function(String message)? log;

  /// Log file used when the service is spawned directly (not via systemd).
  static String get defaultLogFile {
    final state =
        Platform.environment['XDG_STATE_HOME'] ??
        '${Platform.environment['HOME'] ?? '.'}/.local/state';
    return '$state/psu_control/service.log';
  }

  /// Returns true once the service accepts connections. Does nothing if it is
  /// already running. Throws [ServiceLaunchException] if it cannot be started.
  Future<bool> ensureRunning({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (await _reachable()) return true;
    await start();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await _reachable()) return true;
    }
    throw ServiceLaunchException(
      'psu_service was started but did not come up within ${timeout.inSeconds}s (see $defaultLogFile)',
    );
  }

  Future<bool> _reachable() async {
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

  /// Spawns the service without waiting for it.
  Future<void> start() async {
    if (await _startViaSystemd()) return;

    final command = _locate();
    if (command == null) {
      throw ServiceLaunchException(
        'psu_service not found. Run deploy/install.sh or set PSU_SERVICE_BIN.',
      );
    }
    final logFile = defaultLogFile;
    Directory(File(logFile).parent.path).createSync(recursive: true);
    log?.call('starting ${command.join(' ')}');
    await Process.start(command.first, [
      ...command.skip(1),
      '--log-file',
      logFile,
    ], mode: ProcessStartMode.detached);
  }

  Future<bool> _startViaSystemd() async {
    try {
      final enabled = await Process.run('systemctl', [
        '--user',
        'is-enabled',
        'psu_service',
      ]).timeout(const Duration(seconds: 3));
      if (enabled.exitCode != 0) return false;
      log?.call('starting psu_service via systemd --user');
      final r = await Process.run('systemctl', [
        '--user',
        'start',
        'psu_service',
      ]).timeout(const Duration(seconds: 10));
      return r.exitCode == 0;
    } on Object {
      return false;
    }
  }

  List<String>? _locate() {
    final env = Platform.environment;
    final candidates = <String>[
      ?env['PSU_SERVICE_BIN'],
      '${File(Platform.resolvedExecutable).parent.path}/psu_service',
      if (env['HOME'] case final home?) '$home/.local/bin/psu_service',
      for (final dir in (env['PATH'] ?? '').split(':'))
        if (dir.isNotEmpty) '$dir/psu_service',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return [c];
    }

    // Development fallback: running from the workspace with `dart run`.
    final script = Platform.script.toFilePath();
    final marker = script.indexOf('/packages/psu_cli/');
    if (marker > 0) {
      final servicePackage =
          '${script.substring(0, marker)}/packages/psu_service';
      if (Directory(servicePackage).existsSync()) {
        return ['dart', 'run', '$servicePackage/bin/psu_service.dart'];
      }
    }
    return null;
  }
}

class ServiceLaunchException implements Exception {
  ServiceLaunchException(this.message);
  final String message;

  @override
  String toString() => message;
}
