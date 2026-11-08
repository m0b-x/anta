part of re_editor;

typedef IsolateRunnable<Req, Res> = Res Function(Req req);
typedef IsolateCallback<Res> = void Function(Res res);

class _IsolateTasker<Req, Res> {
  final String name;
  late bool _closed;

  late IsolateManager<Res, Req>? _isolateManager;

  /// Set for a task whose newest request is the only one worth answering.
  LatestWinsQueue<Req, Res>? _latest;

  /// [latestWins] coalesces requests that arrive while one runs: only the
  /// newest is kept, and the result of a run it overtook is dropped. Find
  /// takes it — every edit used to queue one whole-document search behind
  /// another — while highlight and chunk analysis keep every run.
  _IsolateTasker(this.name, IsolateRunnable<Req, Res> runnable,
      {bool latestWins = false}) {
    _closed = false;
    _isolateManager = IsolateManager.create(
      runnable,
      concurrent: 1, // one is enough
    );
    if (latestWins) {
      _latest =
          LatestWinsQueue<Req, Res>((req) => _isolateManager!.compute(req));
    }
  }

  void run(Req req, IsolateCallback<Res> callback) async {
    if (_closed) {
      return;
    }
    final LatestWinsQueue<Req, Res>? latest = _latest;
    if (latest != null) {
      latest.run(req, callback);
      return;
    }
    _isolateManager?.compute(req, callback: (message) async {
      if (_closed) {
        return false;
      }
      callback(message);
      return true;
    });
  }

  void close() {
    _closed = true;
    _latest?.close();
    _isolateManager?.stop();
    _isolateManager = null;
  }
}

/// Runs one request at a time and keeps only the newest of those that
/// arrive meanwhile: when a run ends with a newer request waiting, its
/// result is dropped — the text it searched is already stale — and the
/// newest request starts instead. A failed run delivers nothing, as a
/// failed isolate run never did.
@visibleForTesting
class LatestWinsQueue<Req, Res> {
  LatestWinsQueue(this._execute);

  final Future<Res> Function(Req req) _execute;
  bool _running = false;
  bool _closed = false;
  bool _hasWaiting = false;
  Req? _waitingReq;
  IsolateCallback<Res>? _waitingCallback;

  void run(Req req, IsolateCallback<Res> callback) {
    if (_closed) {
      return;
    }
    if (_running) {
      _hasWaiting = true;
      _waitingReq = req;
      _waitingCallback = callback;
      return;
    }
    _start(req, callback);
  }

  void _start(Req req, IsolateCallback<Res> callback) {
    _running = true;
    _execute(req).then((Res res) {
      if (!_closed && !_startWaiting()) {
        callback(res);
      }
    }, onError: (Object error) {
      if (!_closed) {
        _startWaiting();
      }
    });
  }

  /// Starts the waiting request; `false` when none was waiting.
  bool _startWaiting() {
    if (!_hasWaiting) {
      _running = false;
      return false;
    }
    final Req req = _waitingReq as Req;
    final IsolateCallback<Res> callback = _waitingCallback!;
    _hasWaiting = false;
    _waitingReq = null;
    _waitingCallback = null;
    _start(req, callback);
    return true;
  }

  void close() {
    _closed = true;
    _hasWaiting = false;
    _waitingReq = null;
    _waitingCallback = null;
  }
}
