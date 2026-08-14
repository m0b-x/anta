import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'bloc/app_settings/app_settings_bloc.dart';
import 'bloc/calendar/calendar_bloc.dart';
import 'bloc/optimized_folder/optimized_folder_bloc.dart';
import 'bloc/optimized_note/optimized_note_bloc.dart';
import 'bloc/counter/counter_bloc.dart';
import 'bloc/import_export/import_export_bloc.dart';
import 'bloc/markdown_bar/markdown_bar_bloc.dart';
import 'core/di/injection.dart';
import 'pages/optimized_folder_content_page.dart';
import 'pages/onboarding_page.dart';
import 'services/app_navigator.dart';
import 'services/counter_service.dart';
import 'services/import_export_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

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
    // Reopen the last-viewed folder/note exactly once on cold launch, but
    // only for returning users (skip while onboarding is still showing).
    if (completed && !_didRestoreLocation) {
      _didRestoreLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.restoreLastLocation();
      });
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
            navigatorObservers: [AppNavigator.routeObserver],
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
