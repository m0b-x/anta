/// Supported single-note export/import file formats.
///
/// Folders are always exported as a `.zip` archive (see
/// [ImportExportService.exportFolder]) — that is not part of this enum
/// because folders cannot be flattened into a single note format.
enum ExportFormat {
  /// Structured, lossless. Preserves title, content, timestamps.
  json('json', 'application/json'),

  /// Markdown with the title as a level-1 heading prefix.
  markdown('md', 'text/markdown'),

  /// Raw note content with no metadata.
  text('txt', 'text/plain');

  final String extension;
  final String mimeType;

  const ExportFormat(this.extension, this.mimeType);

  static ExportFormat? fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceAll('.', '');
    for (final format in ExportFormat.values) {
      if (format.extension == normalized) return format;
    }
    return null;
  }
}
