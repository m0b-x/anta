/// Which geometry the custom-colour picker offers for hue and saturation.
///
/// Persisted by name through `SettingsService`, so [fromName] falls back to
/// [square] for values written by a newer build rather than throwing.
enum ColorPickerMode {
  /// Saturation across, brightness down, for one hue chosen on a slider. The
  /// default: two independent Cartesian axes over the whole area, which is
  /// the easier target one-handed.
  square,

  /// Hue around, saturation out from the centre, with brightness on a slider.
  /// The opt-in: polar-coupled and harder to aim, but the shape a lot of
  /// people have used for years and reach for by habit.
  wheel;

  static ColorPickerMode fromName(String? name) {
    return ColorPickerMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ColorPickerMode.square,
    );
  }
}
