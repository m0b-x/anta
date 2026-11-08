import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/json_keys.dart';
import '../constants/temp_file_names.dart';
import '../models/calendar_event.dart';
import '../models/export_format.dart';
import '../models/folder.dart';
import '../models/item_label.dart';
import '../models/note_metadata.dart';
import '../repositories/note_repository.dart';
import '../utils/ics_serializer.dart';
import 'database_manager.dart';
import 'duplicate_name_exception.dart';
import 'folder_storage_service.dart';
import 'note_storage_service.dart';

/// Result of a successful export operation.
class ExportResult {
  /// Absolute path to the file written under the system temp directory.
  final String filePath;

  /// Format used for the export. Folders always report
  /// [ExportFormat.json] inside a `.zip` archive — see [isArchive].
  final ExportFormat? format;

  /// True when [filePath] is a `.zip` archive (folder export).
  final bool isArchive;

  /// Number of folders written into the archive (folder exports only).
  final int foldersExported;

  /// Number of notes written into the archive (folder exports only).
  final int notesExported;

  /// Number of calendar events written (calendar `.ics` exports only).
  final int eventsExported;

  /// False for a file the app keeps ([ExportResult.file]), which
  /// [ImportExportService.cleanupExport] must never delete.
  final bool isTemporary;

  /// True for the database share's snapshot, which sits alone in a folder of
  /// its own ([DatabaseManager.shareSnapshotPrefix]) that goes with it, and
  /// only once the share sheet is done reading it
  /// ([ImportExportService.shareExport]).
  final bool isSnapshot;

  const ExportResult({
    required this.filePath,
    this.format,
    this.isArchive = false,
    this.foldersExported = 0,
    this.notesExported = 0,
    this.eventsExported = 0,
  }) : isTemporary = true,
       isSnapshot = false;

  /// A file shared where it lives rather than written for the share, so
  /// [ImportExportService.shareExport] leaves it in place afterwards. No
  /// production path shares one today — the Databases page hands over a
  /// [ExportResult.snapshot] — and the guard stays for the next that does.
  const ExportResult.file(this.filePath)
    : format = null,
      isArchive = false,
      foldersExported = 0,
      notesExported = 0,
      eventsExported = 0,
      isTemporary = false,
      isSnapshot = false;

  /// The consistent copy of a database written for one share
  /// ([DatabaseManager.snapshotForShare]).
  const ExportResult.snapshot(this.filePath)
    : format = null,
      isArchive = false,
      foldersExported = 0,
      notesExported = 0,
      eventsExported = 0,
      isTemporary = true,
      isSnapshot = true;
}

/// Result of a successful import operation.
class ConvertImportResult {
  final int foldersImported;
  final int notesImported;

  /// Folder ids freshly created by the import. Useful for the UI to
  /// expand or scroll to the imported root.
  final List<String> createdRootFolderIds;

  const ConvertImportResult({
    this.foldersImported = 0,
    this.notesImported = 0,
    this.createdRootFolderIds = const [],
  });
}

/// Thrown when an archive's manifest declares an [archiveVersion] this
/// build doesn't know how to read. Surfaced through the bloc as a
/// failure state so the UI can prompt the user to upgrade.
class UnsupportedArchiveVersionException implements Exception {
  final int archiveVersion;
  final int supportedVersion;
  const UnsupportedArchiveVersionException({
    required this.archiveVersion,
    required this.supportedVersion,
  });

  @override
  String toString() =>
      'Archive version $archiveVersion is newer than supported version '
      '$supportedVersion. Please update the app to import this archive.';
}

/// Converts notes and folders to/from on-disk files for sharing and import.
///
/// Single notes are exported as one of the [ExportFormat] variants. Folders
/// are exported as a `.zip` archive that mirrors the folder tree on disk:
/// every folder becomes a directory, each contains a `_folder.json` with
/// its metadata, and each note becomes its own `.json` file. A top-level
/// `manifest.json` records archive version and timestamps.
///
/// All filesystem-bound names are sanitized with [_sanitizeFileName]; on
/// import, name collisions are resolved with a numeric suffix so existing
/// content is never overwritten.
class ImportExportService {
  static const String archiveVersionKey = 'version';
  static const int archiveVersion = 1;
  static const String _manifestFileName = 'manifest.json';
  static const String _folderMetaFileName = '_folder.json';
  static const String _archiveTypeFolder = 'folderArchive';
  static const String _archiveTypeNote = 'note';

  /// What every file and folder ANTA leaves in the system temp directory is
  /// named with ([TempFileNames.prefix]); [sweepStaleExports] deletes nothing
  /// else, because on Windows that directory is every app's.
  static const String tempPrefix = TempFileNames.prefix;

