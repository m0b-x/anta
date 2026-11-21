/// How the pairing's snapshot listeners come back after a listen ended in
/// an error (`PairingService`): never at once, since a listen the server
/// refuses would otherwise be asked again for the life of the process, and
/// never never, since a transient error must not leave the phone deaf to
/// its partner for good.
abstract final class PairingLimits {
  /// The wait before the first listen again; each further error in a row
  /// doubles it.
  static const Duration relistenFirst = Duration(seconds: 2);

  /// The longest wait between two listens: how late, at worst, a phone
  /// whose listen kept failing hears its partner once the cause is gone.
  static const Duration relistenCeiling = Duration(minutes: 5);
}
