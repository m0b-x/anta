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
      return _fromNode(node);
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

  ResolvedTarget _pick(List<TargetMatch> all, String target, int? nth) {
    if (all.isEmpty) {
      throw TargetFailure(
        'no node matches "$target". ${onScreenListing()}',
      );
    }
    final visible = all.where((m) => !m.node.hidden).toList();
    final matches = visible.isNotEmpty ? visible : all;
    if (nth != null) {
      if (nth < 0 || nth >= matches.length) {
        throw TargetFailure(
          '--nth $nth is out of range: "$target" has ${matches.length} '
          'match(es) (0..${matches.length - 1}).',
        );
      }
      return _fromNode(matches[nth].node);
    }
    if (matches.length > 1) {
      final listing = <String>[];
      for (var i = 0; i < matches.length; i++) {
        listing.add('  --nth $i  ${matches[i].node.describe()}');
      }
      throw TargetFailure(
        '"$target" is ambiguous: ${matches.length} matches. '
        'Re-run with --nth N:\n${listing.join('\n')}',
      );
    }
    return _fromNode(matches.single.node);
  }

  ResolvedTarget _fromNode(UiNode node) => ResolvedTarget(
        x: node.bounds.centreX,
        y: node.bounds.centreY,
        description: node.describe(),
        node: node,
      );
}
