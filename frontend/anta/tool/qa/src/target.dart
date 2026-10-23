import 'errors.dart';
import 'ui_tree.dart';

/// A target string resolved to a node and/or a tap point.
class ResolvedTarget {
  const ResolvedTarget({
    required this.x,
    required this.y,
    required this.description,
    this.node,
  });

  final int x;
  final int y;
  final String description;
  final UiNode? node;

  @override
  String toString() => '$description at $x,$y';
}

final RegExp _indexTargetForm = RegExp(r'^#(\d+)$');
final RegExp _pointTargetForm = RegExp(r'^(-?\d+)\s*,\s*(-?\d+)$');

/// Whether a target is the `#12` flat-index form, which resolves against the
/// dump the agent last read rather than against a fresh one.
bool isIndexTarget(String target) => _indexTargetForm.hasMatch(target.trim());

/// Whether a target is a raw `x,y` coordinate, which needs no dump at all.
bool isPointTarget(String target) => _pointTargetForm.hasMatch(target.trim());

/// How a label was matched, weakest last.
enum MatchPass { exact, caseInsensitive, substring }

/// Which attribute a label matched against.
enum MatchField { contentDesc, text, resourceId }

class TargetMatch {
  const TargetMatch(this.node, this.pass, this.field);

  final UiNode node;
  final MatchPass pass;
  final MatchField field;
}

/// Resolves target strings against a dumped hierarchy.
///
/// Accepted forms: `#12` (flat node index), `123,456` (raw coordinates),
/// `id:some_id` (resource id) and any other string as a label, matched
/// against content description, then text, then resource id, in three
/// passes: exact, case-insensitive, then case-insensitive substring.
class TargetResolver {
  const TargetResolver(this.tree);

  final UiTree tree;

  static final RegExp _indexForm = _indexTargetForm;
  static final RegExp _pointForm = _pointTargetForm;

