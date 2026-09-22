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
import 'constants/app_theme.dart';
import 'core/di/injection.dart';
import 'core/qa/qa_bootstrap.dart';
import 'core/qa/qa_mode.dart';
import 'models/alert_payload.dart';
import 'pages/alarm_page.dart';
import 'pages/optimized_folder_content_page.dart';
import 'pages/onboarding_page.dart';
import 'services/alert_gateway.dart';
import 'services/alert_removal_notice.dart';
import 'services/alert_scheduler.dart';
import 'services/app_navigator.dart';
import 'services/counter_service.dart';
import 'services/import_export_service.dart';
import 'services/label_appearance_service.dart';
import 'services/navigation_history_service.dart';
import 'services/pending_navigation.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'widgets/permission_prompt_dialog.dart';

/// How much of an exception string the on-screen placeholder carries. Long
/// enough to name the widget and the assertion, short enough that the box
/// stays a caption rather than a wall of stack frames.
const int _errorDetailLimit = 300;

const Duration _launchIntentPatience = Duration(seconds: 5);

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
  // Namespaces preferences and honours a reset marker before anything opens
  // preferences or a database. Compiled out unless `ANTA_QA` is defined.
  await QaBootstrap.beforeDependencies();
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

  // Imports a seed marker and skips onboarding, so the first frame of a QA run
  // is the folder root over known data. Compiled out unless `ANTA_QA` is
  // defined.
  await QaBootstrap.afterDependencies();

  // Seeds `LabelAppearance.style` before the first frame, so a browser opened
  // straight into the stripe style renders it rather than flashing the dot it
  // defaults to and swapping a frame later.
  await LabelAppearanceService.getInstance();

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

  /// Coalesces the resume reconcile. A resume often arrives in bursts — an
  /// inset animation, a permission dialog closing — and the pass walks the
  /// whole horizon, so it waits for the app to settle first.
  Timer? _resumeReconcile;

  /// Whether the launch restore has had its turn. An alert tap must land
  /// **above** the remembered location, never underneath it, so nothing is
  /// drained until the replay has been queued.
  bool _navigationReady = false;

  bool _permissionPromptChecked = false;
  bool _alertNavigationSeen = false;
  Future<void>? _launchIntentDrain;

  /// Live subscription to the gateway's ring stream, for as long as the app is.
  StreamSubscription<AlertPayload>? _ringing;

  /// The rings that ended without the app asking: the notification's own Stop,
  /// and the Silence-after timeout.
  StreamSubscription<AlertRingEnd>? _ringEnded;

  /// The phone's "next alarm" line opening a warm app (the alarm-clock show
  /// intent); a cold launch by the same intent arrives as the launch intent.
  StreamSubscription<void>? _showAlarms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PendingNavigationQueue.instance.addListener(_scheduleNavigationDrain);
    _listenForRings();
    _checkOnboarding();
    // Post-frame and unawaited: the launch reconcile reads four services and
    // talks to the platform, and none of that may sit between the user and
    // the first frame. `all`, because a launch is the one moment nothing has
    // told us what changed — a reboot, a force stop, a clock change and a
    // week of skipped occurrences all look the same from here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reconcileAlerts(AlertReconcileReason.launch));
    });
  }

  @override
  void dispose() {
    _resumeReconcile?.cancel();
    unawaited(_ringing?.cancel());
    unawaited(_ringEnded?.cancel());
    unawaited(_showAlarms?.cancel());
    PendingNavigationQueue.instance.removeListener(_scheduleNavigationDrain);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Subscribes to the gateway's rings, and drains the alert the app may have
  /// been launched by.
  ///
  /// Both go through [PendingNavigationQueue] rather than pushing directly: a
  /// ring can arrive while the process is still starting, `AppNavigator`'s
  /// navigator accessor force-unwraps, and the queue is what holds an intent
  /// until there is somewhere to put it — and what dedupes the cold-start tap
  /// the notification plugin delivers twice.
  void _listenForRings() {
    final AlertGateway gateway;
    try {
      gateway = getIt<AlertGateway>();
    } catch (e) {
      debugPrint('[main] no AlertGateway to listen to: $e');
      return;
    }
    _ringing = gateway.ringing.listen((payload) {
      // **Before anything else.** The launch reconcile that the ring's own
      // relaunch of the app provokes runs post-frame, a second or two before
      // `Alarm.ringing` emits, and it leaves a row under `kLateFireGrace` late
      // exactly as it found it — in flight, waiting for something to settle
      // it. This is that something; without it the row ages out of the grace
      // window and the next launch reports a "Missed" for a ring the user
      // heard and stopped.
      unawaited(AlertScheduler.markFiredById(payload.osId));
      PendingNavigationQueue.instance.enqueue(
        OpenAlarmIntent(payload: payload),
      );
    });
    _ringEnded = gateway.ringEnded.listen((end) {
      unawaited(_settleEndedRing(end));
    });
    _showAlarms = gateway.showAlarms.listen((_) {
      PendingNavigationQueue.instance.enqueue(const OpenAlertsHubIntent());
    });
    _launchIntentDrain = _drainLaunchIntent(gateway);
  }

  /// Does for a ring stopped from the platform's notification what the alarm
  /// page's Stop does for one stopped there: settle the registration, re-arm
  /// the event, and carry out A3. With the phone in use Android shows a ring
  /// as a heads-up, so for many alarms this is the only Stop there is.
  ///
  /// An unanswered ring that timed out is settled too, but it acknowledged
  /// nothing, so it removes nothing.
  Future<void> _settleEndedRing(AlertRingEnd end) async {
    final answered = end.cause == AlertRingEndCause.dismissed;
    await AlertScheduler.settleEndedRingByPayload(
      end.payload,
      answered: answered,
    );
    if (answered) await AlertAcknowledgement.apply(end.payload);
  }

  Future<void> _drainLaunchIntent(AlertGateway gateway) async {
    try {
      final intent = await gateway.launchIntent();
      if (intent == null) return;
      if (intent is OpenAlarmIntent) {
        unawaited(AlertScheduler.markFiredById(intent.osId));
      }
      PendingNavigationQueue.instance.enqueue(intent);
    } catch (e) {
      debugPrint('[main] launch intent failed: $e');
    }
  }

  /// Re-derives the alert horizon and makes the platform match it.
  ///
  /// Every failure is swallowed: the scheduler is best-effort by nature — the
  /// permission may be gone, the plugin may throw — and nothing the user is
  /// doing depends on it succeeding right now.
  Future<void> _reconcileAlerts(AlertReconcileReason reason) async {
    try {
      final scheduler = await AlertScheduler.getInstance();
      await scheduler.reconcileAll(reason);
    } catch (e) {
      debugPrint('[main] Alert reconcile (${reason.name}) failed: $e');
    }
  }

  /// `addPostFrameCallback` only *registers* — it never asks for a frame. An
  /// app sitting idle in the foreground is not producing any, so without the
  /// explicit request a ring that arrives then queues its alarm page and the
  /// page appears at the user's next touch, however long the phone has been
  /// ringing by then.
  void _scheduleNavigationDrain() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _drainPendingNavigation(),
    );
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Routes the alert taps that arrived while there was nowhere to push them.
  ///
  /// `AppNavigator`'s navigator accessor force-unwraps, so a cold-start tap
  /// has to wait for a navigator to exist; the queue is what holds it, and
  /// [_navigationReady] is what keeps it from landing under the restored
  /// location.
  void _drainPendingNavigation() {
    if (!_navigationReady) return;
    if (AppNavigator.navigatorKey.currentState == null) return;
    final intents = PendingNavigationQueue.instance.drain();
    if (intents.isNotEmpty) _alertNavigationSeen = true;
    for (final intent in intents) {
      switch (intent) {
        case OpenEventIntent():
          unawaited(
            AppNavigator.toCalendarOccurrence(
              day: intent.payload.dayUtc,
              eventId: intent.payload.eventId,
            ),
          );
        case OpenAlarmIntent():
          // Instant, and deliberately unstamped: a restored last location must
          // never reopen a ring that is long over.
          unawaited(
            AppNavigator.rootPushInstant<void>(
              AlarmPage(payload: intent.payload),
            ),
          );
        case OpenAlertsHubIntent():
          unawaited(AppNavigator.toAlertsFromPlatform());
      }
    }
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
    // The resume branch is what makes the horizon roll forward without the
    // user doing anything: a phone left closed for a week comes back with
    // every registration in the past, and this is where they are marked and
    // replanned. It is also what carries a holiday-profile change to the OS,
    // since the rules that read `PublicHolidays` are re-walked here.
    if (state == AppLifecycleState.resumed) {
      _resumeReconcile?.cancel();
      _resumeReconcile = Timer(const Duration(seconds: 2), () {
        unawaited(_reconcileAlerts(AlertReconcileReason.resumed));
      });
      _scheduleNavigationDrain();
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
        unawaited(
          AppNavigator.restoreLastLocation().whenComplete(
            _promptForPermissions,
          ),
        );
        // Straight after the replay is queued, never before: an alert tap
        // opens on top of the remembered chain, not underneath it.
        _navigationReady = true;
        _drainPendingNavigation();
      });
    } else if (!completed) {
      getIt<NavigationHistoryService>().beginRecording();
      // Onboarding restores nothing, so there is nothing to land above.
      _navigationReady = true;
      _drainPendingNavigation();
    }
  }

  void _onOnboardingComplete() {
    setState(() => _showOnboarding = false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_promptForPermissions()),
    );
  }

  Future<void> _promptForPermissions() async {
    if (_permissionPromptChecked) return;
    _permissionPromptChecked = true;
    if (QaMode.enabled && !QaMode.permissionPrompt) return;
    try {
      await _launchIntentDrain?.timeout(
        _launchIntentPatience,
        onTimeout: () {},
      );
      if (!mounted) return;
      await PermissionLaunchPrompt.maybeShow(
        service: getIt<PermissionService>(),
        context: () => AppNavigator.navigatorKey.currentContext,
        isInterrupted: _isAlertInFront,
      );
    } catch (e) {
      debugPrint('[main] permission prompt skipped: $e');
    }
  }

  bool _isAlertInFront() {
    if (_alertNavigationSeen) return true;
    if (!PendingNavigationQueue.instance.isEmpty) return true;
    try {
      return getIt<AlertGateway>().ringingIds.isNotEmpty;
    } catch (_) {
      return false;
    }
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
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
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
