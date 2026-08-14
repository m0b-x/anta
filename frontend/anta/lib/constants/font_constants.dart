/// Centralized font size constants for the application
class FontConstants {
  // Default font sizes
  static const double defaultFontSize = 16.0;
  static const double minFontSize = 10.0;
  static const double maxFontSize = 30.0;
  static const double fontSizeStep = 2.0;

  /// The font family used by the code editor (re_editor).
  /// When null, the platform default font is used.
  /// Must match the fontFamily set on CodeEditorStyle in ModernEditorWrapper.
  static const String? editorFontFamily = null;

  // Markdown header font sizes
  static const double h1 = 32.0;
  static const double h2 = 24.0;
  static const double h3 = 20.0;
  static const double h4 = 18.0;
  static const double h5 = 16.0;
  static const double h6 = 14.0;

  // UI text sizes
  static const double title = 18.0;
  static const double dialogTitle = 16.0;
  static const double body = 14.0;
  static const double caption = 12.0;
  static const double small = 13.0;
  static const double tiny = 10.0;

  // Specific UI elements
  static const double subtitle = 14.0;
  static const double label = 14.0;
}
