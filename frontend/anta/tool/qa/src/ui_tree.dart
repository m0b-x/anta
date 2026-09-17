import 'dart:convert';

import 'package:xml/xml.dart';

import 'agent_protocol.dart';
import 'errors.dart';

/// Integer rectangle in device pixels, as `uiautomator` reports bounds.
class UiRect {
  const UiRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;

  int get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  int get centreX => left + width ~/ 2;

  int get centreY => top + height ~/ 2;

  @override
  String toString() => '[$left,$top][$right,$bottom]';

  static UiRect? tryParse(String raw) {
    final match =
        RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]').firstMatch(raw);
    if (match == null) return null;
    return UiRect(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
  }
}

/// Where a tree came from, which decides how its package is read.
enum UiTreeSource { uiautomator, agent }

/// One flattened node of an accessibility tree — an `adb shell uiautomator
/// dump` node on Android, a Flutter semantics node from the in-app agent
/// elsewhere.
class UiNode {
  const UiNode({
    required this.index,
    required this.parentIndex,
    required this.depth,
    required this.className,
    required this.text,
    required this.contentDesc,
    required this.resourceId,
    required this.packageName,
    required this.bounds,
    required this.clickable,
    required this.longClickable,
    required this.enabled,
    required this.focused,
    required this.focusable,
    required this.checked,
    required this.checkable,
    required this.selected,
    required this.scrollable,
    this.hidden = false,
    this.hint = '',
  });

  final int index;
  final int parentIndex;
  final int depth;
  final String className;
  final String text;
  final String contentDesc;
  final String resourceId;
  final String packageName;
  final UiRect bounds;
  final bool clickable;
  final bool longClickable;
  final bool enabled;
  final bool focused;
  final bool focusable;
  final bool checked;
  final bool checkable;
  final bool selected;
  final bool scrollable;

  /// Off screen: scrolled out of a list, or flagged hidden by the app. Such a
  /// node is real but cannot be tapped until `scroll-to` brings it in.
  final bool hidden;

  final String hint;

  /// The short class name, e.g. `Button` for `android.widget.Button`.
  String get shortClass {
    final dot = className.lastIndexOf('.');
    return dot == -1 ? className : className.substring(dot + 1);
  }

  /// The resource id without its package prefix.
  String get shortId {
    final slash = resourceId.lastIndexOf('/');
    return slash == -1 ? resourceId : resourceId.substring(slash + 1);
  }

  /// The best human label for this node: content description, then text.
  String get label => contentDesc.isNotEmpty
      ? contentDesc
      : (text.isNotEmpty ? text : shortId);

  bool get hasLabel =>
      contentDesc.isNotEmpty || text.isNotEmpty || resourceId.isNotEmpty;

  bool get interesting => !hidden && (hasLabel || clickable || scrollable);

  String get flags {
    final on = <String>[
      if (clickable) 'click',
      if (longClickable) 'long',
      if (scrollable) 'scroll',
      if (focused) 'focused',
      if (checkable) checked ? 'checked' : 'unchecked',
      if (selected) 'selected',
      if (!enabled) 'disabled',
      if (hidden) 'hidden',
    ];
    return on.join(',');
  }

  String describe() {
    final parts = <String>[
      '#$index',
      shortClass,
      if (contentDesc.isNotEmpty) '"$contentDesc"',
      if (text.isNotEmpty) 'text="$text"',
      if (hint.isNotEmpty) 'hint="$hint"',
      if (resourceId.isNotEmpty) 'id=$shortId',
      bounds.toString(),
      if (flags.isNotEmpty) flags,
    ];
    return parts.join('  ');
  }

  Map<String, Object?> toJson() => {
        'index': index,
        'parent': parentIndex,
        'depth': depth,
        'class': className,
        'text': text,
        'desc': contentDesc,
        if (hint.isNotEmpty) 'hint': hint,
        'id': resourceId,
        'package': packageName,
        'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
        'centre': [bounds.centreX, bounds.centreY],
        'clickable': clickable,
        'longClickable': longClickable,
        'enabled': enabled,
        'focused': focused,
        'checked': checked,
        'selected': selected,
        'scrollable': scrollable,
        'hidden': hidden,
      };
}

/// A parsed, flattened accessibility hierarchy.
class UiTree {
  const UiTree(this.nodes, {this.source = UiTreeSource.uiautomator});

  final List<UiNode> nodes;

  final UiTreeSource source;

  bool get isEmpty => nodes.isEmpty;

  UiNode? byIndex(int index) {
    for (final node in nodes) {
      if (node.index == index) return node;
    }
    return null;
  }

  UiNode? parentOf(UiNode node) =>
      node.parentIndex < 0 ? null : byIndex(node.parentIndex);

