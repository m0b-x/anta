import 'package:flutter_test/flutter_test.dart';

import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/markdown_bar_profile.dart';
import 'package:anta/services/markdown_bar_service.dart';

import '../database/support/db_test_support.dart';

/// The money shortcuts follow the ledger switch (2026-10-30): hidden in a new
/// install's bar, shown in every profile when the ledger comes on, hidden
/// again when it goes off — and nothing else in a profile moves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(MarkdownBarService.reset);

  Iterable<CustomMarkdownShortcut> moneyOf(MarkdownBarProfile profile) =>
      profile.shortcuts.where(
        (s) => DefaultMarkdownShortcuts.moneyIds.contains(s.id),
      );
  List<CustomMarkdownShortcut> restOf(MarkdownBarProfile profile) => [
    for (final s in profile.shortcuts)
      if (!DefaultMarkdownShortcuts.moneyIds.contains(s.id)) s,
  ];

  test('a new install hides the ten money shortcuts in its default bar', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final service = await MarkdownBarService.forTesting(db);

    final money = moneyOf(service.profiles.single).toList();

    expect(money, hasLength(10));
    expect(money.every((s) => !s.isVisible), isTrue);
  });

  test('the switch shows and hides them in every profile and touches '
      'nothing else', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final service = await MarkdownBarService.forTesting(db);
    await service.addProfile('Second');
    final others = [for (final p in service.profiles) restOf(p)];

    await service.setMoneyShortcutsVisible(true);
    for (final profile in service.profiles) {
      expect(
        moneyOf(profile).every((s) => s.isVisible),
        isTrue,
        reason: profile.name,
      );
    }
    expect([for (final p in service.profiles) restOf(p)], others);

    await service.setMoneyShortcutsVisible(false);
    for (final profile in service.profiles) {
      expect(
        moneyOf(profile).every((s) => !s.isVisible),
        isTrue,
        reason: profile.name,
      );
    }
    expect([for (final p in service.profiles) restOf(p)], others);
  });

  test('a user-made money button keeps its own visibility, and a profile '
      'already in step is not restamped', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final service = await MarkdownBarService.forTesting(db);
    final profile = service.profiles.single;
    const custom = CustomMarkdownShortcut(
      id: 'custom_spent',
      label: 'Spent',
      iconCodePoint: 0xe227,
      iconFontFamily: 'MaterialIcons',
      beforeText: '\$- ',
      afterText: '',
      isVisible: false,
    );
    await service.updateShortcuts(profile.id, [...profile.shortcuts, custom]);
    final stamped = service.profiles.single.updatedAt;

    // Already hidden: nothing to write, so the profile's stamp stays honest.
    await service.setMoneyShortcutsVisible(false);
    expect(service.profiles.single.updatedAt, stamped);

    await service.setMoneyShortcutsVisible(true);
    final after = service.profiles.single;
    expect(moneyOf(after).every((s) => s.isVisible), isTrue);
    expect(
      after.shortcuts.singleWhere((s) => s.id == custom.id).isVisible,
      isFalse,
    );
  });

  test('the visibility is what the next load reads back', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final service = await MarkdownBarService.forTesting(db);
    await service.setMoneyShortcutsVisible(true);

    MarkdownBarService.reset();
    final reloaded = await MarkdownBarService.forTesting(db);

    expect(moneyOf(reloaded.profiles.single).every((s) => s.isVisible), isTrue);
  });
}
