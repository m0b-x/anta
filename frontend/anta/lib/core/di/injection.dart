import 'package:firebase_core/firebase_core.dart';
import 'package:get_it/get_it.dart';
import '../../database/database.dart';
import '../../repositories/note_repository.dart';
import '../../repositories/folder_repository.dart';
import '../../services/folder_storage_service.dart';
import '../../services/note_storage_service.dart';
import '../../services/folder_search_service.dart';
import '../../services/import_export_service.dart';
import '../../services/markdown_bar_service.dart';
import '../../services/counter_service.dart';
import '../../services/calendar_event_service.dart';
import '../../services/event_occurrence_service.dart';
import '../../services/event_presence_service.dart';
import '../../services/category_service.dart';
import '../../services/public_holiday_service.dart';
import '../../services/mixed_reorder_service.dart';
import '../../services/move_history_service.dart';
import '../../services/move_history_store.dart';
import '../../services/recent_destinations_service.dart';
import '../../services/folder_name_index.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/pairing_gateway.dart';
import '../../services/sync_availability.dart';
import '../../bloc/optimized_folder/optimized_folder_bloc.dart';
import '../../bloc/optimized_note/optimized_note_bloc.dart';
import '../../bloc/import_export/import_export_bloc.dart';
import '../../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../../bloc/counter/counter_bloc.dart';
import '../../bloc/calendar/calendar_bloc.dart';
import '../../bloc/pairing/pairing_bloc.dart';
import '../../bloc/sync/sync_bloc.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  await _registerDatabase();
  _registerRepositories();
  await _registerServices();
  _registerBlocs();
}

Future<void> _registerDatabase() async {
  final database = await AppDatabase.getInstance();
  getIt.registerSingleton<AppDatabase>(database);
}

void _registerRepositories() {
  final db = getIt<AppDatabase>();

  getIt.registerSingleton<NoteRepository>(NoteRepository(database: db));

  getIt.registerSingleton<FolderRepository>(FolderRepository(database: db));
}

Future<void> _registerServices() async {
  final folderStorageService = FolderStorageService(
    repository: getIt<FolderRepository>(),
  );
  await folderStorageService.initialize();
  getIt.registerSingleton<FolderStorageService>(folderStorageService);

  final noteStorageService = NoteStorageService(
    repository: getIt<NoteRepository>(),
  );
  await noteStorageService.initialize();
  getIt.registerSingleton<NoteStorageService>(noteStorageService);

  final folderSearchService = FolderSearchService(
    storageService: noteStorageService,
  );
  await folderSearchService.initialize();
  getIt.registerSingleton<FolderSearchService>(folderSearchService);

  final markdownBarService = await MarkdownBarService.getInstance();
  getIt.registerSingleton<MarkdownBarService>(markdownBarService);

  final counterService = await CounterService.getInstance();
  getIt.registerSingleton<CounterService>(counterService);

  final publicHolidayService = await PublicHolidayService.getInstance();
  getIt.registerSingleton<PublicHolidayService>(publicHolidayService);

  final categoryService = await CategoryService.getInstance();
  getIt.registerSingleton<CategoryService>(categoryService);

  final calendarEventService = await CalendarEventService.getInstance();
  getIt.registerSingleton<CalendarEventService>(calendarEventService);

  final eventOccurrenceService = await EventOccurrenceService.getInstance();
  getIt.registerSingleton<EventOccurrenceService>(eventOccurrenceService);

  final eventPresenceService = await EventPresenceService.getInstance();
  getIt.registerSingleton<EventPresenceService>(eventPresenceService);

  getIt.registerSingleton<MoveHistoryService>(
    MoveHistoryService(store: InMemoryMoveHistoryStore()),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<RecentDestinationsService>(
    RecentDestinationsService(),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<FolderNameIndex>(
    FolderNameIndex(folderService: folderStorageService),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<MixedReorderService>(
    MixedReorderService(
      folderRepository: getIt<FolderRepository>(),
      noteRepository: getIt<NoteRepository>(),
    ),
  );

  getIt.registerSingleton<ImportExportService>(
    ImportExportService(
      noteStorage: noteStorageService,
      folderStorage: folderStorageService,
      noteRepository: getIt<NoteRepository>(),
    ),
  );

  // Identity is global, not per-database, so this deliberately stays off the
  // `DatabaseLifecycle` reset contract — switching databases must not tear
  // down the auth stream. `Firebase.apps` guards the case where init failed
  // in `main.dart`: degrade to the no-op binding instead of crashing here.
  final canSync = SyncAvailability.isSupported && Firebase.apps.isNotEmpty;
  getIt.registerSingleton<AuthService>(
    canSync ? FirebaseAuthService() : NoOpAuthService(),
    dispose: (s) => s.dispose(),
  );

  // The gateway is stateless and global like the identity; the per-database
  // pairing state lives in `PairingService`, which is on the reset contract.
  getIt.registerSingleton<PairingGateway>(
    canSync ? FirestorePairingGateway() : const NoOpPairingGateway(),
  );
}

void _registerBlocs() {
  getIt.registerFactory<OptimizedFolderBloc>(
    () => OptimizedFolderBloc(storageService: getIt<FolderStorageService>()),
  );

  getIt.registerFactory<OptimizedNoteBloc>(
    () => OptimizedNoteBloc(
      storageService: getIt<NoteStorageService>(),
      searchService: getIt<FolderSearchService>(),
    ),
  );

  getIt.registerFactory<MarkdownBarBloc>(
    () => MarkdownBarBloc(barService: getIt<MarkdownBarService>()),
  );

  getIt.registerFactory<CounterBloc>(
    () => CounterBloc(counterService: getIt<CounterService>()),
  );

  getIt.registerFactory<CalendarBloc>(
    () => CalendarBloc(service: getIt<CalendarEventService>()),
  );

  getIt.registerFactory<ImportExportBloc>(
    () => ImportExportBloc(service: getIt<ImportExportService>()),
  );

  getIt.registerFactory<SyncBloc>(
    () => SyncBloc(authService: getIt<AuthService>()),
  );

  getIt.registerFactory<PairingBloc>(
    () => PairingBloc(
      authService: getIt<AuthService>(),
      gateway: getIt<PairingGateway>(),
    ),
  );
}

Future<void> resetDependencies() async {
  await getIt.reset();
}
