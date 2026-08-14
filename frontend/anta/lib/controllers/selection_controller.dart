import 'dart:async';

import '../models/movable_item.dart';

/// In-memory controller that holds the current multi-select state for the
/// folder content page. Exposes a broadcast stream so widgets can react
/// without rebuilding the whole page.
///
/// One instance per page (do NOT register globally) — selection state is
/// inherently view-scoped.
class SelectionController {
  final Map<MovableItemRef, MovableItemRef> _selected = {};
  final _changesController = StreamController<Set<MovableItemRef>>.broadcast();
  // Tracks whether the user is in selection mode independently of how many
  // items are currently selected. Without this, "deselect all" would exit
  // the mode entirely (because isActive would flip to false).
  bool _modeActive = false;

  Stream<Set<MovableItemRef>> get changes => _changesController.stream;

  bool get isActive => _modeActive || _selected.isNotEmpty;
  int get count => _selected.length;
  Set<MovableItemRef> get items => _selected.values.toSet();

  bool contains(MovableItemRef ref) => _selected.containsKey(ref);

  void toggle(MovableItemRef ref) {
    if (_selected.containsKey(ref)) {
      _selected.remove(ref);
    } else {
      _selected[ref] = ref;
      _modeActive = true;
    }
    _emit();
  }

  void add(MovableItemRef ref) {
    if (_selected.containsKey(ref)) {
      return;
    }
    _selected[ref] = ref;
    _modeActive = true;
    _emit();
  }

  /// Deselect every item but stay in selection mode. Use this for the
  /// app-bar "deselect all" action.
  void deselectAll() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _emit();
  }

  /// Exit selection mode entirely. Use this for the app-bar cancel/back
  /// actions.
  void clear() {
    final wasActive = _modeActive || _selected.isNotEmpty;
    _selected.clear();
    _modeActive = false;
    if (wasActive) _emit();
  }

  void _emit() {
    if (_changesController.isClosed) return;
    _changesController.add(items);
  }

  void dispose() {
    _changesController.close();
  }
}
