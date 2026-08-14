import 'package:flutter/material.dart';
import '../services/loading_service.dart';

/// A linear progress bar that shows just below the AppBar when loading.
/// Listens to LoadingService's ValueNotifier for reactive updates.
class AppLoadingBar extends StatelessWidget {
  const AppLoadingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LoadingService().isLoading,
      builder: (context, isLoading, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: isLoading ? 4 : 0,
          child: isLoading
              ? LinearProgressIndicator(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

/// A scaffold wrapper that automatically includes the loading bar below the AppBar.
/// Use this instead of Scaffold for pages that need loading indicator.
class LoadingScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Color? backgroundColor;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;

  const LoadingScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.drawer,
    this.backgroundColor,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      drawer: drawer,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const AppLoadingBar(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
