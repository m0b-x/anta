import 'package:equatable/equatable.dart';

import '../../services/import_export_service.dart';

/// Operation kind tracked in [ImportExportInProgress] / *Success / *Failure
/// so the UI can render a contextual progress label.
enum ImportExportOperation {
  exportNote,
  exportFolder,
  exportItems,
  exportCalendar,

  /// A page's composed text — the report's Markdown share, its one caller.
  exportText,
  importFile,
  importArchive,
}

sealed class ImportExportState extends Equatable {
  const ImportExportState();

  @override
  List<Object?> get props => [];
}

final class ImportExportInitial extends ImportExportState {
  const ImportExportInitial();
}

final class ImportExportInProgress extends ImportExportState {
  final ImportExportOperation operation;

  const ImportExportInProgress(this.operation);

  @override
  List<Object?> get props => [operation];
}

final class ImportExportExportSuccess extends ImportExportState {
  final ImportExportOperation operation;
  final ExportResult result;

  const ImportExportExportSuccess({
    required this.operation,
    required this.result,
  });

  @override
  List<Object?> get props => [operation, result.filePath];
}

final class ImportExportImportSuccess extends ImportExportState {
  final ImportExportOperation operation;
  final ConvertImportResult result;

  const ImportExportImportSuccess({
    required this.operation,
    required this.result,
  });

  @override
  List<Object?> get props => [
    operation,
    result.foldersImported,
    result.notesImported,
  ];
}

final class ImportExportFailure extends ImportExportState {
  final ImportExportOperation operation;
  final String message;

  /// The export named a row the partner shares and was refused before any
  /// file was written (share surfaces D19) — a refusal the page words as
  /// its plain failure, not a fault.
  final bool refusedShared;

  const ImportExportFailure({
    required this.operation,
    required this.message,
    this.refusedShared = false,
  });

  @override
  List<Object?> get props => [operation, message, refusedShared];
}
