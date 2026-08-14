import 'package:equatable/equatable.dart';

import '../../models/custom_markdown_shortcut.dart';

sealed class MarkdownBarEvent extends Equatable {
  const MarkdownBarEvent();

  @override
  List<Object?> get props => [];
}

final class LoadMarkdownBar extends MarkdownBarEvent {
  final String? noteId;

  const LoadMarkdownBar({this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class AddBarProfile extends MarkdownBarEvent {
  final String name;

  const AddBarProfile({required this.name});

  @override
  List<Object?> get props => [name];
}

final class RenameBarProfile extends MarkdownBarEvent {
  final String profileId;
  final String newName;

  const RenameBarProfile({required this.profileId, required this.newName});

  @override
  List<Object?> get props => [profileId, newName];
}

final class DuplicateBarProfile extends MarkdownBarEvent {
  final String sourceId;
  final String newName;

  const DuplicateBarProfile({required this.sourceId, required this.newName});

  @override
  List<Object?> get props => [sourceId, newName];
}

final class DeleteBarProfile extends MarkdownBarEvent {
  final String profileId;

  const DeleteBarProfile({required this.profileId});

  @override
  List<Object?> get props => [profileId];
}

final class SetActiveProfile extends MarkdownBarEvent {
  final String profileId;

  const SetActiveProfile({required this.profileId});

  @override
  List<Object?> get props => [profileId];
}

final class UpdateShortcuts extends MarkdownBarEvent {
  final String profileId;
  final List<CustomMarkdownShortcut> shortcuts;

  const UpdateShortcuts({required this.profileId, required this.shortcuts});

  @override
  List<Object?> get props => [profileId, shortcuts];
}

final class SetNoteBarAssignment extends MarkdownBarEvent {
  final String noteId;
  final String? profileId;

  const SetNoteBarAssignment({required this.noteId, this.profileId});

  @override
  List<Object?> get props => [noteId, profileId];
}

final class ResolveBarForNote extends MarkdownBarEvent {
  final String? noteId;

  const ResolveBarForNote({this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class SwitchEditingProfile extends MarkdownBarEvent {
  final String profileId;

  const SwitchEditingProfile({required this.profileId});

  @override
  List<Object?> get props => [profileId];
}
