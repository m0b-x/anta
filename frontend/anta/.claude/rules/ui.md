---
paths:
  - "lib/widgets/**"
  - "lib/pages/**"
  - "lib/constants/form_metrics.dart"
  - "lib/constants/row_metrics.dart"
  - "lib/constants/app_bar_metrics.dart"
  - "lib/constants/surface_roles.dart"
  - "lib/constants/app_theme.dart"
---
# Visual work — loads when a widget, page or UI-language constant is touched

- Decide the idiom before the layout: grouped form rows, the browser's content rows, the settings kit, or a takeover page — they are never mixed in one surface. Load the `ui-language` skill for the primitives, the sheet chrome and the metrics; `ui-mock` for a mock (one, by default); `ui-revamp` for a rework.
- A surface on the language reads `FormMetrics` / `RowMetrics` / `AppBarMetrics` / `SurfaceRoles` by name — no literal numbers, nothing from the generic `AppSpacing` scale.
- Sheet bottom clearance is `max(viewInsets.bottom, viewPadding.bottom)` read through `MediaQuery` (never `View.of`) — the most-repeated bug in this app's history.
- Stable layouts: nothing moves under the finger, 48 dp targets, captions change text not geometry, disabled instead of hidden; light and dark, en/de/ro, text scale 2.0 and both phone sizes (360 × 780, 412 × 915) are part of done.
- Every new sheet ships with its widget suite (robots in `test/widgets/support/`) and a `SemanticsIds` entry for anything a device script targets.
- Snackbars go through `CustomSnackbar`; on a page whose Scaffold does not resize for the keyboard (the note editor, the calendar page) they ride `OverlaySnackbar`, whose body re-anchors on every inset change — never bake a keyboard inset into a `SnackBar.margin`, it is fixed at show time and strands the bar mid-screen when the IME closes (2026-10-19). Any geometry that depends on the keyboard is read in `build` and tested with the inset going both up and down.
