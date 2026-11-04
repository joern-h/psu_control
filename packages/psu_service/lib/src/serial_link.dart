import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when the serial link fails (device gone, timeout, ...).
class SerialException implements Exception {
  SerialException(this.message);
  final String message;

  @override
  String toString() => 'SerialException: $message';
}

/// Line-oriented serial link built on `dart:io` and `stty`.
///
/// The device node is configured with `stty` once and then used as two plain
/// file handles: a read stream and a write handle. All transactions are
/// serialized, so a reply can always be matched to the command that caused it.
class SerialLink {
  SerialLink(
    this.path, {
    this.baudRate = 115200,
    this.replyTimeout = const Duration(milliseconds: 800),
  });

  final String path;
  final int baudRate;
  final Duration replyTimeout;

  RandomAccessFile? _writer;
  StreamSubscription<String>? _reader;
  final _lines = StreamController<String>.broadcast();
  Future<void> _queue = Future.value();
  bool _open = false;

  bool get isOpen => _open;

  /// Lines received that were not consumed by a [query] (should be rare).
  Stream<String> get lines => _lines.stream;

  Future<void> open() async {
    if (_open) return;
    if (!File(path).existsSync()) throw SerialException('$path does not exist');

    final stty = await Process.run('stty', [
      '-F', path, '$baudRate',
      'cs8', '-cstopb', '-parenb', // 8N1
      '-crtscts', '-ixon', '-ixoff', // no flow control
      'raw', '-echo', '-echoe', '-echok', '-icrnl', '-onlcr',
      'min',
      '1',
      'time',
      '0', // blocking read, return as soon as 1 byte is there
    ]);
    if (stty.exitCode != 0) {
      throw SerialException('stty failed: ${(stty.stderr as String).trim()}');
    }

    _writer = await File(path).open(mode: FileMode.writeOnly);
    _reader = File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _lines.add(line.trimRight()),
          onError: (Object e) => _fail('read error: $e'),
          onDone: () => _fail('port closed'),
        );
    _open = true;
    // Give stale bytes from a previous session a moment to drain; lines that
    // arrive while nobody is waiting for a reply are dropped.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  void _fail(String reason) {
    if (!_open) return;
    _open = false;
    _lines.addError(SerialException(reason));
    _writer?.close().ignore();
    _writer = null;
    _reader?.cancel().ignore();
    _reader = null;
  }

  /// Closes the port. The read side is cancelled without waiting: a blocking
  /// tty read cannot be interrupted, so awaiting it could hang forever.
  Future<void> close() async {
    _open = false;
    _reader?.cancel().ignore();
    _reader = null;
    await _writer?.close();
    _writer = null;
  }

  /// Sends [command] (terminator appended) and does not wait for a reply.
  Future<void> send(String command) => _enqueue(() => _write(command));

  /// Sends [command] and waits for exactly one reply line.
  Future<String> query(String command) => _enqueue(() async {
    // Subscribe before writing so a fast reply cannot be missed.
    final completer = Completer<String>();
    final sub = _lines.stream.listen(
      (line) {
        if (!completer.isCompleted) completer.complete(line);
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    try {
      await _write(command);
      return await completer.future.timeout(
        replyTimeout,
        onTimeout: () => throw SerialException('no reply to "$command"'),
      );
    } finally {
      await sub.cancel();
    }
  });

  Future<void> _write(String command) async {
    final w = _writer;
    if (w == null || !_open) throw SerialException('port not open');
    // RandomAccessFile writes are unbuffered; flush() would fsync, which a
    // tty rejects with EINVAL.
    await w.writeString('$command\n');
  }

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
