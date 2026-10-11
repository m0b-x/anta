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
