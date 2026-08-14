import 'package:equatable/equatable.dart';

import '../../models/calendar_event.dart';
import '../../models/export_format.dart';
import '../../models/note_metadata.dart';

/// Events for [ImportExportBloc].
sealed class ImportExportEvent extends Equatable {
  const ImportExportEvent();

  @override
  List<Object?> get props => [];
}

/// Export a single note as [format] and surface the resulting file path
/// in [ImportExportSuccess]. Optionally invoke the share sheet.
final class ExportNoteRequested extends ImportExportEvent {
  final NoteMetadata metadata;
  final ExportFormat format;
  final bool share;

  const ExportNoteRequested({
    required this.metadata,
    required this.format,
    this.share = false,
  });

  @override
  List<Object?> get props => [metadata, format, share];
}

/// Export a folder (recursively) as a `.zip` archive.
final class ExportFolderRequested extends ImportExportEvent {
  final String folderId;
  final bool share;

  const ExportFolderRequested({required this.folderId, this.share = false});

  @override
  List<Object?> get props => [folderId, share];
}

/// Export a mixed selection of notes and folders into a single `.zip`.
/// [noteFormat] is applied to every note in the archive (loose ones at
/// the root and the ones nested inside the selected folders).
final class ExportItemsRequested extends ImportExportEvent {
  final Set<String> noteIds;
  final Set<String> folderIds;
  final ExportFormat noteFormat;
  final bool share;

  const ExportItemsRequested({
    required this.noteIds,
    required this.folderIds,
    required this.noteFormat,
    this.share = false,
  });

  @override
  List<Object?> get props => [noteIds, folderIds, noteFormat, share];
}

/// Export calendar events as a single iCalendar (`.ics`) file.
///
/// The events travel on the event rather than being re-read from storage:
/// the calendar page already holds the loaded list, and the export must
/// match exactly what the user is looking at.
final class ExportCalendarRequested extends ImportExportEvent {
  final List<CalendarEvent> events;
  final bool share;

  const ExportCalendarRequested({required this.events, this.share = false});

  @override
  List<Object?> get props => [events, share];
}

/// Import a single file (json/md/txt). Detects format from extension.
final class ImportFileRequested extends ImportExportEvent {
  final String filePath;
  final String targetFolderId;

  const ImportFileRequested({
    required this.filePath,
    required this.targetFolderId,
  });

  @override
  List<Object?> get props => [filePath, targetFolderId];
}

/// Import a folder archive (`.zip`) under [targetParentFolderId]
/// (`null` = root).
final class ImportArchiveRequested extends ImportExportEvent {
  final String filePath;
  final String? targetParentFolderId;

  const ImportArchiveRequested({
    required this.filePath,
    this.targetParentFolderId,
  });

  @override
  List<Object?> get props => [filePath, targetParentFolderId];
}

/// Reset the bloc back to [ImportExportInitial] (e.g. after the UI has
/// consumed the success/failure state).
final class ImportExportReset extends ImportExportEvent {
  const ImportExportReset();
}
