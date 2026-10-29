class HybridLogicalClock {
  final String nodeId;
  final DateTime Function() _wallClock;
  int _logicalCounter;
  DateTime _lastPhysicalTime;
  Duration _seedAhead = Duration.zero;
  int _clampedRemotes = 0;

  /// How far a remote stamp's wall time may run ahead of this device's wall
  /// clock before [receive] and [update] stop following it; [adopt] follows
  /// it however far ahead it is and only counts it.
  ///
  /// What the guard still protects is the stamps this device has not stored:
  /// every stamp after a merge is above what was merged, so a device with a
  /// clock set years ahead would otherwise drag this one years ahead too on
  /// a stamp that may never be kept here. An hour absorbs ordinary skew
  /// between phones; what [adopt] gives up for a stamp already stored on a
  /// row of this database is its own doc's.
  static const Duration maxDrift = Duration(hours: 1);

  /// The largest counter the string encoding's four hex digits can carry;
  /// one more would sort below its predecessor as a string.
  static const int _maxCounter = 0xFFFF;

  /// [wallClock] stands in for `DateTime.now` so a test can put the wall
  /// behind a stored stamp.
  HybridLogicalClock({
    required this.nodeId,
    int initialCounter = 0,
    DateTime Function()? wallClock,
  }) : _wallClock = wallClock ?? DateTime.now,
       _logicalCounter = 0,
       _lastPhysicalTime = _toMillis((wallClock ?? DateTime.now)()) {
    _setCounter(initialCounter);
  }

  String? _persistedUpTo;

  /// The highest clock value this instance has claimed as stored, or null
  /// before its first claim. A claim, not proof of a write: a batch that
  /// carries the clock row claims when the batch is built, and a transaction
  /// that rolls back afterwards leaves the claim ahead of the store. That is
  /// safe because every later stamp is higher and stores itself again.
  ///
  /// `CrdtWrite` alone reads it and claims through [claimPersisted]; a value
  /// at or below it is already covered, so a multi-row action persists the
  /// clock once.
  String? get persistedUpTo => _persistedUpTo;

  /// Records [value] as stored — for `CrdtWrite` only. Never lowers the
  /// claim: a write that commits after a newer one does not undo it.
  void claimPersisted(String value) {
    final claimed = _persistedUpTo;
    if (claimed == null || value.compareTo(claimed) > 0) {
      _persistedUpTo = value;
    }
  }

  /// How far the last [seed] was ahead of the wall clock, zero when it was
  /// not. Reported rather than acted on: the seed is honoured however far
  /// ahead it is, since a capped seed would mint stamps below rows already
  /// written — the rollback persisting the clock exists to prevent.
  Duration get seedAhead => _seedAhead;

  /// How many remote stamps ran past [maxDrift] ahead of the wall clock —
  /// skew seen, not stamps held back.
  ///
  /// [receive] and [update] count the ones they hold. [adopt] counts a stamp
  /// whether or not this clock already covered it, so every page after a
  /// [seed] from a stored far-future stamp counts although its raise changes
  /// nothing, and a stamp this device minted itself counts once the user
  /// corrects a fast clock backwards and the device pulls its own rows back.
  int get clampedRemotes => _clampedRemotes;

  /// The current state without advancing it — what is persisted after a merge.
  HlcTimestamp get last => HlcTimestamp(
    wallTime: _lastPhysicalTime.millisecondsSinceEpoch,
    logicalCounter: _logicalCounter,
    nodeId: nodeId,
  );

  /// The wall clock at the precision a timestamp carries.
  ///
  /// `DateTime.now()` resolves to microseconds while [HlcTimestamp.wallTime]
  /// is milliseconds, so comparing the two at full precision let two stamps
  /// inside one millisecond — a later microsecond, the same millisecond —
  /// reset the counter and come out equal. Every comparison here is made on
  /// the truncated instant, which is what keeps a node's stamps strictly
  /// increasing.
  DateTime _wallMillis() => _toMillis(_wallClock());

  static DateTime _toMillis(DateTime instant) =>
      DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch);

  /// Raises the clock to [stored], the last stamp a previous run wrote, so
  /// no stamp of this run can sort below it even when the wall clock is
  /// behind. Never lowers the clock; any node's stamp is accepted.
  void seed(HlcTimestamp stored) {
    final storedPhysical = DateTime.fromMillisecondsSinceEpoch(stored.wallTime);
    final wall = _wallMillis();
    _seedAhead = storedPhysical.isAfter(wall)
        ? storedPhysical.difference(wall)
        : Duration.zero;
    _raiseTo(storedPhysical, stored.logicalCounter);
  }

  HlcTimestamp now() {
    final physicalTime = _wallMillis();

    if (physicalTime.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = physicalTime;
      _logicalCounter = 0;
    } else {
      _setCounter(_logicalCounter + 1);
    }

    return last;
  }

  HlcTimestamp receive(HlcTimestamp remote) {
    final physicalTime = _wallMillis();
    final guarded = _guard(remote, physicalTime);
    final remotePhysical = DateTime.fromMillisecondsSinceEpoch(
      guarded.wallTime,
    );

    if (physicalTime.isAfter(_lastPhysicalTime) &&
        physicalTime.isAfter(remotePhysical)) {
      _lastPhysicalTime = physicalTime;
      _logicalCounter = 0;
    } else if (remotePhysical.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = remotePhysical;
      _setCounter(guarded.logicalCounter + 1);
    } else if (_lastPhysicalTime == remotePhysical) {
      _setCounter(
        (_logicalCounter > guarded.logicalCounter
                ? _logicalCounter
                : guarded.logicalCounter) +
            1,
      );
    } else {
      _setCounter(_logicalCounter + 1);
    }

    return last;
  }

  void update(HlcTimestamp timestamp) {
    final guarded = _guard(timestamp, _wallMillis());
    _raiseTo(
      DateTime.fromMillisecondsSinceEpoch(guarded.wallTime),
      guarded.logicalCounter,
    );
  }

  /// Raises the clock to [stamp] past [maxDrift] as well — for a stamp this
  /// device has already stored on a row of its own.
  ///
  /// Held back instead, the clock would mint below that row, and the edit it
  /// stamps loses every later merge of it, has its outbox entry retired and
  /// is gone from the space with no park and no copy (A5 review R98). The
  /// stamp is honoured anyway at the next open — [seed] takes it unguarded
  /// and a pulled page stores it inside its own transaction — so the guard
  /// only shortened the loss to this run. A wrong clock elsewhere now moves
  /// this one forward; [clampedRemotes] records that the stamp ran past
  /// [maxDrift], no longer that the clock was held anywhere.
  void adopt(HlcTimestamp stamp) {
    if (stamp.wallTime > _wallMillis().add(maxDrift).millisecondsSinceEpoch) {
      _clampedRemotes++;
    }
    _raiseTo(
      DateTime.fromMillisecondsSinceEpoch(stamp.wallTime),
      stamp.logicalCounter,
    );
  }

  void _raiseTo(DateTime physical, int counter) {
    if (physical.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = physical;
      _setCounter(counter);
    } else if (physical == _lastPhysicalTime && counter > _logicalCounter) {
      _setCounter(counter);
    }
  }

  /// A counter past [_maxCounter] moves to the next millisecond instead, so
  /// the stamp still sorts after its predecessor as a string.
  void _setCounter(int counter) {
    if (counter > _maxCounter) {
      _lastPhysicalTime = _lastPhysicalTime.add(
        const Duration(milliseconds: 1),
      );
      _logicalCounter = 0;
    } else {
      _logicalCounter = counter;
    }
  }

  /// [remote] held to [maxDrift] past [wall], or never below where this clock
  /// already is, so a clamp cannot lower a seed that was itself far ahead.
  ///
  /// A remote at or below the clock passes unchanged and is not counted: it
  /// cannot pull the clock anywhere, so holding it would only lower what
  /// [receive] returns below the remote. A held stamp takes counter zero: its
  /// own counter ordered events at a wall time this clock does not adopt.
  HlcTimestamp _guard(HlcTimestamp remote, DateTime wall) {
    final limit = wall.add(maxDrift);
    final held = _lastPhysicalTime.isAfter(limit) ? _lastPhysicalTime : limit;
    if (remote.wallTime <= held.millisecondsSinceEpoch) return remote;
    _clampedRemotes++;
    return HlcTimestamp(
      wallTime: held.millisecondsSinceEpoch,
      logicalCounter: 0,
      nodeId: remote.nodeId,
    );
  }
}

