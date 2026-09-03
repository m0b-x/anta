import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'services/sync_availability.dart';
import 'bloc/app_settings/app_settings_bloc.dart';
import 'bloc/calendar/calendar_bloc.dart';
import 'bloc/optimized_folder/optimized_folder_bloc.dart';
import 'bloc/optimized_note/optimized_note_bloc.dart';
import 'bloc/counter/counter_bloc.dart';
import 'bloc/import_export/import_export_bloc.dart';
import 'bloc/markdown_bar/markdown_bar_bloc.dart';
import 'constants/app_colors.dart';
import 'constants/app_icon_sizes.dart';
import 'constants/app_spacing.dart';
import 'core/di/injection.dart';
import 'pages/optimized_folder_content_page.dart';
import 'pages/onboarding_page.dart';
import 'services/app_navigator.dart';
import 'services/counter_service.dart';
import 'services/import_export_service.dart';
import 'services/navigation_history_service.dart';
import 'services/settings_service.dart';

/// How much of an exception string the on-screen placeholder carries. Long
/// enough to name the widget and the assertion, short enough that the box
/// stays a caption rather than a wall of stack frames.
const int _errorDetailLimit = 300;

/// Localizations for a surface that has no [BuildContext] to resolve them
/// from. Falls back to English when the device locale is not one of ours, and
/// to `null` when even that fails, so the caller can use plain literals.
AppLocalizations? _errorLocalizations() {
  try {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    final supported = AppLocalizations.supportedLocales.any(
      (locale) => locale.languageCode == device.languageCode,
    );
    return lookupAppLocalizations(
      supported ? Locale(device.languageCode) : const Locale('en'),
    );
  } catch (_) {
    return null;
  }
}

/// Replacement for Flutter's default [ErrorWidget].
///
/// In release the default is a textless [RenderErrorBox] that expands to fill
/// its parent, so a build exception inside a bottom sheet renders as a blank,
/// unresponsive sheet. This one says what happened, stays as small as its own
/// content, and hit-tests nothing outside that box.
///
/// It runs with no inherited theme or directionality guaranteed, so both are
/// supplied here and every colour is explicit.
Widget buildAppErrorWidget(FlutterErrorDetails details) {
  final l10n = _errorLocalizations();
  final raw = details.exceptionAsString();
  final error = raw.length > _errorDetailLimit
      ? '${raw.substring(0, _errorDetailLimit)}…'
      : raw;
  final title =
      l10n?.renderErrorTitle ?? 'This part of the screen could not be drawn';
  final detail = l10n?.renderErrorDetail(error) ?? 'Details: $error';

  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: AppColors.deleteAction.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 12,
              height: 1.3,
              color: AppColors.deleteAction,
              decoration: TextDecoration.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: AppIconSizes.tiny,
                        color: AppColors.deleteAction,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: AppColors.deleteAction,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    detail,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: AppColors.deleteAction,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Keeps Flutter's own reporting and adds a single logcat line, which is the
/// only place a release build surfaces anything at all.
void installErrorHooks() {
  ErrorWidget.builder = buildAppErrorWidget;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    final where = details.context == null ? '' : ' while ${details.context}';
    debugPrint(
      '[anta][${details.library ?? 'flutter'}]$where: '
      '${details.exceptionAsString()}',
    );
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHooks();
  await initializeDateFormatting();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Degrade to local-only rather than blocking launch: a checkout without
  // `google-services.json` must still start, just without sync.
  if (SyncAvailability.isSupported) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('[main] Firebase init failed, continuing offline: $e');
    }
  }

  await configureDependencies();

  // Best-effort sweep of stale exports left in the system temp dir
  // (crashes, denied share dialogs, files from prior installs). Fire
  // and forget so app launch isn't gated on filesystem hygiene.
  unawaited(getIt<ImportExportService>().sweepStaleExports());

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool? _showOnboarding;
  bool _didRestoreLocation = false;

  late final NavigationHistoryObserver _navigationHistoryObserver =
      NavigationHistoryObserver(getIt<NavigationHistoryService>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboarding();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      getIt<CounterService>().flush();
      // The remembered location is written on a debounce, and this is the
      // moment the whole feature exists for: Android kills paused processes,
      // so a pending stack has to reach SQLite before the window goes away.
      getIt<NavigationHistoryService>().flush();
    }
    // Close the input connection before the OS suspends us. Android can
    // pause the activity mid keyboard inset-animation, and the bottom
    // view inset then stays stuck at the keyboard height on the next
    // resume — the app comes back with a phantom empty strip under the
    // note toolbar. Dismissing the IME while the window is still live
    // lets that animation finish and leaves nothing focused on resume.
    if (state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _checkOnboarding() async {
    final settings = await SettingsService.getInstance();
    final completed = await settings.isOnboardingCompleted();
    if (mounted) {
      setState(() => _showOnboarding = !completed);
    }
    // Reopen the chain the user was in exactly once on cold launch, but only
    // for returning users (skip while onboarding is still showing).
    //
    // `restoreLastLocation` is also what unseals recording, so the onboarding
    // path has to unseal it itself — a first-run user must still have their
    // navigation remembered from here on.
    if (completed && !_didRestoreLocation) {
      _didRestoreLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.restoreLastLocation();
      });
    } else if (!completed) {
      getIt<NavigationHistoryService>().beginRecording();
    }
  }

  void _onOnboardingComplete() {
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AppSettingsBloc()..add(const LoadAppSettings()),
        ),
        BlocProvider(create: (_) => getIt<OptimizedFolderBloc>()),
        BlocProvider(create: (_) => getIt<OptimizedNoteBloc>()),
        BlocProvider(
          create: (_) => getIt<MarkdownBarBloc>()..add(const LoadMarkdownBar()),
        ),
        BlocProvider(
          create: (_) => getIt<CounterBloc>()..add(const LoadCounters()),
        ),
        BlocProvider(create: (_) => getIt<ImportExportBloc>()),
        BlocProvider(
          create: (_) => getIt<CalendarBloc>()..add(const LoadCalendarEvents()),
        ),
      ],
      child: BlocBuilder<AppSettingsBloc, AppSettingsState>(
        builder: (context, settingsState) {
          return MaterialApp(
            navigatorKey: AppNavigator.navigatorKey,
            navigatorObservers: [
              AppNavigator.routeObserver,
              _navigationHistoryObserver,
            ],
            title: 'ANTA',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('de'), Locale('ro')],
            locale: settingsState.locale,
            themeMode: settingsState.themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            home: _buildHome(),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (_showOnboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_showOnboarding!) {
      return OnboardingPage(onComplete: _onOnboardingComplete);
    }

    return const OptimizedFolderContentPage(folderId: null, title: 'ANTA');
  }
}
