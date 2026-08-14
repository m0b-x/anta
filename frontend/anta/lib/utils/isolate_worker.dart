import 'dart:async';
import 'dart:isolate';

class _DiffPayload {
  final String original;
  final String modified;

  _DiffPayload(Map<String, dynamic> map)
    : original = map['original'] as String,
      modified = map['modified'] as String;
}

class IsolateResult<T> {
  final T? data;
  final String? error;

  IsolateResult({this.data, this.error});

  bool get isSuccess => error == null;
}

class _IsolateMessage {
  final SendPort sendPort;
  final String operation;
  final dynamic payload;

  _IsolateMessage(this.sendPort, this.operation, this.payload);
}

class IsolateWorker {
  static Future<IsolateResult<T>> run<T>(
    String operation,
    dynamic payload,
  ) async {
    final receivePort = ReceivePort();
    final message = _IsolateMessage(receivePort.sendPort, operation, payload);

    await Isolate.spawn(_isolateEntryPoint, message);

    final result = await receivePort.first;
    receivePort.close();

    if (result is Map && result.containsKey('error')) {
      return IsolateResult<T>(error: result['error'] as String);
    }

    return IsolateResult<T>(data: result as T);
  }

  static void _isolateEntryPoint(_IsolateMessage message) {
    try {
      final result = _processOperation(message.operation, message.payload);
      message.sendPort.send(result);
    } catch (e) {
      message.sendPort.send({'error': e.toString()});
    }
  }

  static dynamic _processOperation(String operation, dynamic payload) {
    switch (operation) {
      case 'computeDiff':
        return _computeDiffInIsolate(
          _DiffPayload(payload as Map<String, dynamic>),
        );

      default:
        throw UnsupportedError('Unknown operation: $operation');
    }
  }

  static Map<String, dynamic> _computeDiffInIsolate(_DiffPayload payload) {
    final original = payload.original;
    final modified = payload.modified;

    if (original == modified) {
      return {'hasChanges': false};
    }

    final originalLines = original.split('\n');
    final modifiedLines = modified.split('\n');

    final changes = <Map<String, dynamic>>[];

    int i = 0;
    int j = 0;

    while (i < originalLines.length || j < modifiedLines.length) {
      if (i >= originalLines.length) {
        changes.add({'type': 'add', 'line': j, 'content': modifiedLines[j]});
        j++;
      } else if (j >= modifiedLines.length) {
        changes.add({'type': 'remove', 'line': i, 'content': originalLines[i]});
        i++;
      } else if (originalLines[i] == modifiedLines[j]) {
        i++;
        j++;
      } else {
        changes.add({
          'type': 'modify',
          'originalLine': i,
          'modifiedLine': j,
          'original': originalLines[i],
          'modified': modifiedLines[j],
        });
        i++;
        j++;
      }
    }

    return {
      'hasChanges': true,
      'changes': changes,
      'originalLength': original.length,
      'modifiedLength': modified.length,
    };
  }
}

class IsolatePool {
  final int poolSize;
  final List<Isolate> _isolates = [];
  final List<SendPort> _sendPorts = [];
  final List<bool> _available = [];
  final List<Completer<int>> _waitingForWorker = [];
  bool _isInitialized = false;

  IsolatePool({this.poolSize = 4});

  Future<void> initialize() async {
    if (_isInitialized) return;

    for (int i = 0; i < poolSize; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _poolWorkerEntryPoint,
        receivePort.sendPort,
      );

      final sendPort = await receivePort.first as SendPort;

      _isolates.add(isolate);
      _sendPorts.add(sendPort);
      _available.add(true);
    }

    _isInitialized = true;
  }

  static void _poolWorkerEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _PoolTask) {
        try {
          final result = IsolateWorker._processOperation(
            message.operation,
            message.payload,
          );
          message.resultPort.send({'success': true, 'data': result});
        } catch (e) {
          message.resultPort.send({'success': false, 'error': e.toString()});
        }
      }
    });
  }

  Future<IsolateResult<T>> execute<T>(String operation, dynamic payload) async {
    await initialize();

    final workerIndex = await _getAvailableWorker();

    try {
      final resultPort = ReceivePort();
      final task = _PoolTask(operation, payload, resultPort.sendPort);

      _sendPorts[workerIndex].send(task);

      final result = await resultPort.first as Map<String, dynamic>;
      resultPort.close();

      if (result['success'] == true) {
        return IsolateResult<T>(data: result['data'] as T);
      } else {
        return IsolateResult<T>(error: result['error'] as String);
      }
    } finally {
      _releaseWorker(workerIndex);
    }
  }

  Future<int> _getAvailableWorker() async {
    for (int i = 0; i < _available.length; i++) {
      if (_available[i]) {
        _available[i] = false;
        return i;
      }
    }

    final completer = Completer<int>();
    _waitingForWorker.add(completer);
    return completer.future;
  }

  void _releaseWorker(int index) {
    if (_waitingForWorker.isNotEmpty) {
      final completer = _waitingForWorker.removeAt(0);
      completer.complete(index);
    } else {
      _available[index] = true;
    }
  }

  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _sendPorts.clear();
    _available.clear();
    _isInitialized = false;
  }
}

class _PoolTask {
  final String operation;
  final dynamic payload;
  final SendPort resultPort;

  _PoolTask(this.operation, this.payload, this.resultPort);
}
