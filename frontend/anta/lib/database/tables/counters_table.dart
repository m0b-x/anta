import 'package:drift/drift.dart';

@DataClassName('CounterRow')
class Counters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get startValue => integer().withDefault(const Constant(1))();
  IntColumn get step => integer().withDefault(const Constant(1))();
  TextColumn get scope => text().withDefault(const Constant('global'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
