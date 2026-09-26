import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'paths.dart';
import 'placeholders.dart';

/// A seed fixture made ready for the device: placeholders resolved against
/// the run's clock and `--setting key=value` overrides folded into its
/// `settings` map, written under `build/qa/` so the fixture in the repo is
/// never edited.
class PreparedSeed {
  const PreparedSeed({
    required this.path,
    required this.placeholders,
    required this.settings,
  });

  /// The file to push as `qa_seed.json`.
  final String path;

  /// How many placeholders the fixture carried.
  final int placeholders;

  /// The settings overrides applied, in `key=value` form.
  final List<String> settings;

  /// The tail of the `qa_seed.json pushed from …` line.
  String describe() {
    final parts = <String>[];
    if (placeholders > 0) {
      parts.add('$placeholders placeholder${placeholders == 1 ? '' : 's'} resolved');
    }
    if (settings.isNotEmpty) parts.add('settings: ${settings.join(', ')}');
    return parts.isEmpty ? '' : ' (${parts.join('; ')})';
  }
}

/// Splits one `--setting` argument into its key and value.
///
/// The value may itself contain `=`; only the first one separates.
(String, String) parseSettingOverride(String raw) {
  final at = raw.indexOf('=');
  if (at <= 0 || at == raw.length - 1) {
    throw UsageFailure(
      '--setting takes key=value (got "$raw"); e.g. --setting locale=de '
      '--setting theme_mode=dark',
    );
  }
  return (raw.substring(0, at).trim(), raw.substring(at + 1));
}

/// Reads [sourcePath], resolves placeholders, applies [settings] and writes
/// the result to [QaPaths.seedResolved].
PreparedSeed prepareSeed(
  QaPaths paths,
  String sourcePath, {
  List<String> settings = const [],
  DateTime? now,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw UsageFailure('seed fixture not found: $sourcePath');
  }
  final raw = file.readAsStringSync();
  final placeholders = countPlaceholders(raw);
  var text = resolvePlaceholders(raw, now: now);
  final overrides = <String>[];
  if (settings.isNotEmpty) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw UsageFailure('seed fixture is not valid JSON after resolving: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw UsageFailure('seed fixture must be a JSON object');
    }
    final map = (decoded['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final entry in settings) {
      final (key, value) = parseSettingOverride(entry);
      map[key] = value;
      overrides.add('$key=$value');
    }
    decoded['settings'] = map;
    text = const JsonEncoder.withIndent('  ').convert(decoded);
  }
  final out = File(paths.seedResolved);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(text);
  return PreparedSeed(
    path: out.path,
    placeholders: placeholders,
    settings: overrides,
  );
}
