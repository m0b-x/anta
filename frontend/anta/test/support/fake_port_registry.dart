import 'dart:isolate';

import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';

/// The process's port names as a map, so both sides of the handshake run in
/// one isolate over real ports.
class FakePortRegistry implements PortRegistry {
  final Map<String, SendPort> names = {};

  /// Every call, as `lookup:<name>`, `register:<name>` or `remove:<name>`.
  final List<String> calls = [];

  @override
  SendPort? lookup(String name) {
    calls.add('lookup:$name');
    return names[name];
  }

  @override
  bool register(SendPort port, String name) {
    calls.add('register:$name');
    if (names.containsKey(name)) return false;
    names[name] = port;
    return true;
  }

  @override
  bool remove(String name) {
    calls.add('remove:$name');
    return names.remove(name) != null;
  }
}
