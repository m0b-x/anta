import 'dart:io';

import 'app_ids.dart';
import 'paths.dart';
import 'ui_tree.dart';

/// The accessibility tree the agent most recently read, with its age.
class CachedDump {
  const CachedDump({required this.xml, required this.capturedAt});

  /// The raw capture: uiautomator XML on Android, the agent's JSON elsewhere.
  final String xml;
  final DateTime capturedAt;

  UiTree get tree => parseDumpText(xml, appPackage: antaPackage);

  Duration ageFrom(DateTime now) => now.difference(capturedAt);
}

/// Human wording for how long ago a dump was taken.
String describeAge(Duration age) {
  final seconds = age.inSeconds;
  if (seconds < 1) return 'just now';
  if (seconds < 120) return '$seconds s ago';
  final minutes = age.inMinutes;
  if (minutes < 120) return '$minutes min ago';
  return '${age.inHours} h ago';
}

/// Writes the newest dump so `#N` targets keep meaning what the agent read.
void writeDumpCache(QaPaths paths, String xml) {
  paths.ensureBuildQa();
  File(paths.lastDump).writeAsStringSync(xml);
  final legacy = File(paths.legacyLastDump);
  if (legacy.existsSync()) {
    try {
      legacy.deleteSync();
    } on FileSystemException {
      return;
    }
  }
}

/// The last dump, or null when nothing has been dumped in this project yet.
/// A cache left by the previous tool version (`last_dump.xml`) still counts.
CachedDump? readDumpCache(QaPaths paths) {
  var file = File(paths.lastDump);
  if (!file.existsSync()) file = File(paths.legacyLastDump);
  if (!file.existsSync()) return null;
  final String xml;
  try {
    xml = file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  if (xml.trim().isEmpty) return null;
  return CachedDump(xml: xml, capturedAt: file.statSync().modified);
}