  /// The folder note files and archives are written into
  /// ([TempFileNames.exportDirectory]): their names are the user's titles,
  /// which carry no prefix the sweep could recognise.
  static const String exportDirectoryName = TempFileNames.exportDirectory;

  final NoteStorageService _noteStorage;
  final FolderStorageService _folderStorage;
  final NoteRepository _noteRepository;

  ImportExportService({
    required NoteStorageService noteStorage,
    required FolderStorageService folderStorage,
    required NoteRepository noteRepository,
  }) : _noteStorage = noteStorage,
       _folderStorage = folderStorage,
       _noteRepository = noteRepository;

  // ─── Note export ────────────────────────────────────────────────────────

  /// Write [metadata] (and its content) to a single file under
  /// [exportDirectoryName] in the system temp directory using [format] and
  /// return the resulting [ExportResult].
  Future<ExportResult> exportNote({
    required NoteMetadata metadata,
    required ExportFormat format,
  }) async {
    final content = await _noteRepository.loadContent(metadata.id);
    final body = _encodeNote(
      metadata: metadata,
      content: content,
      format: format,
    );

    final baseName = metadata.title.trim().isEmpty
        ? 'note_${metadata.id.substring(0, metadata.id.length.clamp(0, 8))}'
        : _sanitizeFileName(metadata.title);
    final fileName = '$baseName.${format.extension}';

    final file = File(p.join((await _exportDirectory()).path, fileName));
    await file.writeAsString(body);

    return ExportResult(filePath: file.path, format: format);
  }

  String _encodeNote({
    required NoteMetadata metadata,
    required String content,
    required ExportFormat format,
  }) {
    switch (format) {
      case ExportFormat.json:
        return const JsonEncoder.withIndent('  ').convert({
          JsonKeys.type: _archiveTypeNote,
          JsonKeys.title: metadata.title,
          JsonKeys.content: content,
          JsonKeys.createdAt: metadata.createdAt.toIso8601String(),
          JsonKeys.updatedAt: metadata.updatedAt.toIso8601String(),
          JsonKeys.label: metadata.label.storageName,
          JsonKeys.exportedAt: DateTime.now().toIso8601String(),
        });
      case ExportFormat.markdown:
        final title = metadata.title.trim().isEmpty
            ? 'Untitled'
            : metadata.title;
        return '# $title\n\n$content';
      case ExportFormat.text:
        return content;
    }
  }

  // ─── Folder export ──────────────────────────────────────────────────────

  /// Recursively export the folder identified by [folderId] (and everything
  /// nested under it) into a `.zip` archive in the system temp directory.
  ///
  /// [noteFormat] controls how individual note files are encoded inside the
  /// archive. Defaults to [ExportFormat.json] (lossless, round-trippable);
  /// pass [ExportFormat.markdown] / [ExportFormat.text] to make the archive
  /// human-readable at the cost of dropping per-note metadata on import.
  Future<ExportResult> exportFolder({
    required String folderId,
    ExportFormat noteFormat = ExportFormat.json,
  }) async {
    final root = await _folderStorage.getFolderById(folderId);
    if (root == null) {
      throw ArgumentError('Folder $folderId not found');
    }

    final counts = _Counts();
    final file = await _writeArchive((archive) async {
      await _walkFolderIntoArchive(
        archive: archive,
        folder: root,
        pathPrefix: '',
        noteFormat: noteFormat,
        counts: counts,
      );

      archive.addJson(_manifestFileName, {
        JsonKeys.type: _archiveTypeFolder,
        archiveVersionKey: archiveVersion,
        JsonKeys.exportedAt: DateTime.now().toIso8601String(),
        'rootName': root.name,
        'folderCount': counts.folders,
        'noteCount': counts.notes,
        'noteFormat': noteFormat.extension,
      });
      return _sanitizeFileName(root.name);
    });

    return ExportResult(
      filePath: file.path,
      isArchive: true,
      foldersExported: counts.folders,
      notesExported: counts.notes,
    );
  }

