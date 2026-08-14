import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/markdown_bar_service.dart';
import 'markdown_bar_event.dart';
import 'markdown_bar_state.dart';

export 'markdown_bar_event.dart';
export 'markdown_bar_state.dart';

class MarkdownBarBloc extends Bloc<MarkdownBarEvent, MarkdownBarState> {
  final MarkdownBarService _barService;

  MarkdownBarBloc({required MarkdownBarService barService})
    : _barService = barService,
      super(const MarkdownBarInitial()) {
    on<LoadMarkdownBar>(_onLoad);
    on<AddBarProfile>(_onAddProfile);
    on<RenameBarProfile>(_onRenameProfile);
    on<DuplicateBarProfile>(_onDuplicateProfile);
    on<DeleteBarProfile>(_onDeleteProfile);
    on<SetActiveProfile>(_onSetActiveProfile);
    on<UpdateShortcuts>(_onUpdateShortcuts);
    on<SetNoteBarAssignment>(_onSetNoteBarAssignment);
    on<ResolveBarForNote>(_onResolveBarForNote);
    on<SwitchEditingProfile>(_onSwitchEditingProfile);
  }

  Future<void> _onLoad(
    LoadMarkdownBar event,
    Emitter<MarkdownBarState> emit,
  ) async {
    emit(const MarkdownBarLoading());
    try {
      final profile = await _barService.resolveProfileForNote(event.noteId);

      emit(
        MarkdownBarLoaded(
          profiles: _barService.profiles,
          activeProfileId: profile.id,
          currentShortcuts: List.from(profile.shortcuts),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Load error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.loadFailed,
        ),
      );
    }
  }

  Future<void> _onAddProfile(
    AddBarProfile event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      final newId = await _barService.addProfile(event.name);
      emit(
        current.copyWith(
          profiles: _barService.profiles,
          editingProfileId: newId,
          currentShortcuts: _barService.getShortcuts(newId),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Add profile error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.saveFailed,
        ),
      );
    }
  }

  Future<void> _onRenameProfile(
    RenameBarProfile event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      await _barService.renameProfile(event.profileId, event.newName);
      emit(current.copyWith(profiles: _barService.profiles));
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Rename profile error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.saveFailed,
        ),
      );
    }
  }

  Future<void> _onDuplicateProfile(
    DuplicateBarProfile event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      final newId = await _barService.duplicateProfile(
        event.sourceId,
        event.newName,
      );
      emit(
        current.copyWith(
          profiles: _barService.profiles,
          editingProfileId: newId,
          currentShortcuts: _barService.getShortcuts(newId),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Duplicate profile error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.saveFailed,
        ),
      );
    }
  }

  Future<void> _onDeleteProfile(
    DeleteBarProfile event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      await _barService.deleteProfile(event.profileId);
      final activeId = _barService.activeProfileId;
      emit(
        current.copyWith(
          profiles: _barService.profiles,
          activeProfileId: activeId,
          editingProfileId: activeId,
          currentShortcuts: _barService.getShortcuts(activeId),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Delete profile error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.saveFailed,
        ),
      );
    }
  }

  Future<void> _onSetActiveProfile(
    SetActiveProfile event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      await _barService.setActiveProfile(event.profileId);
      emit(
        current.copyWith(
          activeProfileId: event.profileId,
          currentShortcuts: _barService.getShortcuts(event.profileId),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Set active profile error: $e');
    }
  }

  Future<void> _onUpdateShortcuts(
    UpdateShortcuts event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      await _barService.updateShortcuts(event.profileId, event.shortcuts);
      emit(
        current.copyWith(
          profiles: _barService.profiles,
          currentShortcuts: event.profileId == current.activeProfileId
              ? event.shortcuts
              : current.currentShortcuts,
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Update shortcuts error: $e');
      emit(
        MarkdownBarError(
          e.toString(),
          errorType: MarkdownBarErrorType.saveFailed,
        ),
      );
    }
  }

  Future<void> _onSetNoteBarAssignment(
    SetNoteBarAssignment event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      await _barService.setNoteBarId(event.noteId, event.profileId);
      final profile = await _barService.resolveProfileForNote(event.noteId);
      emit(
        current.copyWith(
          activeProfileId: profile.id,
          currentShortcuts: List.from(profile.shortcuts),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Set note bar assignment error: $e');
    }
  }

  Future<void> _onResolveBarForNote(
    ResolveBarForNote event,
    Emitter<MarkdownBarState> emit,
  ) async {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    try {
      final profile = await _barService.resolveProfileForNote(event.noteId);
      emit(
        current.copyWith(
          profiles: _barService.profiles,
          activeProfileId: profile.id,
          currentShortcuts: List.from(profile.shortcuts),
        ),
      );
    } catch (e) {
      debugPrint('[MarkdownBarBloc] Resolve bar error: $e');
    }
  }

  void _onSwitchEditingProfile(
    SwitchEditingProfile event,
    Emitter<MarkdownBarState> emit,
  ) {
    final current = state;
    if (current is! MarkdownBarLoaded) return;
    emit(
      current.copyWith(
        editingProfileId: event.profileId,
        currentShortcuts: _barService.getShortcuts(event.profileId),
      ),
    );
  }
}
