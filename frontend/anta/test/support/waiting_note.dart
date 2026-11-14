import 'package:anta/services/fresh_preferences.dart';
import 'package:anta/services/shared_refresh/shared_refresh_message_gate.dart';

/// Whether a message's work for [pair] is noted as waiting to start, as the
/// store says now — what the background handler asks of its one read of
/// the store (`SharedRefreshMessageGate.waitsIn`).
Future<bool> waits(String pair, {DateTime? now}) async =>
    SharedRefreshMessageGate.waitsIn(
      await FreshPreferences.read(),
      pair,
      now: now,
    );
