import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/golden_fonts.dart';
import 'support/tolerant_comparator.dart';

/// Every suite under `test/goldens/` runs through here: the tolerant
/// comparator replaces the byte-exact one, and the real fonts are loaded
/// before the first pump. Scoped to this directory so the rest of the suite
/// keeps the test font its geometry assertions were written against.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final current = goldenFileComparator as LocalFileComparator;
  // The bootstrap built the current comparator for the test file being run;
  // a file name under the same directory keeps golden paths relative to it.
  goldenFileComparator = TolerantGoldenComparator(
    current.basedir.resolve('golden_test.dart'),
  );
  await loadGoldenFonts();
  await testMain();
}