  ResolvedTarget resolve(String target, {int? nth}) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) {
      throw UsageFailure('empty target');
    }

    final indexMatch = _indexForm.firstMatch(trimmed);
    if (indexMatch != null) {
      final index = int.parse(indexMatch.group(1)!);
      final node = tree.byIndex(index);
      if (node == null) {
        throw TargetFailure(
          'no node #$index in the dump (${tree.nodes.length} nodes)',
        );
      }
      return fromNode(node);
    }

    final pointMatch = _pointForm.firstMatch(trimmed);
    if (pointMatch != null) {
      final x = int.parse(pointMatch.group(1)!);
      final y = int.parse(pointMatch.group(2)!);
      return ResolvedTarget(x: x, y: y, description: 'point $x,$y');
    }

    if (trimmed.startsWith('id:')) {
      final wanted = trimmed.substring(3);
      final matches = tree.nodes
          .where((n) => n.resourceId == wanted || n.shortId == wanted)
          .toList();
      return _pick(
        matches.map((n) => TargetMatch(n, MatchPass.exact, MatchField.resourceId)).toList(),
        trimmed,
        nth,
      );
    }

    return _pick(matchLabel(trimmed), trimmed, nth);
  }

  /// Every node [target] names, in traversal order and hidden ones
  /// included — what a presence check weighs, where [resolve] must pick
  /// one. A `#N` names its one node; a raw point names none.
  List<UiNode> matchingNodes(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty || _pointForm.hasMatch(trimmed)) return const [];
    final indexMatch = _indexForm.firstMatch(trimmed);
    if (indexMatch != null) {
      final node = tree.byIndex(int.parse(indexMatch.group(1)!));
      return node == null ? const [] : [node];
    }
    final List<UiNode> nodes;
    if (trimmed.startsWith('id:')) {
      final wanted = trimmed.substring(3);
      nodes = tree.nodes
          .where((n) => n.resourceId == wanted || n.shortId == wanted)
          .toList();
    } else {
      nodes = [for (final match in matchLabel(trimmed)) match.node];
    }
    return nodes..sort((a, b) => a.index.compareTo(b.index));
  }

  /// All nodes matching [label], strongest pass first.
  List<TargetMatch> matchLabel(String label) {
    for (final pass in MatchPass.values) {
      final found = <TargetMatch>[];
      for (final field in MatchField.values) {
        for (final node in tree.nodes) {
          final value = _valueOf(node, field);
          if (value.isEmpty) continue;
          if (!_matches(value, label, pass)) continue;
          if (found.any((m) => m.node.index == node.index)) continue;
          found.add(TargetMatch(node, pass, field));
        }
      }
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  static String _valueOf(UiNode node, MatchField field) => switch (field) {
        MatchField.contentDesc => node.contentDesc,
        MatchField.text => node.text,
        MatchField.resourceId => node.shortId,
      };

  static bool _matches(String value, String label, MatchPass pass) =>
      switch (pass) {
        MatchPass.exact => value == label,
        MatchPass.caseInsensitive => value.toLowerCase() == label.toLowerCase(),
        MatchPass.substring => value.toLowerCase().contains(label.toLowerCase()),
      };

  /// What is on screen right now, phrased for an error message.
  ///
  /// A failed lookup that lists the alternatives costs the agent no follow-up
  /// call to find out which screen it is actually on.
  String onScreenListing() {
    final labels = tree.interestingLabels();
    final package = tree.foregroundPackage ?? 'unknown';
    if (labels.isEmpty) return 'on screen ($package): nothing labelled';
    return 'on screen ($package): ${labels.map((l) => '"$l"').join(' | ')}';
  }

  /// Without [nth] a match on screen wins over its scrolled-out duplicates.
  /// [nth] numbers every match in traversal order, out-of-view ones
  /// included, so a hidden duplicate of a visible label stays reachable
  /// (and is then revealed) and the number does not shift when a scroll
  /// changes which of them are on screen.
  ResolvedTarget _pick(List<TargetMatch> all, String target, int? nth) {
    if (all.isEmpty) {
      throw TargetFailure(
        'no node matches "$target". ${onScreenListing()}',
      );
    }
    final ordered = [...all]..sort((a, b) => a.node.index.compareTo(b.node.index));
    if (nth != null) {
      if (nth < 0 || nth >= ordered.length) {
        throw TargetFailure(
          '--nth $nth is out of range: "$target" has ${ordered.length} '
          'match(es) (0..${ordered.length - 1}).',
        );
      }
      return fromNode(ordered[nth].node);
    }
    final visible = ordered.where((m) => !m.node.outOfView).toList();
    final matches = visible.isNotEmpty ? visible : ordered;
    if (matches.length > 1) {
      final listing = [
        for (final match in matches)
          '  --nth ${ordered.indexOf(match)}  ${match.node.describe()}',
      ];
      throw TargetFailure(
        '"$target" is ambiguous: ${matches.length} matches. '
        'Re-run with --nth N:\n${listing.join('\n')}',
      );
    }
    return fromNode(matches.single.node);
  }

  /// [node] as a target, for a caller that already holds the node (found
  /// again by its semantics id after a reveal) rather than a target string.
  ResolvedTarget fromNode(UiNode node) => ResolvedTarget(
        x: node.bounds.centreX,
        y: node.bounds.centreY,
        description: node.describe(),
        node: node,
      );
}

/// A target resolved for acting on, after the app was asked to bring it
/// into view when it had been scrolled out.
class RevealOutcome {
  const RevealOutcome({
    required this.resolved,
    required this.tree,
    required this.revealed,
    this.note,
  });

  final ResolvedTarget resolved;

  /// The tree [resolved] came from: the fresh dump when [revealed].
  final UiTree tree;

  /// Whether the app was asked to scroll the node into view.
  final bool revealed;

  /// Set when the revealed node could not be found again by its id and
  /// [resolved] is the label's match in the new tree instead.
  final String? note;

  bool get onScreen => !(resolved.node?.outOfView ?? false);
}

/// Resolves [target] in [tree]; when the match is out of view and [reveal]
/// is given, asks the app to scroll it in, dumps again through [redump] and
/// finds the same node there by its semantics id.
///
/// Flutter keeps a scrolled-out row in the semantics tree (inside the
/// viewport's cache extent, and a sheet's whole content), so the node is
/// known but its rect is useless for a tap; revealing it here is what keeps
/// a flow from failing on the fold. The id, not the label and `--nth`, is
/// what finds it again: the scroll changes which duplicates are on screen,
/// so a position among them can name another row. Only when the id is gone
/// is the label resolved once more, and [RevealOutcome.note] says so. [reveal]
/// is null on the adb path, which has no such action: an out-of-view match
/// then comes back as it is, and so does a `#N` read from a uiautomator dump,
/// which carries no id to reveal by.
Future<RevealOutcome> resolveRevealing(
  String target,
  UiTree tree, {
  int? nth,
  required Future<void> Function(UiNode node)? reveal,
  required Future<UiTree> Function() redump,
}) async {
  final resolved = TargetResolver(tree).resolve(target, nth: nth);
  final node = resolved.node;
  final indexTarget = isIndexTarget(target);
  if (reveal == null ||
      node == null ||
      !node.outOfView ||
      (indexTarget && node.semanticsId == null)) {
    return RevealOutcome(resolved: resolved, tree: tree, revealed: false);
  }
  await reveal(node);
  final fresh = await redump();
  final id = node.semanticsId;
  final again = id == null ? null : fresh.bySemanticsId(id);
  if (again != null) {
    return RevealOutcome(
      resolved: TargetResolver(fresh).fromNode(again),
      tree: fresh,
      revealed: true,
    );
  }
  if (indexTarget) {
    throw TargetFailure('$target (semantics id $id) is not in the dump taken '
        'after revealing it — `look` again and pick its new #N');
  }
  return RevealOutcome(
    resolved: TargetResolver(fresh).resolve(target, nth: nth),
    tree: fresh,
    revealed: true,
    note: 'the revealed node (semantics id $id) is not in the new dump; '
        '"$target" was resolved again by its label',
  );
}

/// Why an acting verb gives up on a node the app could not bring into view.
String offScreenAfterReveal(String target) =>
    '"$target" is off screen even after asking the app to scroll it into '
    'view; scroll-to it first (with --in <scrollable> when it is not in the '
    'first list on screen)';
