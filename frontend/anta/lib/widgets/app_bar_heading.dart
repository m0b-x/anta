import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A bar title's own node as the page's level-1 heading, the one that names
/// the route — for a bar that sets `excludeHeaderSemantics`, so `AppBar`
/// leaves no unlabelled heading of its own beside it.
///
/// `AppBar` names routes everywhere but on Apple platforms, and so does this.
/// The level is what Android reads (its bridge marks a heading from
/// `headingLevel` alone) and the flag what VoiceOver reads; level 1 puts the
/// level-2 section headers under the page's name.
class AppBarHeading extends StatelessWidget {
  const AppBarHeading({super.key, this.identifier, required this.child});

  /// A `SemanticsIds` value, so a device script can tell which page is on
  /// top without reading translated text.
  final String? identifier;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final namesRoute = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => null,
      _ => true,
    };
    return Semantics(
      container: true,
      identifier: identifier,
      header: true,
      headingLevel: 1,
      namesRoute: namesRoute,
      child: child,
    );
  }
}
