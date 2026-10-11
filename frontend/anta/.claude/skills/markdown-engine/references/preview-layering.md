# Preview layering

Reference, not rules — moved verbatim from the markdown-engine SKILL.md on 2026-10-11. Read only the part the task needs.

Contents — each entry is the verbatim start of a line below (bullet marker dropped), each nested entry a verbatim fragment inside that line (a bold run or a sentence opening), so `grep -n -F` finds it:

- Related docs: [docs/markdown-feature-ideas.md]…
  - The full invariant list lives in…
- Deprecated since 2026-09-03: gated by `SettingsKeys.previewModeEnabled`…
  - The page's `_canPreview` (`previewModeEnabled || !liveMarkdownRendering`)…
  - When `_canPreview` is false nothing below mounts or runs.
- Toolbar: `_buildMarkdownBar()` is the one `MarkdownBar(...)` tree — never duplicate it.
  - Since 2026-09-07 the loading state builds **no** chrome at all…
  - Add a new async render input to that gate, not to a post-mount refresh.

The introduction's links were written for SKILL.md, one folder up — from here `docs/` is `../../../../docs/` — and its `COPILOT_CONTEXT.md` sections (retired) now live in this folder: "Markdown Preview Pipeline", "Markdown Block Model And Chunking" and "Markdown Lists" in `preview-pipeline.md`, "Ghost Text" in `inline-syntaxes.md`. The deprecation line sat directly above the layering diagram, which stays in SKILL.md with the section's other rule lines; "nothing below" is that diagram.

## From the introduction

Related docs: [docs/markdown-feature-ideas.md](../../../docs/markdown-feature-ideas.md) (candidate features + fit analysis), [docs/tag-system-roadmap.md](../../../docs/tag-system-roadmap.md) (tag feature plan), and [docs/live-markdown-editor-roadmap.md](../../../docs/live-markdown-editor-roadmap.md) (live editor rendering — status, decision log, remaining gaps). The full invariant list lives in [COPILOT_CONTEXT.md](../../../COPILOT_CONTEXT.md) sections "Markdown Preview Pipeline", "Markdown Block Model And Chunking", "Markdown Lists", and "Ghost Text".

## From "Preview pipeline layering (keep intact)"

Deprecated since 2026-09-03: gated by `SettingsKeys.previewModeEnabled` (default off, under Settings → "Deprecated features"). The page's `_canPreview` (`previewModeEnabled || !liveMarkdownRendering`) decides whether the preview can exist at all and `_showPreview` (computed once per build) whether it is the visible surface right now — gate new preview-touching code on those two, never on `_isPreviewMode` directly. When `_canPreview` is false nothing below mounts or runs.

- Toolbar: `_buildMarkdownBar()` is the one `MarkdownBar(...)` tree — never duplicate it. Since 2026-09-07 the loading state builds **no** chrome at all: `_isLoading` gates the whole body (content, settings bundle, stored position, money config + palette, and the bar bloc's answer — Loaded or Error) and the finished body fades in through one `AnimatedSwitcher` (`AppConstants.animationDuration`), so nothing half-built ever shifts or restyles. Add a new async render input to that gate, not to a post-mount refresh.
