class HybridLogicalClock {
  final String nodeId;
  int _logicalCounter;
  DateTime _lastPhysicalTime;

  HybridLogicalClock({required this.nodeId, int initialCounter = 0})
    : _logicalCounter = initialCounter,
      _lastPhysicalTime = DateTime.now();

  HlcTimestamp now() {
    final physicalTime = DateTime.now();

    if (physicalTime.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = physicalTime;
      _logicalCounter = 0;
    } else {
      _logicalCounter++;
    }

    return HlcTimestamp(
      wallTime: _lastPhysicalTime.millisecondsSinceEpoch,
      logicalCounter: _logicalCounter,
      nodeId: nodeId,
    );
  }

  HlcTimestamp receive(HlcTimestamp remote) {
    final physicalTime = DateTime.now();
    final remotePhysical = DateTime.fromMillisecondsSinceEpoch(remote.wallTime);

    if (physicalTime.isAfter(_lastPhysicalTime) &&
        physicalTime.isAfter(remotePhysical)) {
      _lastPhysicalTime = physicalTime;
      _logicalCounter = 0;
    } else if (remotePhysical.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = remotePhysical;
      _logicalCounter = remote.logicalCounter + 1;
    } else if (_lastPhysicalTime == remotePhysical) {
      _logicalCounter =
          (_logicalCounter > remote.logicalCounter
              ? _logicalCounter
              : remote.logicalCounter) +
          1;
    } else {
      _logicalCounter++;
    }

    return HlcTimestamp(
      wallTime: _lastPhysicalTime.millisecondsSinceEpoch,
      logicalCounter: _logicalCounter,
      nodeId: nodeId,
    );
  }

  void update(HlcTimestamp timestamp) {
    final remotePhysical = DateTime.fromMillisecondsSinceEpoch(
      timestamp.wallTime,
    );

    if (remotePhysical.isAfter(_lastPhysicalTime)) {
      _lastPhysicalTime = remotePhysical;
      _logicalCounter = timestamp.logicalCounter;
    } else if (remotePhysical == _lastPhysicalTime &&
        timestamp.logicalCounter > _logicalCounter) {
      _logicalCounter = timestamp.logicalCounter;
    }
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
