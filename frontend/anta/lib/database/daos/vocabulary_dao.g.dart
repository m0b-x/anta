// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vocabulary_dao.dart';

// ignore_for_file: type=lint
mixin _$VocabularyDaoMixin on DatabaseAccessor<AppDatabase> {
  $VocabulariesTable get vocabularies => attachedDatabase.vocabularies;
  $VocabularyItemsTable get vocabularyItems => attachedDatabase.vocabularyItems;
  VocabularyDaoManager get managers => VocabularyDaoManager(this);
}

class VocabularyDaoManager {
  final _$VocabularyDaoMixin _db;
  VocabularyDaoManager(this._db);
  $$VocabulariesTableTableManager get vocabularies =>
      $$VocabulariesTableTableManager(_db.attachedDatabase, _db.vocabularies);
  $$VocabularyItemsTableTableManager get vocabularyItems =>
      $$VocabularyItemsTableTableManager(
        _db.attachedDatabase,
        _db.vocabularyItems,
      );
}
