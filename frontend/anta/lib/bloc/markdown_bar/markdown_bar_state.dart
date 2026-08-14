import 'package:equatable/equatable.dart';

import '../../models/custom_markdown_shortcut.dart';
import '../../models/markdown_bar_profile.dart';

sealed class MarkdownBarState extends Equatable {
  const MarkdownBarState();

  @override
  List<Object?> get props => [];
}

final class MarkdownBarInitial extends MarkdownBarState {
  const MarkdownBarInitial();
}

final class MarkdownBarLoading extends MarkdownBarState {
  const MarkdownBarLoading();
}

final class MarkdownBarLoaded extends MarkdownBarState {
  final List<MarkdownBarProfile> profiles;
  final String activeProfileId;
  final String? editingProfileId;
  final List<CustomMarkdownShortcut> currentShortcuts;

  const MarkdownBarLoaded({
    required this.profiles,
    required this.activeProfileId,
    this.editingProfileId,
    required this.currentShortcuts,
  });

  MarkdownBarProfile get activeProfile => profiles.firstWhere(
    (p) => p.id == activeProfileId,
    orElse: () => profiles.first,
  );

  MarkdownBarProfile? get editingProfile {
    if (editingProfileId == null) return null;
    try {
      return profiles.firstWhere((p) => p.id == editingProfileId);
    } catch (_) {
      return null;
    }
  }

  MarkdownBarLoaded copyWith({
    List<MarkdownBarProfile>? profiles,
    String? activeProfileId,
    String? editingProfileId,
    bool clearEditingProfile = false,
    List<CustomMarkdownShortcut>? currentShortcuts,
  }) {
    return MarkdownBarLoaded(
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      editingProfileId: clearEditingProfile
          ? null
          : (editingProfileId ?? this.editingProfileId),
      currentShortcuts: currentShortcuts ?? this.currentShortcuts,
    );
  }

  @override
  List<Object?> get props => [
    profiles,
    activeProfileId,
    editingProfileId,
    currentShortcuts,
  ];
}

final class MarkdownBarError extends MarkdownBarState {
  final String message;
  final MarkdownBarErrorType errorType;

  const MarkdownBarError(
    this.message, {
    this.errorType = MarkdownBarErrorType.unknown,
  });

  @override
  List<Object?> get props => [message, errorType];
}

enum MarkdownBarErrorType { loadFailed, saveFailed, profileNotFound, unknown }
