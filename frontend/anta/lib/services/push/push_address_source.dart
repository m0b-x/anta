import '../../models/pair_record.dart';

/// Where this phone's push address comes from: the address the relay sends
/// to (`docs/cloud-shared-freshness.md` §7, decision m). A seam, so the
/// registry holds no plugin type and its suite decides the answers.
abstract interface class PushAddressSource {
  /// The kind every address of this source is ([PairPushDevice.kindFid]).
  String get kind;

  /// Each address the platform names, the last one replayed to a new
  /// listener: an installation renewed by the system names a new one
  /// without being asked.
  Stream<String> get addresses;

  /// Registers this phone if it has not, and answers its address; null when
  /// the platform could not name one. Only ever asked while a pair needs it:
  /// an install that never paired never registers.
  Future<String?> current();

  /// Whether this install holds an address, or still owes the end of one:
  /// what every leave asks before it does anything. Read from preferences
  /// already in memory — no statement, no network.
  Future<bool> holds();

  /// Ends the address for good (decision n): the old one can no longer
  /// receive, and the next [current] names a different one. Nothing is
  /// asked of the platform unless [holds].
  Future<void> giveUp();

  /// Finishes the end of an address a [giveUp] could not complete — at a
  /// launch, for an install that may never pair again. Nothing at all
  /// unless one is owed.
  Future<void> payOwed();
}

/// Bound wherever push cannot work — not Android, no Firebase, a QA build,
/// the run with the app closed: no address, and nothing to give up.
class NoOpPushAddressSource implements PushAddressSource {
  const NoOpPushAddressSource();

  @override
  String get kind => PairPushDevice.kindFid;

  @override
  Stream<String> get addresses => const Stream<String>.empty();

  @override
  Future<String?> current() async => null;

  @override
  Future<bool> holds() async => false;

  @override
  Future<void> giveUp() async {}

  @override
  Future<void> payOwed() async {}
}