  /// The node itself if clickable, otherwise the nearest clickable ancestor.
  UiNode? clickableSelfOrAncestor(UiNode node) {
    var current = node;
    for (var hops = 0; hops < 12; hops++) {
      if (current.clickable) return current;
      final parent = parentOf(current);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  /// Innermost scrollable node whose bounds contain the given point.
  UiNode? scrollableAt(int x, int y) {
    UiNode? best;
    for (final node in nodes) {
      if (!node.scrollable || node.hidden) continue;
      final b = node.bounds;
      if (x < b.left || x > b.right || y < b.top || y > b.bottom) continue;
      if (best == null ||
          b.width * b.height < best.bounds.width * best.bounds.height) {
        best = node;
      }
    }
    return best;
  }

  UiNode? get firstScrollable {
    for (final node in nodes) {
      if (node.scrollable && !node.hidden) return node;
    }
    return null;
  }

  /// Package that owns the screen this dump was taken from.
  ///
  /// The largest top-level window wins, because that is the window the user is
  /// actually looking at; a dump with no top-level node falls back to the
  /// commonest package that is not part of the system chrome, so a dialog
  /// drawn over the app still reports the dialog's owner rather than the
  /// status bar's.
  String? get foregroundPackage {
    UiNode? largest;
    for (final node in nodes) {
      if (node.parentIndex != -1) continue;
      if (node.packageName.isEmpty) continue;
      if (_systemPackages.contains(node.packageName)) continue;
      final area = node.bounds.width * node.bounds.height;
      if (largest == null ||
          area > largest.bounds.width * largest.bounds.height) {
        largest = node;
      }
    }
    if (largest != null) return largest.packageName;

    final counts = <String, int>{};
    for (final node in nodes) {
      if (node.packageName.isEmpty) continue;
      if (_systemPackages.contains(node.packageName)) continue;
      counts[node.packageName] = (counts[node.packageName] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var best = counts.keys.first;
    counts.forEach((package, count) {
      if (count > (counts[best] ?? 0)) best = package;
    });
    return best;
  }

  /// Up to [limit] labels in tree order, for telling a failed lookup what it
  /// could have matched instead.
  ///
  /// Nodes that carry a real label come first and nodes identified only by a
  /// resource id fill the rest: a screen has far more ids than labels, and a
  /// listing drowned in `drag_layer` and `scrim_view` tells the reader
  /// nothing about which screen they are on.
  List<String> interestingLabels({int limit = 20, int clip = 40}) {
    final labels = <String>[];
    final ids = <String>[];

    String? clean(String raw) {
      final text = raw.replaceAll('\n', ' / ').trim();
      if (text.isEmpty) return null;
      return text.length <= clip ? text : '${text.substring(0, clip - 1)}…';
    }

    for (final node in nodes) {
      if (!node.interesting) continue;
      final described = node.contentDesc.isNotEmpty
          ? clean(node.contentDesc)
          : (node.text.isNotEmpty ? clean(node.text) : null);
      if (described != null) {
        if (!labels.contains(described)) labels.add(described);
        continue;
      }
      final id = clean(node.shortId);
      if (id != null && !ids.contains('id:$id')) ids.add('id:$id');
    }
    final combined = [...labels, ...ids];
    return combined.length <= limit ? combined : combined.sublist(0, limit);
  }

  /// Chrome that is drawn over every app and so never identifies the screen.
  static const Set<String> _systemPackages = {
    'com.android.systemui',
    'android',
  };

  /// Parses `uiautomator dump` XML, dropping zero-size nodes.
  static UiTree parse(String rawXml) {
    final start = _xmlStart(rawXml);
    if (start == null) {
      throw DeviceFailure(
        'uiautomator dump produced no XML. Output was:\n'
        '${rawXml.trim().split('\n').take(5).join('\n')}',
      );
    }
    final XmlDocument document;
    try {
      document = XmlDocument.parse(rawXml.substring(start));
    } on XmlException catch (e) {
      throw DeviceFailure('uiautomator dump XML is malformed: ${e.message}');
    }
    final nodes = <UiNode>[];
    var counter = 0;

    void walk(XmlElement element, int parentIndex, int depth) {
      var myIndex = parentIndex;
      var childDepth = depth;
      if (element.name.local == 'node') {
        final bounds = UiRect.tryParse(_attr(element, 'bounds'));
        if (bounds != null && !bounds.isEmpty) {
          myIndex = counter++;
          nodes.add(UiNode(
            index: myIndex,
            parentIndex: parentIndex,
            depth: depth,
            className: _attr(element, 'class'),
            text: _attr(element, 'text'),
            contentDesc: _attr(element, 'content-desc'),
            resourceId: _attr(element, 'resource-id'),
            packageName: _attr(element, 'package'),
            bounds: bounds,
            clickable: _flag(element, 'clickable'),
            longClickable: _flag(element, 'long-clickable'),
            enabled: _flag(element, 'enabled', fallback: true),
            focused: _flag(element, 'focused'),
            focusable: _flag(element, 'focusable'),
            checked: _flag(element, 'checked'),
            checkable: _flag(element, 'checkable'),
            selected: _flag(element, 'selected'),
            scrollable: _flag(element, 'scrollable'),
          ));
          childDepth = depth + 1;
        }
      }
      for (final child in element.childElements) {
        walk(child, myIndex, childDepth);
      }
    }

    walk(document.rootElement, -1, 0);
    return UiTree(nodes);
  }

  /// Parses the JSON the in-app agent's `dump` op returns.
  ///
  /// The shape mirrors what Android's accessibility bridge derives from the
  /// same semantics nodes: the label (with the tooltip appended) is the
  /// content description, the value is the text, and `Semantics.identifier`
  /// is the resource id — so a target that works on the emulator works here.
  static UiTree fromAgentJson(String json, {required String appPackage}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw DeviceFailure('the agent dump is not JSON: ${e.message}');
    }
    if (decoded is! Map) throw DeviceFailure('the agent dump has no nodes');
    return fromAgentMap(decoded, appPackage: appPackage);
  }

  /// The same, from a reply that is already decoded.
  static UiTree fromAgentMap(Map<dynamic, dynamic> decoded, {required String appPackage}) {
    if (decoded[AgentKeys.nodes] is! List) {
      throw DeviceFailure('the agent dump has no nodes');
    }
    final nodes = <UiNode>[];
    for (final entry in decoded[AgentKeys.nodes] as List) {
      if (entry is! Map) continue;
      final rect = entry[AgentNodeKeys.rect];
      if (rect is! List || rect.length != 4) continue;
      final bounds = UiRect(
        (rect[0] as num).toInt(),
        (rect[1] as num).toInt(),
        (rect[2] as num).toInt(),
        (rect[3] as num).toInt(),
      );
      final flags = ((entry[AgentNodeKeys.flags] as List?) ?? const [])
          .map((f) => '$f')
          .toSet();
      final label = '${entry[AgentNodeKeys.label] ?? ''}';
      final tooltip = '${entry[AgentNodeKeys.tooltip] ?? ''}';
      final contentDesc = tooltip.isEmpty || tooltip == label
          ? label
          : (label.isEmpty ? tooltip : '$label\n$tooltip');
      final clickable = flags.contains(AgentFlags.click);
      final textField = flags.contains(AgentFlags.textField);
      nodes.add(UiNode(
        index: (entry[AgentNodeKeys.index] as num).toInt(),
        parentIndex: (entry[AgentNodeKeys.parent] as num? ?? -1).toInt(),
        depth: (entry[AgentNodeKeys.depth] as num? ?? 0).toInt(),
        className: classForAgentFlags(flags),
        text: '${entry[AgentNodeKeys.value] ?? ''}',
        contentDesc: contentDesc,
        resourceId: '${entry[AgentNodeKeys.identifier] ?? ''}',
        packageName: appPackage,
        bounds: bounds,
        clickable: clickable,
        longClickable: flags.contains(AgentFlags.long),
        enabled: !flags.contains(AgentFlags.disabled),
        focused: flags.contains(AgentFlags.focused),
        focusable: clickable || textField,
        checked: flags.contains(AgentFlags.checked),
        checkable: flags.contains(AgentFlags.checkable),
        selected: flags.contains(AgentFlags.selected),
        scrollable: flags.contains(AgentFlags.scroll),
        hidden: flags.contains(AgentFlags.hidden),
        hint: '${entry[AgentNodeKeys.hint] ?? ''}',
      ));
    }
    return UiTree(nodes, source: UiTreeSource.agent);
  }

  /// The pseudo class a semantics node shows as, chosen to read like the
  /// Android dump so the two surfaces stay comparable.
  static String classForAgentFlags(Set<String> flags) {
    if (flags.contains(AgentFlags.textField)) return 'EditText';
    if (flags.contains(AgentFlags.button)) return 'Button';
    if (flags.contains(AgentFlags.toggle)) return 'Switch';
    if (flags.contains(AgentFlags.checkable)) return 'CheckBox';
    if (flags.contains(AgentFlags.slider)) return 'Slider';
    if (flags.contains(AgentFlags.link)) return 'Link';
    if (flags.contains(AgentFlags.image)) return 'Image';
    if (flags.contains(AgentFlags.header)) return 'Header';
    if (flags.contains(AgentFlags.scroll)) return 'Scroll';
    return 'View';
  }

  static int? _xmlStart(String raw) {
    final declaration = raw.indexOf('<?xml');
    if (declaration >= 0) return declaration;
    final hierarchy = raw.indexOf('<hierarchy');
    if (hierarchy >= 0) return hierarchy;
    return null;
  }

  static String _attr(XmlElement element, String name) =>
      element.getAttribute(name) ?? '';

  static bool _flag(XmlElement element, String name, {bool fallback = false}) {
    final value = element.getAttribute(name);
    if (value == null) return fallback;
    return value == 'true';
  }
}

/// Parses a cached or live dump in whichever format it was captured.
UiTree parseDumpText(String text, {required String appPackage}) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{')) {
    return UiTree.fromAgentJson(trimmed, appPackage: appPackage);
  }
  return UiTree.parse(text);
}
