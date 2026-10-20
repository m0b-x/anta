/// The snackbars' paddings, shared by the Scaffold bar `CustomSnackbar`
/// shows and the `OverlaySnackbar` that stands in for it over a page that
/// does not resize for the keyboard, so the two roads draw one bar.
abstract final class SnackbarMetrics {
  /// The bar's padding above and below its row, a `SnackBar`'s own around
  /// its message; a bar whose content brings its own 48 dp target passes
  /// [actionBarVerticalPadding] instead, so the target does not stack on it.
  static const double barVerticalPadding = 14;

  /// The vertical padding of a bar that carries an action: with the 48 dp
  /// action it makes a 56 dp bar, where the message's own padding around
  /// the action made it 76.
  static const double actionBarVerticalPadding = 4;

  /// A floating `SnackBar`'s own start padding, restated because passing a
  /// padding replaces the default whole.
  static const double barStartPadding = 16;
}