  /// Export an arbitrary mix of notes and folders into a single `.zip`.
  ///
  /// - Loose notes (referenced by [noteIds]) land at the archive root,
  ///   encoded with [noteFormat].
  /// - Each folder in [folderIds] becomes a top-level subdirectory
  ///   containing the same recursive layout produced by [exportFolder],
  ///   also using [noteFormat] for nested notes.
  /// - Name collisions at any level are resolved with a numeric suffix so
  ///   two siblings with the same title don't overwrite each other.
  /// - Missing ids are skipped silently (race with delete is not fatal);
  ///   if the entire selection resolves to nothing, throws [StateError].
  Future<ExportResult> exportItems({
    required Set<String> noteIds,
    required Set<String> folderIds,
    required ExportFormat noteFormat,
  }) async {
    if (noteIds.isEmpty && folderIds.isEmpty) {
      throw ArgumentError('exportItems requires at least one id');
    }

    final counts = _Counts();
    final usedRootNames = <String>{_manifestFileName.toLowerCase()};

    final file = await _writeArchive((archive) async {
      // The name of the last item the walk resolved — the only one when the
      // selection is a single item, which then names the archive. Taken from
      // the walk's own read, so the name is the one of the item exported.
      String? resolvedName;

      // Loose notes first so their filenames have first claim on root names.
      for (final id in noteIds) {
        final lazy = await _noteStorage.loadNoteWithContent(id);
        if (lazy == null) continue;
        final note = lazy.metadata;
        resolvedName = note.title;
        final base = note.title.trim().isEmpty
            ? 'note_${id.substring(0, id.length.clamp(0, 8))}'
            : _sanitizeFileName(note.title);
        final fileName = _uniqueName(
          '$base.${noteFormat.extension}',
          usedRootNames,
        );
        usedRootNames.add(fileName.toLowerCase());
        _addNoteFile(
          archive: archive,
          path: fileName,
          metadata: note,
          content: lazy.content ?? '',
          format: noteFormat,
        );
        counts.notes++;
      }

      // Then folders, each as a top-level subtree.
      for (final id in folderIds) {
        final folder = await _folderStorage.getFolderById(id);
        if (folder == null) continue;
        resolvedName = folder.name;
        final segment = _uniqueName(
          _sanitizeFileName(folder.name),
          usedRootNames,
        );
        usedRootNames.add(segment.toLowerCase());
        await _walkFolderIntoArchive(
          archive: archive,
          folder: folder,
          pathPrefix: '',
          segmentOverride: segment,
          noteFormat: noteFormat,
          counts: counts,
        );
      }

      if (counts.folders == 0 && counts.notes == 0) {
        throw StateError('Selection resolved to no exportable items');
      }

      archive.addJson(_manifestFileName, {
        JsonKeys.type: _archiveTypeFolder,
        archiveVersionKey: archiveVersion,
        JsonKeys.exportedAt: DateTime.now().toIso8601String(),
        'folderCount': counts.folders,
        'noteCount': counts.notes,
        'noteFormat': noteFormat.extension,
        'selection': true,
      });

      return (folderIds.length + noteIds.length) == 1
          ? _sanitizeFileName(resolvedName ?? 'selection')
          : 'selection';
    });

    return ExportResult(
      filePath: file.path,
      isArchive: true,
      foldersExported: counts.folders,
      notesExported: counts.notes,
    );
  }

  /// Recursive helper shared by [exportFolder] and [exportItems]. Walks
  /// [folder] and adds its `_folder.json` plus every note to [archive],
  /// honoring [noteFormat] for the note bodies.
  ///
  /// [pathPrefix] is the parent directory inside the archive; pass `''`
  /// for a root-level folder. [segmentOverride], when non-null, is used as
  /// this folder's directory name instead of its sanitized title — the
  /// caller's de-duplicated name, so two siblings whose names sanitize alike
  /// ("A:B" and "A_B", two long names sharing their first 100 characters,
  /// same-named folders a sync merge left side by side) never write the
  /// same entries, which an import would read as one folder.
  Future<void> _walkFolderIntoArchive({
    required _ArchiveWriter archive,
    required Folder folder,
    required String pathPrefix,
    required ExportFormat noteFormat,
    required _Counts counts,
    String? segmentOverride,
  }) async {
    counts.folders++;
    final segment = segmentOverride ?? _sanitizeFileName(folder.name);
    final dirPath = pathPrefix.isEmpty
        ? segment
        : p.posix.join(pathPrefix, segment);

    archive.addJson(p.posix.join(dirPath, _folderMetaFileName), {
      JsonKeys.type: 'folder',
      JsonKeys.name: folder.name,
      JsonKeys.createdAt: folder.createdAt.toIso8601String(),
      JsonKeys.noteSortOrder: folder.noteSortOrder,
      JsonKeys.subfolderSortOrder: folder.subfolderSortOrder,
      JsonKeys.label: folder.label.storageName,
    });

    final notes = await _noteStorage.loadAllMetadataForFolder(folder.id);
    final usedNames = <String>{_folderMetaFileName.toLowerCase()};
    for (final note in notes) {
      counts.notes++;
      final content = await _noteRepository.loadContent(note.id);
      final base = note.title.trim().isEmpty
          ? 'note_${note.id.substring(0, note.id.length.clamp(0, 8))}'
          : _sanitizeFileName(note.title);
      final fileName = _uniqueName('$base.${noteFormat.extension}', usedNames);
      usedNames.add(fileName.toLowerCase());
      _addNoteFile(
        archive: archive,
        path: p.posix.join(dirPath, fileName),
        metadata: note,
        content: content,
        format: noteFormat,
      );
    }

    // Child folders share the directory's names with its notes, the way the
    // archive root's folders share them with the loose notes.
    final children = await _folderStorage.loadAllFoldersForParent(folder.id);
    for (final child in children) {
      final childSegment = _uniqueName(
        _sanitizeFileName(child.name),
        usedNames,
      );
      usedNames.add(childSegment.toLowerCase());
      await _walkFolderIntoArchive(
        archive: archive,
        folder: child,
        pathPrefix: dirPath,
        segmentOverride: childSegment,
        noteFormat: noteFormat,
        counts: counts,
      );
    }
  }