class HlcTimestamp implements Comparable<HlcTimestamp> {
  final int wallTime;
  final int logicalCounter;
  final String nodeId;

  const HlcTimestamp({
    required this.wallTime,
    required this.logicalCounter,
    required this.nodeId,
  });

  factory HlcTimestamp.parse(String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid HLC timestamp: $encoded');
    }
    return HlcTimestamp(
      wallTime: int.parse(parts[0], radix: 16),
      logicalCounter: int.parse(parts[1], radix: 16),
      nodeId: parts[2],
    );
  }

  factory HlcTimestamp.zero(String nodeId) {
    return HlcTimestamp(wallTime: 0, logicalCounter: 0, nodeId: nodeId);
  }

  @override
  String toString() {
    final wallHex = wallTime.toRadixString(16).padLeft(12, '0');
    final counterHex = logicalCounter.toRadixString(16).padLeft(4, '0');
    return '$wallHex:$counterHex:$nodeId';
  }

  @override
  int compareTo(HlcTimestamp other) {
    final wallCompare = wallTime.compareTo(other.wallTime);
    if (wallCompare != 0) return wallCompare;

    final counterCompare = logicalCounter.compareTo(other.logicalCounter);
    if (counterCompare != 0) return counterCompare;

    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(HlcTimestamp other) => compareTo(other) > 0;
  bool operator <(HlcTimestamp other) => compareTo(other) < 0;
  bool operator >=(HlcTimestamp other) => compareTo(other) >= 0;
  bool operator <=(HlcTimestamp other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HlcTimestamp &&
        other.wallTime == wallTime &&
        other.logicalCounter == logicalCounter &&
        other.nodeId == nodeId;
  }

  @override
  int get hashCode => Object.hash(wallTime, logicalCounter, nodeId);

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(wallTime);

  HlcTimestamp increment() {
    return HlcTimestamp(
      wallTime: wallTime,
      logicalCounter: logicalCounter + 1,
      nodeId: nodeId,
    );
  }
}
