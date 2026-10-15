/// One in-flight slot shared by every sheet a calendar page opens.
///
/// A fast double tap (or a tap landing while a route transition is still
/// running) pushes the same modal twice; dismissing one then reveals a
/// pixel-identical copy underneath, which reads as a sheet that refuses to
/// close. Owned by the page's state — the calendar's and the overview's — and
/// handed down, so it survives the rebuilds that reconstruct the widgets
/// below it.
///
/// Only entry points from a gesture go through [run]. A sheet opened from
/// inside an already-running body — the detail sheet's editor loop, the
/// template picker's fallback — is intentional and calls the unguarded body
/// directly, so the slot is never re-checked below the top of the trip.
class SheetGuard {
  bool _open = false;

  bool get isOpen => _open;

  Future<T?> run<T>(Future<T> Function() body) async {
    if (_open) return null;
    _open = true;
    try {
      return await body();
    } finally {
      _open = false;
    }
  }
}