  void _addNoteFile({
    required _ArchiveWriter archive,
    required String path,
    required NoteMetadata metadata,
    required String content,
    required ExportFormat format,
  }) {
    archive.addText(
      path,
      _encodeNote(metadata: metadata, content: content, format: format),
    );
  }

  /// Runs [write] over a `.zip` opened under a provisional name and, once it
  /// returns the archive's base name, closes the file and gives it its final
  /// `<base>_<timestamp>.zip` name — so a half-written archive never carries
  /// a name the share sheet or an import would take for a whole one. A walk
  /// that throws — the walk, or a write that fails — closes the file and
  /// deletes the partial archive.
  ///
  /// The failure path closes the handle itself, never the stream: closing
  /// the stream flushes its buffer first, and a flush that failed once fails
  /// again before the handle is closed — on Windows an open file cannot be
  /// deleted.
  Future<File> _writeArchive(
    Future<String> Function(_ArchiveWriter archive) write,
  ) async {
    final directory = await _exportDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final partial = File(p.join(directory.path, 'archive_$timestamp.part'));
    final handle = openArchiveHandle(partial.path);
    final archive = _ArchiveWriter(OutputFileStream.withFileHandle(handle));
    try {
      final baseName = await write(archive);
      await archive.close();
      return await partial.rename(
        p.join(directory.path, '${baseName}_$timestamp.zip'),
      );
    } catch (_) {
      try {
        await handle.close();
      } catch (_) {
        /* the delete below is what matters */
      }
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {
        /* left for sweepStaleExports */
      }
      rethrow;
    }
  }

  /// Opens the file an archive is written into; a test wraps it to watch
  /// each entry reach the file, or to fail a write or the close.
  @visibleForTesting
  AbstractFileHandle openArchiveHandle(String path) =>
      FileHandle(path, mode: FileAccess.write);

