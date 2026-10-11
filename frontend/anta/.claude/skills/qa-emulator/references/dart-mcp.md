# Dart MCP

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

## Dart MCP tools

`qa run` and `qa attach` print the DTD URI and save it per device (`qa dtd`
reprints it; `qa dtd --vm` gives the VM service URI, which `relaunch` also
records). Then:

- `dtd` tool, command `connect`, `uri: <the ws:// URI>` — connects and lists
  the app. After a bare `relaunch` there is no DTD; the `vm_service` tool's
  `connect` takes the `--vm` URI instead.
- `get_runtime_errors` (`clearRuntimeErrors: true` to reset) — the app's
  uncaught exceptions. `qa errors` reads the same errors from the agent's
  buffer without the MCP.
- `hot_reload` / `hot_restart` — apply a code edit without rebuilding (needs
  the `flutter run` behind `qa run`; a `relaunch` ends that tool process).
- `widget_inspector`, command `get_widget_tree` (`summaryOnly: true`).
- `flutter_driver_command` — finders `ByTooltipMessage` (icon buttons),
  `ByText` (rows), `ByValueKey`; `BySemanticsLabel` finds almost nothing in
  this app. `enter_text` is disabled in the driver build — `qa type` types.
