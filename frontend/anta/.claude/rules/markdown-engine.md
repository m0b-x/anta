---
paths:
  - "lib/utils/markdown_*.dart"
  - "lib/utils/ghost_text.dart"
  - "lib/utils/line_based_markdown_builder.dart"
  - "lib/utils/editor_input_policy.dart"
  - "lib/bloc/markdown_preview/**"
  - "lib/services/markdown_render_service.dart"
  - "lib/pages/optimized_note_editor_page.dart"
  - "lib/widgets/markdown_toolbar.dart"
  - "lib/widgets/source_mapped_markdown_view.dart"
  - "lib/controllers/**"
  - "packages/re_editor/**"
---
# Markdown engine and editor — loads when the engine, the editor page or the re_editor fork is touched

- **One grammar module per syntax** in `lib/utils/`, consumed by both the preview (`LineBasedMarkdownBuilder`) and the live editor (`MarkdownEditorSpanBuilder`). Never add a second regex or scanner for a construct that has a module; extend the module.
- **Offsets are sacred.** Every rendered span keeps its exact source offset; editor rendering conceals markers (transparent, ~0 width) or substitutes 1:1 — it never adds or drops code units, or caret, search and scroll mapping desync.
- The typing path is plain classes and `ChangeNotifier`s under `lib/controllers/`, never a BLoC; programmatic inserts go through `EditorEditTracker.runGuarded`; single-line edits use `CodeLines.replaceLine` / `removeLine`, never a `CodeLines.of([...])` rebuild.
- The fork is owned: add or change members when a feature needs it, but keep its optimizations (2-slot `asString` cache, bounded LRU paragraph cache, binary-search lookups, 50 ms highlight debounce, `cloneShallowDirty()`, capped undo). `dart analyze packages/re_editor/lib` after touching it.
- Load the `markdown-engine` skill before editing; its `references/` hold the pipeline, the money ledger, the inline syntaxes and the fork notes.
