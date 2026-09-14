import 'package:flutter/material.dart';

/// Puts an automation identifier on a leaf control's **own** semantics node.
///
/// A bare `Semantics(identifier: …)` around a button builds a second node: an
/// accessibility dump then shows an unlabelled `View` carrying the id next to
/// the `Button` carrying the tooltip, at identical bounds. Both are findable,
/// but a driver that resolves a target by id gets a node with no label and no
/// click flag, and a screen reader walks one extra stop.
///
/// [MergeSemantics] collapses the pair, so the id, the tooltip label and the
/// tap action end up on one node.
///
/// Only for controls that are a single node to begin with — a button, a
/// chip, a menu anchor. A container (the editor body, the markdown toolbar,
/// the colour strip) must keep its children as separate nodes, so those wear a
/// plain `Semantics(identifier: …)` and an extra node is the right shape.
class AutomationId extends StatelessWidget {
  const AutomationId({
    super.key,
    required this.identifier,
    required this.child,
  });

  /// A value from `SemanticsIds`.
  final String identifier;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(identifier: identifier, child: child),
    );
  }
}
