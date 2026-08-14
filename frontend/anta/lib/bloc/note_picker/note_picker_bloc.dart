import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

import '../../constants/app_constants.dart';
import '../../services/note_storage_service.dart';
import 'note_picker_event.dart';
import 'note_picker_state.dart';

EventTransformer<T> _debounce<T>(Duration duration) {
  return (events, mapper) => events.debounce(duration).switchMap(mapper);
}

class NotePickerBloc extends Bloc<NotePickerEvent, NotePickerState> {
  final NoteStorageService _storageService;
  String _currentQuery = '';

  NotePickerBloc({required NoteStorageService storageService})
    : _storageService = storageService,
      super(const NotePickerInitial()) {
    on<NotePickerOpened>(_onOpened);
    on<NotePickerPageChanged>(_onPageChanged);
    on<NotePickerQueryChanged>(
      _onQueryChanged,
      transformer: _debounce(const Duration(milliseconds: 200)),
    );
  }

  Future<void> _onOpened(
    NotePickerOpened event,
    Emitter<NotePickerState> emit,
  ) async {
    await _loadPage(emit, page: 1, query: '');
  }

  Future<void> _onPageChanged(
    NotePickerPageChanged event,
    Emitter<NotePickerState> emit,
  ) async {
    await _loadPage(emit, page: event.page, query: _currentQuery);
  }

  Future<void> _onQueryChanged(
    NotePickerQueryChanged event,
    Emitter<NotePickerState> emit,
  ) async {
    _currentQuery = event.query;
    await _loadPage(emit, page: 1, query: event.query);
  }

  Future<void> _loadPage(
    Emitter<NotePickerState> emit, {
    required int page,
    required String query,
  }) async {
    emit(NotePickerLoading(query: query, page: page));
    try {
      final result = await _storageService.loadNotePickerPage(
        query: query,
        page: page,
        pageSize: AppConstants.notePickerPageSize,
      );
      emit(NotePickerLoaded(paginatedNotes: result, query: query));
    } catch (e) {
      emit(NotePickerError(e.toString()));
    }
  }
}
