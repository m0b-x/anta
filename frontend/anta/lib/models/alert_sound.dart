import 'package:equatable/equatable.dart';

/// Which sound an **alarm-tier** alert plays, as the one value that is stored,
/// synced and carried in a backup.
///
/// Three things can be written into `EventAlert.sound` and into the
/// `alert_sound` setting, and this type is the only place that knows how to
/// tell them apart:
///
/// - **nothing chosen** — `null`, which only an alert can hold, and which means
///   *follow the `alert_sound` setting*. The setting itself is never null; its
///   own "nothing chosen" is the empty string, which reads as the phone's
///   default.
/// - **the phone's default alarm sound** — the literal [systemDefaultValue],
///   and the empty string. The phone's *current* default, whatever the Clock
///   app is set to at ring time: it is armed by handing the plugin no path at
///   all rather than the default's URI, so it keeps following that setting
///   instead of freezing the day's choice. The app ships no sound of its own
///   (2026-09-22) — the phone already has alarm sounds, and bundling one only
///   added to the install size.
/// - **a URI** (`content://…`) the user picked out of the phone's own sounds.
///
/// The value rides backups and syncs to other devices, where a URI can mean
/// nothing at all — the media id it names belongs to one phone's provider.
/// Decoding therefore **never throws and never yields silence**: anything this
/// build or this device cannot read is [AlertSoundSystemDefault], the one
/// sound every phone has.
sealed class AlertSound extends Equatable {
  const AlertSound();

  /// The stored literal for "the phone's own default alarm sound".
  ///
  /// Deliberately not the default URI itself: storing
  /// `content://settings/system/alarm_alert` would pin the sound the user had
  /// on the day they chose it, while this keeps following the Clock app.
  static const String systemDefaultValue = 'system:default';

  /// The URI scheme [systemDefaultValue] occupies, and which therefore can
  /// never be read as a picked sound.
  static const String _reservedScheme = 'system';

  /// What is written back into the alert row or into the setting. `null` only
  /// for [AlertSoundInherit], which exists on an alert alone.
  String? get stored;

  /// Whether this is a sound the phone has to resolve for us — the one case
  /// that can fail on a device other than the one that chose it.
  bool get needsDevice => this is AlertSoundUri;

  /// Reads one stored value. Total: every input maps to a sound, and an input
  /// this build cannot make sense of maps to the phone's default.
  static AlertSound decode(String? raw) {
    if (raw == null) return const AlertSoundInherit();
    if (raw.isEmpty || raw == systemDefaultValue) {
      return const AlertSoundSystemDefault();
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return const AlertSoundSystemDefault();
    if (uri.scheme == _reservedScheme) return const AlertSoundSystemDefault();
    // A bare scheme names nothing; the platform would fail to open it anyway,
    // and failing here costs one round trip less.
    if (raw.length <= uri.scheme.length + 1) {
      return const AlertSoundSystemDefault();
    }
    return AlertSoundUri(raw);
  }

  /// The sound one alert will actually be armed with: its own choice if it made
  /// one, else the app setting's, else the phone's default.
  ///
  /// Never returns [AlertSoundInherit] — "follow the setting" is a thing an
  /// alert stores, never a thing the platform can be handed.
  static AlertSound resolve({String? alert, required String setting}) {
    final chosen = decode(alert);
    if (chosen is! AlertSoundInherit) return chosen;
    final fallback = decode(setting);
    return fallback is AlertSoundInherit
        ? const AlertSoundSystemDefault()
        : fallback;
  }

  @override
  List<Object?> get props => [stored];
}

/// "Follow the app setting" — `null` on an alert, and the only value the
/// setting itself can never hold.
final class AlertSoundInherit extends AlertSound {
  const AlertSoundInherit();

  @override
  String? get stored => null;
}

/// The phone's current default alarm sound, whatever it is at ring time — and
/// the answer to every value this build or this device cannot resolve.
final class AlertSoundSystemDefault extends AlertSound {
  const AlertSoundSystemDefault();

  @override
  String get stored => AlertSound.systemDefaultValue;
}

/// A sound picked out of the phone, by the URI its own provider named it with.
///
/// Meaningless on any other device, which is what the degrade rule in
/// [AlertSound.decode]'s doc is about: the value still round-trips through a
/// backup and through sync untouched, and the device that cannot open it rings
/// its own default alarm instead of nothing.
final class AlertSoundUri extends AlertSound {
  final String uri;

  const AlertSoundUri(this.uri);

  @override
  String get stored => uri;
}