  /// [exportDirectoryName] under the system temp directory, created on
  /// first use.
  Future<Directory> _exportDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory(p.join(tempDir.path, exportDirectoryName));
    await directory.create(recursive: true);
    return directory;
  }

  // ─── Calendar export ────────────────────────────────────────────────────

  /// Write [events] to a single `.ics` file in the system temp directory.
  ///
  /// Reports [ExportResult.format] as `null`: iCalendar is not one of the
  /// note [ExportFormat]s and must not become one, or it would show up in
  /// every note-format picker. The `.ics` extension is registered with
  /// [sweepStaleExports] so abandoned exports are still cleaned up.
  Future<ExportResult> exportCalendar({
    required List<CalendarEvent> events,
  }) async {
    final body = IcsSerializer.serialize(events: events);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(tempDir.path, 'anta_events_$timestamp.ics'));
    await file.writeAsString(body);
    return ExportResult(filePath: file.path, eventsExported: events.length);
  }

  /// Write [text] — already composed by its caller, the report's Markdown —
  /// to [fileName] in the system temp directory, beside the `.ics` export,
  /// for [shareExport]. [fileName] carries [format]'s extension, so
  /// [sweepStaleExports] knows the file. A write that fails takes its
  /// half-written file with it, so no partial report waits for the sweep.
  Future<ExportResult> exportText({
    required String fileName,
    required String text,
    required ExportFormat format,
  }) async {
    assert(
      p.basename(fileName) == fileName &&
          p.extension(fileName) == '.${format.extension}',
      'exportText takes a bare file name with the format\'s extension: '
      '$fileName',
    );
    final tempDir = await getTemporaryDirectory();
    final result = ExportResult(
      filePath: p.join(tempDir.path, fileName),
      format: format,
    );
    try {
      await writeExportText(File(result.filePath), text);
    } catch (_) {
      await cleanupExport(result);
      rethrow;
    }
    return result;
  }

  /// The write behind [exportText]; a test overrides it to fail mid-file.
  @visibleForTesting
  Future<void> writeExportText(File file, String text) =>
      file.writeAsString(text);

  /// Convenience: hand the exported file to the OS share sheet, then
  /// delete it from the temp directory. The OS copies/streams the bytes
  /// through its own share intent before we get control back, so removing
  /// the file afterwards is safe and prevents the temp dir from
  /// accumulating exports across sessions.
  ///
  /// A database snapshot ([ExportResult.isSnapshot]) is the exception: it
  /// goes only once the sheet is done reading it ([_shareReleased]), else it
  /// waits for the next share or the launch sweep.
  Future<void> shareExport(ExportResult result) async {
    ShareResult? shared;
    try {
      shared = await SharePlus.instance.share(
        ShareParams(files: [XFile(result.filePath)]),
      );
    } finally {
      if (!result.isSnapshot || _shareReleased(shared)) {
        await cleanupExport(result);
      }
    }
  }

  /// Whether the share sheet is done with the file once `share()` returns.
  /// A share that threw ([shared] is null) never reached a sheet, and
  /// Android's share_plus copies the file into its own cache before the
  /// sheet opens (`Share.kt`, 13.3.0). A desktop sheet may still be reading
  /// the path, and `unavailable` does not say whether anything is.
  ///
  /// The platform is read through [defaultTargetPlatform] rather than
  /// `Platform.isAndroid` so a test can drive each branch; in the app the two
  /// name the same OS, and the share plugin is the one that OS loads.
  static bool _shareReleased(ShareResult? shared) =>
      shared == null ||
      (defaultTargetPlatform == TargetPlatform.android &&
          shared.status != ShareResultStatus.unavailable);

  /// Best-effort delete of a previously-produced export file — a snapshot's
  /// whole folder. Swallows IO errors — failing to delete a temp file is
  /// never worth blocking the user on.
  Future<void> cleanupExport(ExportResult result) async {
    if (!result.isTemporary) return;
    try {
      if (result.isSnapshot) {
        final folder = File(result.filePath).parent;
        // Never more than a folder the snapshot made, whatever path it got:
        // prefixed, and directly in the temp directory.
        final tempDir = await getTemporaryDirectory();
        if (p
                .basename(folder.path)
                .startsWith(DatabaseManager.shareSnapshotPrefix) &&
            p.equals(p.dirname(folder.path), tempDir.path) &&
            await folder.exists()) {
          await folder.delete(recursive: true);
        }
        return;
      }
      final file = File(result.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      /* non-fatal */
    }
  }

  /// Sweep stale export artefacts out of the system temp directory.
  /// Intended to be called from app startup so files left behind by a
  /// crash, a denied share dialog, or a previous build version don't
  /// accumulate. Only what is older than [maxAge] and named with
  /// [tempPrefix] is considered: every file in [exportDirectoryName] (a
  /// partial archive included), a database snapshot's folder, and a
  /// prefixed file at the top with one of the extensions this service
  /// writes (`anta_events_….ics`, the report's `anta_report_….md`).
  Future<void> sweepStaleExports({
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge);
      final knownExtensions = <String>{
        'zip',
        'ics',
        for (final f in ExportFormat.values) f.extension,
      };
      Future<void> deleteIfStale(FileSystemEntity entity) async {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          /* skip what we can't stat/delete */
        }
      }

      await for (final entity in tempDir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (!name.startsWith(tempPrefix)) continue;
        if (entity is Directory) {
          if (name == exportDirectoryName) {
            await for (final file in entity.list(followLinks: false)) {
              if (file is File) await deleteIfStale(file);
            }
          } else if (name.startsWith(DatabaseManager.shareSnapshotPrefix)) {
            await deleteIfStale(entity);
          }
        } else if (entity is File) {
          final ext = p.extension(name).toLowerCase().replaceAll('.', '');
          if (knownExtensions.contains(ext)) await deleteIfStale(entity);
        }
      }
    } catch (_) {
      /* swallow — startup hygiene is best-effort */
    }
  }

  // ─── Import ─────────────────────────────────────────────────────────────

  /// Import a single file at [filePath] into [targetFolderId]. The format
  /// is detected from the extension. ZIP files are routed to
  /// [importArchive]; everything else is treated as a single note.
  Future<ConvertImportResult> importFile({
    required String filePath,
    required String targetFolderId,
  }) async {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    if (ext == 'zip') {
      return importArchive(
        filePath: filePath,
        targetParentFolderId: targetFolderId,
      );
    }

    final file = File(filePath);
    final raw = await file.readAsString();
    final fallbackTitle = p.basenameWithoutExtension(filePath);

    final format = ExportFormat.fromExtension(ext) ?? ExportFormat.text;
    await _importNote(
      raw: raw,
      format: format,
      fallbackTitle: fallbackTitle,
      targetFolderId: targetFolderId,
    );
    return const ConvertImportResult(notesImported: 1);
  }

  Future<void> _importNote({
    required String raw,
    required ExportFormat format,
    required String fallbackTitle,
    required String targetFolderId,
  }) async {
    String title;
    String content;
    DateTime? createdAt;
    DateTime? updatedAt;
    var label = ItemLabel.none;

    switch (format) {
      case ExportFormat.json:
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('JSON note must be an object');
        }
        title = (decoded[JsonKeys.title] as String?) ?? fallbackTitle;
        content = (decoded[JsonKeys.content] as String?) ?? '';
        createdAt = _tryParseDate(decoded[JsonKeys.createdAt]);
        updatedAt = _tryParseDate(decoded[JsonKeys.updatedAt]);
        final rawLabel = decoded[JsonKeys.label];
        label = ItemLabel.fromName(rawLabel is String ? rawLabel : null);
      case ExportFormat.markdown:
        final lines = raw.split('\n');
        if (lines.isNotEmpty && lines.first.startsWith('# ')) {
          title = lines.first.substring(2).trim();
          content = lines.skip(1).join('\n').trimLeft();
        } else {
          title = fallbackTitle;
          content = raw;
        }
      case ExportFormat.text:
        title = fallbackTitle;
        content = raw;
    }

    await _createNoteWithUniqueTitle(
      folderId: targetFolderId,
      title: title,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      label: label,
    );
  }

  /// Parse an ISO-8601 string defensively. Returns null when the value
  /// is missing or malformed so the caller can fall back to "now".
  static DateTime? _tryParseDate(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  /// Import a folder archive (`.zip`) under [targetParentFolderId].
  /// `targetParentFolderId == null` imports at the root.
  ///
  /// The archive is read from the file, not loaded: decoding reads only its
  /// directory, and each entry's bytes are read when that entry is imported
  /// and dropped right after ([_consume]), so the peak is one entry.
  Future<ConvertImportResult> importArchive({
    required String filePath,
    String? targetParentFolderId,
  }) async {
    final input = InputFileStream(filePath);
    try {
      return await _importArchive(
        ZipDecoder().decodeStream(input),
        targetParentFolderId: targetParentFolderId,
      );
    } finally {
      await input.close();
    }
  }

  Future<ConvertImportResult> _importArchive(
    Archive archive, {
    String? targetParentFolderId,
  }) async {
    // Group entries by directory to drive the recursive recreation.
    // Map<dirPath, _DirEntry>.
    final entries = <String, _DirEntry>{};
    ArchiveFile? manifestFile;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final path = file.name;
      if (path == _manifestFileName) {
        manifestFile = file;
        continue;
      }

      final dir = p.posix.dirname(path);
      final base = p.posix.basename(path);
      final dirEntry = entries.putIfAbsent(dir, _DirEntry.new);
      if (base == _folderMetaFileName) {
        dirEntry.folderMeta = file;
      } else {
        // Accept any extension known to [ExportFormat] so archives
        // produced with noteFormat=md/txt round-trip cleanly.
        final ext = p.extension(base).toLowerCase().replaceAll('.', '');
        if (ExportFormat.fromExtension(ext) != null) {
          dirEntry.noteFiles.add(file);
        }
      }
    }

    // Reject archives produced by a future build before we touch the DB.
    // Manifest is optional so legacy archives created before v1 still
    // import; once present, the version is treated as authoritative.
    if (manifestFile != null) {
      _assertSupportedManifest(manifestFile);
    }

    if (entries.isEmpty) {
      throw const FormatException('Archive contains no importable entries');
    }

    var folderCount = 0;
    var noteCount = 0;
    final createdRootIds = <String>[];

    // The roots are the dirs whose parent dir is not present in [entries].
    // The synthetic '.' / '' dir holds loose top-level notes from a
    // multi-select export — those import directly into [targetParentFolderId]
    // without spawning a wrapper folder.
    final allDirs = entries.keys.toSet();
    final folderRoots = allDirs.where((d) {
      if (d == '.' || d == '') return false;
      final parent = p.posix.dirname(d);
      return parent == '.' || parent == '' || !allDirs.contains(parent);
    }).toList()..sort();

    Future<void> importNoteFile(
      ArchiveFile noteFile,
      String targetFolderId,
    ) async {
      final raw = _consume(noteFile);
      final ext = p.extension(noteFile.name).toLowerCase().replaceAll('.', '');
      final format = ExportFormat.fromExtension(ext) ?? ExportFormat.json;
      try {
        await _importNote(
          raw: raw,
          format: format,
          fallbackTitle: p.basenameWithoutExtension(noteFile.name),
          targetFolderId: targetFolderId,
        );
        noteCount++;
      } on FormatException {
        // Skip malformed note files; keep importing the rest.
      }
    }

    Future<void> recreate(String dirPath, String? newParentId) async {
      final entry = entries[dirPath];
      if (entry == null) return;

      final meta = entry.folderMeta != null
          ? _readFolderMeta(entry.folderMeta!)
          : null;
      // Fall back to the directory name in the archive when the meta
      // file is missing or its `name` field is blank.
      final folderName = meta?.name ?? p.posix.basename(dirPath);

      final folder = await _createFolderWithUniqueName(
        name: folderName,
        parentId: newParentId,
        createdAt: meta?.createdAt,
        noteSortOrder: meta?.noteSortOrder,
        subfolderSortOrder: meta?.subfolderSortOrder,
        label: meta?.label ?? ItemLabel.none,
      );
      folderCount++;
      if (newParentId == targetParentFolderId) {
        createdRootIds.add(folder.id);
      }

      for (final noteFile in entry.noteFiles) {
        await importNoteFile(noteFile, folder.id);
      }

      // Children: directories whose parent equals this dirPath.
      final children =
          allDirs.where((d) => p.posix.dirname(d) == dirPath).toList()..sort();
      for (final child in children) {
        await recreate(child, folder.id);
      }
    }

    // Loose root notes from a multi-select export. They require a target
    // folder to land in; importing such an archive at the database root
    // (where notes can't live) is rejected up front.
    final looseRoot = entries['.'] ?? entries[''];
    if (looseRoot != null && looseRoot.noteFiles.isNotEmpty) {
      if (targetParentFolderId == null) {
        throw const FormatException(
          'Archive contains loose notes but no target folder was provided',
        );
      }
      for (final noteFile in looseRoot.noteFiles) {
        await importNoteFile(noteFile, targetParentFolderId);
      }
    }

    for (final root in folderRoots) {
      await recreate(root, targetParentFolderId);
    }

    return ConvertImportResult(
      foldersImported: folderCount,
      notesImported: noteCount,
      createdRootFolderIds: createdRootIds,
    );
  }

  /// Decode a folder's `_folder.json` into the subset of fields the
  /// importer cares about (name, original `createdAt`, sort preferences).
  /// Returns null if the file is missing or malformed; callers fall back
  /// to safe defaults (directory name, current time, no sort prefs).
  _FolderMeta? _readFolderMeta(ArchiveFile file) {
    try {
      final raw = _consume(file);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final name = decoded[JsonKeys.name];
      final rawLabel = decoded[JsonKeys.label];
      return _FolderMeta(
        name: (name is String && name.trim().isNotEmpty) ? name : null,
        createdAt: _tryParseDate(decoded[JsonKeys.createdAt]),
        noteSortOrder: decoded[JsonKeys.noteSortOrder] as String?,
        subfolderSortOrder: decoded[JsonKeys.subfolderSortOrder] as String?,
        label: ItemLabel.fromName(rawLabel is String ? rawLabel : null),
      );
    } catch (_) {
      return null;
    }
  }

  /// Verify the archive's manifest version is one this build understands.
  /// A missing or unparseable manifest is tolerated (treated as v1) so we
  /// can still import legacy archives; a *higher* version is rejected
  /// before any DB writes happen.
  void _assertSupportedManifest(ArchiveFile manifest) {
    try {
      final raw = _consume(manifest);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final v = decoded[archiveVersionKey];
      if (v is int && v > archiveVersion) {
        throw UnsupportedArchiveVersionException(
          archiveVersion: v,
          supportedVersion: archiveVersion,
        );
      }
    } on UnsupportedArchiveVersionException {
      rethrow;
    } catch (_) {
      // Malformed manifest is non-fatal — proceed and let directory
      // structure drive the import.
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  /// [file]'s text, after which its bytes are dropped ([ArchiveFile.clear]),
  /// so an import holds one entry at a time. Never `close` / `closeSync`:
  /// every entry reads through the archive's one file stream, which those
  /// would close under the entries still to come.
  static String _consume(ArchiveFile file) {
    try {
      return utf8.decode(file.content);
    } finally {
      file.clear();
    }
  }

  /// Strip characters that are illegal on Windows / unsafe in zip paths,
  /// trim whitespace and dots, and cap length so very long names don't
  /// blow past filesystem limits.
  static String _sanitizeFileName(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final safe = cleaned.isEmpty ? 'untitled' : cleaned;
    return safe.length > 100 ? safe.substring(0, 100) : safe;
  }

  /// Append ` (n)` until [name] does not collide with anything in [used]
  /// (case-insensitive).
  static String _uniqueName(String name, Set<String> used) {
    if (!used.contains(name.toLowerCase())) return name;
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 2;
    while (true) {
      final candidate = '$base ($i)$ext';
      if (!used.contains(candidate.toLowerCase())) return candidate;
      i++;
    }
  }

  /// Always routes through [FolderStorageService.importFolder] — every
  /// caller of this helper is part of the import pipeline. Missing
  /// metadata defaults to "now", which is identical to what the regular
  /// create path would produce, so a single code path is enough.
  Future<Folder> _createFolderWithUniqueName({
    required String name,
    String? parentId,
    DateTime? createdAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
    ItemLabel label = ItemLabel.none,
  }) async {
    final effectiveCreatedAt = createdAt ?? DateTime.now();
    var attempt = name;
    var i = 2;
    while (true) {
      try {
        return await _folderStorage.importFolder(
          name: attempt,
          parentId: parentId,
          createdAt: effectiveCreatedAt,
          noteSortOrder: noteSortOrder,
          subfolderSortOrder: subfolderSortOrder,
          label: label,
        );
      } on DuplicateNameException {
        attempt = '$name ($i)';
        i++;
      }
    }
  }

  /// Always routes through [NoteStorageService.importNote]. When the
  /// source format carried no timestamps (markdown/text), both default
  /// to "now" — equivalent to a fresh create.
  Future<NoteMetadata> _createNoteWithUniqueTitle({
    required String folderId,
    required String title,
    required String content,
    DateTime? createdAt,
    DateTime? updatedAt,
    ItemLabel label = ItemLabel.none,
  }) async {
    final now = DateTime.now();
    final effectiveCreatedAt = createdAt ?? now;
    final effectiveUpdatedAt = updatedAt ?? createdAt ?? now;
    var attempt = title;
    var i = 2;
    while (true) {
      try {
        return await _noteStorage.importNote(
          folderId: folderId,
          title: attempt,
          content: content,
          createdAt: effectiveCreatedAt,
          updatedAt: effectiveUpdatedAt,
          label: label,
        );
      } on DuplicateNameException {
        attempt = '$title ($i)';
        i++;
      }
    }
  }
}

/// One `.zip` written entry by entry: each entry is compressed and handed to
/// the file as it is added, before the walk reads the next note, so an
/// export holds the largest single note rather than the whole tree.
class _ArchiveWriter {
  _ArchiveWriter(OutputFileStream output) {
    // Explicit: without a level the encoder deflates at 6, not the level 1
    // `ZipEncoder.encode` always used.
    _encoder.createWithStream(output, level: DeflateLevel.bestSpeed);
  }

  final _encoder = ZipFileEncoder();

  void addText(String path, String text) {
    final bytes = utf8.encode(text);
    _encoder.addArchiveFile(ArchiveFile(path, bytes.length, bytes));
  }

  void addJson(String path, Map<String, dynamic> data) =>
      addText(path, const JsonEncoder.withIndent('  ').convert(data));

  /// Writes the central directory and closes the file.
  Future<void> close() => _encoder.close();
}

class _DirEntry {
  ArchiveFile? folderMeta;
  final List<ArchiveFile> noteFiles = [];
}

/// Mutable counter pair shared by the recursive folder walk so callers
/// can observe totals after the walk completes.
class _Counts {
  int folders = 0;
  int notes = 0;
}

/// Decoded subset of a `_folder.json` entry.
class _FolderMeta {
  final String? name;
  final DateTime? createdAt;
  final String? noteSortOrder;
  final String? subfolderSortOrder;
  final ItemLabel label;

  const _FolderMeta({
    this.name,
    this.createdAt,
    this.noteSortOrder,
    this.subfolderSortOrder,
    this.label = ItemLabel.none,
  });
}
