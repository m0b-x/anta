import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/public_holiday_service.dart';

import '../database/support/db_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(PublicHolidayService.reset);

  test('two cold callers at once get one instance', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final first = PublicHolidayService.forTesting(db);
    final second = PublicHolidayService.forTesting(db);
    final services = await Future.wait([first, second]);

    expect(identical(services[0], services[1]), isTrue);
    expect(
      identical(await PublicHolidayService.forTesting(db), services[0]),
      isTrue,
    );
  });

  test('a reset lets the next caller build a fresh one', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final before = await PublicHolidayService.forTesting(db);
    PublicHolidayService.reset();
    final after = await PublicHolidayService.forTesting(db);

    expect(identical(before, after), isFalse);
  });
}
