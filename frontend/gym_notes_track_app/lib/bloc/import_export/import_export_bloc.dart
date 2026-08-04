import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/import_export_service.dart';
import 'import_export_event.dart';
import 'import_export_state.dart';

/// Thin orchestrator over [ImportExportService]. Translates events into
/// service calls, emits in-progress / success / failure states, and
/// optionally hands the resulting file to the OS share sheet on export.
class ImportExportBloc extends Bloc<ImportExportEvent, ImportExportState> {
  final ImportExportService _service;

  ImportExportBloc({required ImportExportService service})
    : _service = service,
      super(const ImportExportInitial()) {
    on<ExportNoteRequested>(_onExportNote);
    on<ExportFolderRequested>(_onExportFolder);
    on<ExportItemsRequested>(_onExportItems);
    on<ExportCalendarRequested>(_onExportCalendar);
    on<ImportFileRequested>(_onImportFile);
    on<ImportArchiveRequested>(_onImportArchive);
    on<ImportExportReset>((_, emit) => emit(const ImportExportInitial()));
  }

  Future<void> _onExportNote(
    ExportNoteRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.exportNote));
    try {
      final result = await _service.exportNote(
        metadata: event.metadata,
        format: event.format,
      );
      if (event.share) {
        await _service.shareExport(result);
      }
      emit(
        ImportExportExportSuccess(
          operation: ImportExportOperation.exportNote,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.exportNote,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _onExportFolder(
    ExportFolderRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.exportFolder));
    try {
      final result = await _service.exportFolder(folderId: event.folderId);
      if (event.share) {
        await _service.shareExport(result);
      }
      emit(
        ImportExportExportSuccess(
          operation: ImportExportOperation.exportFolder,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.exportFolder,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _onExportItems(
    ExportItemsRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.exportItems));
    try {
      final result = await _service.exportItems(
        noteIds: event.noteIds,
        folderIds: event.folderIds,
        noteFormat: event.noteFormat,
      );
      if (event.share) {
        await _service.shareExport(result);
      }
      emit(
        ImportExportExportSuccess(
          operation: ImportExportOperation.exportItems,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.exportItems,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _onExportCalendar(
    ExportCalendarRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.exportCalendar));
    try {
      final result = await _service.exportCalendar(events: event.events);
      if (event.share) {
        await _service.shareExport(result);
      }
      emit(
        ImportExportExportSuccess(
          operation: ImportExportOperation.exportCalendar,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.exportCalendar,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _onImportFile(
    ImportFileRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.importFile));
    try {
      final result = await _service.importFile(
        filePath: event.filePath,
        targetFolderId: event.targetFolderId,
      );
      emit(
        ImportExportImportSuccess(
          operation: ImportExportOperation.importFile,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.importFile,
          message: e.toString(),
        ),
      );
    }
  }

  Future<void> _onImportArchive(
    ImportArchiveRequested event,
    Emitter<ImportExportState> emit,
  ) async {
    emit(const ImportExportInProgress(ImportExportOperation.importArchive));
    try {
      final result = await _service.importArchive(
        filePath: event.filePath,
        targetParentFolderId: event.targetParentFolderId,
      );
      emit(
        ImportExportImportSuccess(
          operation: ImportExportOperation.importArchive,
          result: result,
        ),
      );
    } catch (e) {
      emit(
        ImportExportFailure(
          operation: ImportExportOperation.importArchive,
          message: e.toString(),
        ),
      );
    }
  }
}
