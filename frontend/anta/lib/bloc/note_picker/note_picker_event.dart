import 'package:equatable/equatable.dart';

sealed class NotePickerEvent extends Equatable {
  const NotePickerEvent();

  @override
  List<Object?> get props => [];
}

final class NotePickerOpened extends NotePickerEvent {
  const NotePickerOpened();
}

final class NotePickerPageChanged extends NotePickerEvent {
  final int page;

  const NotePickerPageChanged(this.page);

  @override
  List<Object?> get props => [page];
}

final class NotePickerQueryChanged extends NotePickerEvent {
  final String query;

  const NotePickerQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}
