/// The version the drawer's About row and the About dialog show — the part of
/// `pubspec.yaml`'s `version:` before the build number. Dart cannot read the
/// pubspec at run time, so this is a copy, and `app_version_test.dart` pins
/// it to the pubspec: a release bump that forgets it fails the suite.
const String kAppVersion = '1.0.0';

/// The app's mark the About dialog shows (D10): the launcher art
/// (`assets/icon/icon_master_flat.png`) cut to 192 px, so the dialog draws
/// what the home screen does rather than a glyph.
const String kAppIconAsset = 'assets/images/app_icon.png';
