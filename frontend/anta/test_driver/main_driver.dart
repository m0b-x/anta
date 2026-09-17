import 'package:anta/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

import 'qa_agent.dart';

void main() {
  final agent = QaAgent();
  enableFlutterDriverExtension(
    handler: agent.handle,
    enableTextEntryEmulation: false,
  );
  agent.install();
  app.main();
}
