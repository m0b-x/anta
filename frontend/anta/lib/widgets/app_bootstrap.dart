import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import 'app_system_bars.dart';
import 'form_rows.dart';

/// What launch draws before the app's own first frame, and only when there
/// is something to say: the database is being upgraded, or it could not be
/// opened. A normal launch never builds it, so it adds no frame there.
///
/// It runs before the database is open, so neither the language nor the
/// theme the user chose can be read yet: it follows the device's locale and
/// brightness. It speaks the empty states' idiom — a state glyph over a
/// title — with the glyph's slot anchored to the screen, so swapping one
/// state for another moves neither the slot nor the title.
class AppBootstrap extends StatelessWidget {
  /// A migration is running.
  const AppBootstrap.updating({super.key})
    : error = null,
      onRetry = null,
      retrying = false,
      attempt = 0;

  /// Retry's open is running: without it the failed screen would stay as it
  /// was, and a second failure would redraw the same pixels unannounced.
  const AppBootstrap.opening({super.key})
    : error = null,
      onRetry = null,
      retrying = true,
      attempt = 0;

  /// The open failed with [error]; [onRetry] opens the database again.
  /// [attempt] counts the failures so far: a retry that fails the same way
  /// gets a fresh title node, or the screen reader would say nothing.
  const AppBootstrap.failed(
    Object this.error, {
    super.key,
    required VoidCallback this.onRetry,
    this.attempt = 1,
  }) : retrying = false;

  /// Which failure the failed state shows, from 1; 0 while a spinner shows.
  final int attempt;

  /// Null while a spinner shows.
  final Object? error;

  /// Null while a spinner shows.
  final VoidCallback? onRetry;

  /// Whether the spinner is Retry's open rather than a migration.
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppSystemBars(child: child!),
      home: _AppBootstrapPage(
        error: error,
        onRetry: onRetry,
        retrying: retrying,
        attempt: attempt,
      ),
    );
  }
}

class _AppBootstrapPage extends StatelessWidget {
  const _AppBootstrapPage({
    required this.error,
    required this.onRetry,
    required this.retrying,
    required this.attempt,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final bool retrying;
  final int attempt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final error = this.error;
    final progress = retrying
        ? l10n.launchOpeningData
        : l10n.launchUpdatingData;
    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SizedBox.expand(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                math.max(
                  RowMetrics.emptyStatePadding,
                  viewport.maxHeight * RowMetrics.launchSlotTopShare,
                ),
                RowMetrics.groupInset,
                RowMetrics.emptyStatePadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: RowMetrics.emptyStateGlyphSize,
                    child: error == null
                        ? Semantics(
                            liveRegion: true,
                            child: CircularProgressIndicator(
                              semanticsLabel: progress,
                            ),
                          )
                        : Icon(
                            Icons.error_outline_rounded,
                            size: RowMetrics.emptyStateGlyphSize,
                            color: colorScheme.error,
                          ),
                  ),
                  const SizedBox(height: RowMetrics.gap),
                  if (error == null)
                    ExcludeSemantics(
                      child: Text(
                        progress,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    )
                  else ...[
                    // The flag beside the level: on Flutter 3.44 the level
                    // alone marks a heading only for Android (`AppBarHeading`).
                    Semantics(
                      // A new node per failure: a retry that fails the same
                      // way would otherwise keep this node, and a live region
                      // whose text did not change announces nothing.
                      key: ValueKey('launch-failed-$attempt'),
                      header: true,
                      headingLevel: 1,
                      liveRegion: true,
                      child: Text(
                        l10n.launchOpenFailed,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: FormMetrics.settingsValueUnderGap),
                    Text(
                      l10n.launchOpenFailedNext,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: RowMetrics.groupGap),
                    FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
                    const SizedBox(height: RowMetrics.groupGap),
                    // Last and whole: at most errorDetailLimit characters,
                    // so it never needs a scroller of its own. A long press
                    // selects it, so a one-line detail still takes a whole
                    // target's height.
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kMinInteractiveDimension,
                      ),
                      child: SelectableText(
                        _detail(error),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _detail(Object error) {
    final raw = error.toString();
    return raw.length > AppConstants.errorDetailLimit
        ? '${raw.substring(0, AppConstants.errorDetailLimit)}…'
        : raw;
  }
}
