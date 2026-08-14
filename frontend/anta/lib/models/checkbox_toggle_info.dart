/// Describes a checkbox toggle originating from the markdown preview.
///
/// [start] / [end] are source offsets of the checkbox bracket
/// (`[ ]` or `[x]`) in the note content, and [replacement] is the new
/// bracket text to write back. Emitted by the preview and applied by
/// the editor page against the live editing controller.
class CheckboxToggleInfo {
  final int start;
  final int end;
  final String replacement;

  const CheckboxToggleInfo({
    required this.start,
    required this.end,
    required this.replacement,
  });
}
