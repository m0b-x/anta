import 'package:flutter_test/flutter_test.dart';

import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/markdown_bar_profile.dart';

/// The shipped bar only decides what a new profile starts with:
/// `MarkdownBarService` writes the defaults when no default profile is
/// stored and otherwise decodes the stored profiles as saved, appending
/// only the one-time seeds. So the order and visibility pinned here reach
/// new installs (and Reset), never an existing bar.
void main() {
  final defaults = DefaultMarkdownShortcuts.shortcuts;
  List<String> ids(Iterable<CustomMarkdownShortcut> s) => [
    for (final shortcut in s) shortcut.id,
  ];

  test('the list markers and the emphases lead the bar', () {
    expect(ids(defaults.take(6)), [
      'default_checkbox',
      'default_bullet_list',
      'default_numbered_list',
      'default_bold',
      'default_italic',
      'default_header',
    ]);
  });

  test('one bullet button shows; the point list stays available', () {
    final point = defaults.singleWhere((s) => s.id == 'default_point_list');
    expect(point.isVisible, isFalse);
    expect(
      defaults.where((s) => s.isVisible && s.beforeText == '- '),
      hasLength(1),
    );
  });

  test('the line-prefix ids are exactly the defaults typed as toggles', () {
    expect(
      ids(
        defaults.where(
          (s) => s.insertType == CustomMarkdownShortcut.linePrefixType,
        ),
      ).toSet(),
      DefaultMarkdownShortcuts.linePrefixIds,
    );
  });

  test('ids are unique', () {
    expect(ids(defaults).toSet(), hasLength(defaults.length));
  });

  test('a stored profile decodes in its own order with its own types', () {
    // An existing install's bar: the old order, the list shortcuts saved as
    // plain wraps. Decoding is all the service does with it.
    final stored = [
      for (final s in defaults.reversed)
        s.insertType == CustomMarkdownShortcut.linePrefixType
            ? s.copyWith(insertType: 'wrap')
            : s,
    ];
    final encoded = MarkdownBarProfile.encodeList([
      MarkdownBarProfile(
        id: MarkdownBarProfile.defaultProfileId,
        name: 'Default',
        isDefault: true,
        shortcuts: stored,
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);

    final decoded = MarkdownBarProfile.decodeList(encoded).single.shortcuts;

    expect(ids(decoded), ids(stored));
    expect(decoded, stored);
  });

  test('the money ids are exactly the ten `default_money*` shortcuts', () {
    expect(
      DefaultMarkdownShortcuts.moneyIds,
      ids(defaults.where((s) => s.id.startsWith('default_money'))).toSet(),
    );
    expect(DefaultMarkdownShortcuts.moneyIds, hasLength(10));
  });

  test('the money shortcuts ship hidden; everything else but the point '
      'list shows', () {
    // The ledger is off by default, so a `$+` button would insert a line the
    // note renders as plain text — the switch reveals them instead.
    for (final shortcut in defaults) {
      final expected =
          !DefaultMarkdownShortcuts.moneyIds.contains(shortcut.id) &&
          shortcut.id != 'default_point_list';
      expect(shortcut.isVisible, expected, reason: shortcut.id);
    }
  });
}
