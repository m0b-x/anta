// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteSortOrderMeta = const VerificationMeta(
    'noteSortOrder',
  );
  @override
  late final GeneratedColumn<String> noteSortOrder = GeneratedColumn<String>(
    'note_sort_order',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subfolderSortOrderMeta =
      const VerificationMeta('subfolderSortOrder');
  @override
  late final GeneratedColumn<String> subfolderSortOrder =
      GeneratedColumn<String>(
        'subfolder_sort_order',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _hlcTimestampMeta = const VerificationMeta(
    'hlcTimestamp',
  );
  @override
  late final GeneratedColumn<String> hlcTimestamp = GeneratedColumn<String>(
    'hlc_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    parentId,
    position,
    createdAt,
    updatedAt,
    noteSortOrder,
    subfolderSortOrder,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('note_sort_order')) {
      context.handle(
        _noteSortOrderMeta,
        noteSortOrder.isAcceptableOrUnknown(
          data['note_sort_order']!,
          _noteSortOrderMeta,
        ),
      );
    }
    if (data.containsKey('subfolder_sort_order')) {
      context.handle(
        _subfolderSortOrderMeta,
        subfolderSortOrder.isAcceptableOrUnknown(
          data['subfolder_sort_order']!,
          _subfolderSortOrderMeta,
        ),
      );
    }
    if (data.containsKey('hlc_timestamp')) {
      context.handle(
        _hlcTimestampMeta,
        hlcTimestamp.isAcceptableOrUnknown(
          data['hlc_timestamp']!,
          _hlcTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hlcTimestampMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      noteSortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_sort_order'],
      ),
      subfolderSortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subfolder_sort_order'],
      ),
      hlcTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc_timestamp'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final String id;
  final String name;
  final String? parentId;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? noteSortOrder;
  final String? subfolderSortOrder;
  final String hlcTimestamp;
  final String deviceId;
  final int version;
  final bool isDeleted;
  final DateTime? deletedAt;
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    this.noteSortOrder,
    this.subfolderSortOrder,
    required this.hlcTimestamp,
    required this.deviceId,
    required this.version,
    required this.isDeleted,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || noteSortOrder != null) {
      map['note_sort_order'] = Variable<String>(noteSortOrder);
    }
    if (!nullToAbsent || subfolderSortOrder != null) {
      map['subfolder_sort_order'] = Variable<String>(subfolderSortOrder);
    }
    map['hlc_timestamp'] = Variable<String>(hlcTimestamp);
    map['device_id'] = Variable<String>(deviceId);
    map['version'] = Variable<int>(version);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      noteSortOrder: noteSortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(noteSortOrder),
      subfolderSortOrder: subfolderSortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(subfolderSortOrder),
      hlcTimestamp: Value(hlcTimestamp),
      deviceId: Value(deviceId),
      version: Value(version),
      isDeleted: Value(isDeleted),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      noteSortOrder: serializer.fromJson<String?>(json['noteSortOrder']),
      subfolderSortOrder: serializer.fromJson<String?>(
        json['subfolderSortOrder'],
      ),
      hlcTimestamp: serializer.fromJson<String>(json['hlcTimestamp']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      version: serializer.fromJson<int>(json['version']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'noteSortOrder': serializer.toJson<String?>(noteSortOrder),
      'subfolderSortOrder': serializer.toJson<String?>(subfolderSortOrder),
      'hlcTimestamp': serializer.toJson<String>(hlcTimestamp),
      'deviceId': serializer.toJson<String>(deviceId),
      'version': serializer.toJson<int>(version),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Folder copyWith({
    String? id,
    String? name,
    Value<String?> parentId = const Value.absent(),
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> noteSortOrder = const Value.absent(),
    Value<String?> subfolderSortOrder = const Value.absent(),
    String? hlcTimestamp,
    String? deviceId,
    int? version,
    bool? isDeleted,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Folder(
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId.present ? parentId.value : this.parentId,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    noteSortOrder: noteSortOrder.present
        ? noteSortOrder.value
        : this.noteSortOrder,
    subfolderSortOrder: subfolderSortOrder.present
        ? subfolderSortOrder.value
        : this.subfolderSortOrder,
    hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
    deviceId: deviceId ?? this.deviceId,
    version: version ?? this.version,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      noteSortOrder: data.noteSortOrder.present
          ? data.noteSortOrder.value
          : this.noteSortOrder,
      subfolderSortOrder: data.subfolderSortOrder.present
          ? data.subfolderSortOrder.value
          : this.subfolderSortOrder,
      hlcTimestamp: data.hlcTimestamp.present
          ? data.hlcTimestamp.value
          : this.hlcTimestamp,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      version: data.version.present ? data.version.value : this.version,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('noteSortOrder: $noteSortOrder, ')
          ..write('subfolderSortOrder: $subfolderSortOrder, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    parentId,
    position,
    createdAt,
    updatedAt,
    noteSortOrder,
    subfolderSortOrder,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.noteSortOrder == this.noteSortOrder &&
          other.subfolderSortOrder == this.subfolderSortOrder &&
          other.hlcTimestamp == this.hlcTimestamp &&
          other.deviceId == this.deviceId &&
          other.version == this.version &&
          other.isDeleted == this.isDeleted &&
          other.deletedAt == this.deletedAt);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> noteSortOrder;
  final Value<String?> subfolderSortOrder;
  final Value<String> hlcTimestamp;
  final Value<String> deviceId;
  final Value<int> version;
  final Value<bool> isDeleted;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.noteSortOrder = const Value.absent(),
    this.subfolderSortOrder = const Value.absent(),
    this.hlcTimestamp = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.noteSortOrder = const Value.absent(),
    this.subfolderSortOrder = const Value.absent(),
    required String hlcTimestamp,
    required String deviceId,
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlcTimestamp = Value(hlcTimestamp),
       deviceId = Value(deviceId);
  static Insertable<Folder> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? noteSortOrder,
    Expression<String>? subfolderSortOrder,
    Expression<String>? hlcTimestamp,
    Expression<String>? deviceId,
    Expression<int>? version,
    Expression<bool>? isDeleted,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (noteSortOrder != null) 'note_sort_order': noteSortOrder,
      if (subfolderSortOrder != null)
        'subfolder_sort_order': subfolderSortOrder,
      if (hlcTimestamp != null) 'hlc_timestamp': hlcTimestamp,
      if (deviceId != null) 'device_id': deviceId,
      if (version != null) 'version': version,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? parentId,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? noteSortOrder,
    Value<String?>? subfolderSortOrder,
    Value<String>? hlcTimestamp,
    Value<String>? deviceId,
    Value<int>? version,
    Value<bool>? isDeleted,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      noteSortOrder: noteSortOrder ?? this.noteSortOrder,
      subfolderSortOrder: subfolderSortOrder ?? this.subfolderSortOrder,
      hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (noteSortOrder.present) {
      map['note_sort_order'] = Variable<String>(noteSortOrder.value);
    }
    if (subfolderSortOrder.present) {
      map['subfolder_sort_order'] = Variable<String>(subfolderSortOrder.value);
    }
    if (hlcTimestamp.present) {
      map['hlc_timestamp'] = Variable<String>(hlcTimestamp.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('noteSortOrder: $noteSortOrder, ')
          ..write('subfolderSortOrder: $subfolderSortOrder, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 0,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contentLengthMeta = const VerificationMeta(
    'contentLength',
  );
  @override
  late final GeneratedColumn<int> contentLength = GeneratedColumn<int>(
    'content_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chunkCountMeta = const VerificationMeta(
    'chunkCount',
  );
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
    'chunk_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isCompressedMeta = const VerificationMeta(
    'isCompressed',
  );
  @override
  late final GeneratedColumn<bool> isCompressed = GeneratedColumn<bool>(
    'is_compressed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_compressed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcTimestampMeta = const VerificationMeta(
    'hlcTimestamp',
  );
  @override
  late final GeneratedColumn<String> hlcTimestamp = GeneratedColumn<String>(
    'hlc_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    folderId,
    title,
    preview,
    contentLength,
    chunkCount,
    isCompressed,
    position,
    createdAt,
    updatedAt,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    }
    if (data.containsKey('content_length')) {
      context.handle(
        _contentLengthMeta,
        contentLength.isAcceptableOrUnknown(
          data['content_length']!,
          _contentLengthMeta,
        ),
      );
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
        _chunkCountMeta,
        chunkCount.isAcceptableOrUnknown(data['chunk_count']!, _chunkCountMeta),
      );
    }
    if (data.containsKey('is_compressed')) {
      context.handle(
        _isCompressedMeta,
        isCompressed.isAcceptableOrUnknown(
          data['is_compressed']!,
          _isCompressedMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('hlc_timestamp')) {
      context.handle(
        _hlcTimestampMeta,
        hlcTimestamp.isAcceptableOrUnknown(
          data['hlc_timestamp']!,
          _hlcTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hlcTimestampMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      )!,
      contentLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_length'],
      )!,
      chunkCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_count'],
      )!,
      isCompressed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_compressed'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      hlcTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc_timestamp'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final String id;
  final String folderId;
  final String title;
  final String preview;
  final int contentLength;
  final int chunkCount;
  final bool isCompressed;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String hlcTimestamp;
  final String deviceId;
  final int version;
  final bool isDeleted;
  final DateTime? deletedAt;
  const Note({
    required this.id,
    required this.folderId,
    required this.title,
    required this.preview,
    required this.contentLength,
    required this.chunkCount,
    required this.isCompressed,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    required this.hlcTimestamp,
    required this.deviceId,
    required this.version,
    required this.isDeleted,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['folder_id'] = Variable<String>(folderId);
    map['title'] = Variable<String>(title);
    map['preview'] = Variable<String>(preview);
    map['content_length'] = Variable<int>(contentLength);
    map['chunk_count'] = Variable<int>(chunkCount);
    map['is_compressed'] = Variable<bool>(isCompressed);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['hlc_timestamp'] = Variable<String>(hlcTimestamp);
    map['device_id'] = Variable<String>(deviceId);
    map['version'] = Variable<int>(version);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      folderId: Value(folderId),
      title: Value(title),
      preview: Value(preview),
      contentLength: Value(contentLength),
      chunkCount: Value(chunkCount),
      isCompressed: Value(isCompressed),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      hlcTimestamp: Value(hlcTimestamp),
      deviceId: Value(deviceId),
      version: Value(version),
      isDeleted: Value(isDeleted),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      folderId: serializer.fromJson<String>(json['folderId']),
      title: serializer.fromJson<String>(json['title']),
      preview: serializer.fromJson<String>(json['preview']),
      contentLength: serializer.fromJson<int>(json['contentLength']),
      chunkCount: serializer.fromJson<int>(json['chunkCount']),
      isCompressed: serializer.fromJson<bool>(json['isCompressed']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      hlcTimestamp: serializer.fromJson<String>(json['hlcTimestamp']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      version: serializer.fromJson<int>(json['version']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'folderId': serializer.toJson<String>(folderId),
      'title': serializer.toJson<String>(title),
      'preview': serializer.toJson<String>(preview),
      'contentLength': serializer.toJson<int>(contentLength),
      'chunkCount': serializer.toJson<int>(chunkCount),
      'isCompressed': serializer.toJson<bool>(isCompressed),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'hlcTimestamp': serializer.toJson<String>(hlcTimestamp),
      'deviceId': serializer.toJson<String>(deviceId),
      'version': serializer.toJson<int>(version),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Note copyWith({
    String? id,
    String? folderId,
    String? title,
    String? preview,
    int? contentLength,
    int? chunkCount,
    bool? isCompressed,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? hlcTimestamp,
    String? deviceId,
    int? version,
    bool? isDeleted,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Note(
    id: id ?? this.id,
    folderId: folderId ?? this.folderId,
    title: title ?? this.title,
    preview: preview ?? this.preview,
    contentLength: contentLength ?? this.contentLength,
    chunkCount: chunkCount ?? this.chunkCount,
    isCompressed: isCompressed ?? this.isCompressed,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
    deviceId: deviceId ?? this.deviceId,
    version: version ?? this.version,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      title: data.title.present ? data.title.value : this.title,
      preview: data.preview.present ? data.preview.value : this.preview,
      contentLength: data.contentLength.present
          ? data.contentLength.value
          : this.contentLength,
      chunkCount: data.chunkCount.present
          ? data.chunkCount.value
          : this.chunkCount,
      isCompressed: data.isCompressed.present
          ? data.isCompressed.value
          : this.isCompressed,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      hlcTimestamp: data.hlcTimestamp.present
          ? data.hlcTimestamp.value
          : this.hlcTimestamp,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      version: data.version.present ? data.version.value : this.version,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('contentLength: $contentLength, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('isCompressed: $isCompressed, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    title,
    preview,
    contentLength,
    chunkCount,
    isCompressed,
    position,
    createdAt,
    updatedAt,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.folderId == this.folderId &&
          other.title == this.title &&
          other.preview == this.preview &&
          other.contentLength == this.contentLength &&
          other.chunkCount == this.chunkCount &&
          other.isCompressed == this.isCompressed &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.hlcTimestamp == this.hlcTimestamp &&
          other.deviceId == this.deviceId &&
          other.version == this.version &&
          other.isDeleted == this.isDeleted &&
          other.deletedAt == this.deletedAt);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String> folderId;
  final Value<String> title;
  final Value<String> preview;
  final Value<int> contentLength;
  final Value<int> chunkCount;
  final Value<bool> isCompressed;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> hlcTimestamp;
  final Value<String> deviceId;
  final Value<int> version;
  final Value<bool> isDeleted;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    this.title = const Value.absent(),
    this.preview = const Value.absent(),
    this.contentLength = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.isCompressed = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.hlcTimestamp = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String folderId,
    required String title,
    this.preview = const Value.absent(),
    this.contentLength = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.isCompressed = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    required String hlcTimestamp,
    required String deviceId,
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       folderId = Value(folderId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlcTimestamp = Value(hlcTimestamp),
       deviceId = Value(deviceId);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? folderId,
    Expression<String>? title,
    Expression<String>? preview,
    Expression<int>? contentLength,
    Expression<int>? chunkCount,
    Expression<bool>? isCompressed,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? hlcTimestamp,
    Expression<String>? deviceId,
    Expression<int>? version,
    Expression<bool>? isDeleted,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderId != null) 'folder_id': folderId,
      if (title != null) 'title': title,
      if (preview != null) 'preview': preview,
      if (contentLength != null) 'content_length': contentLength,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (isCompressed != null) 'is_compressed': isCompressed,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (hlcTimestamp != null) 'hlc_timestamp': hlcTimestamp,
      if (deviceId != null) 'device_id': deviceId,
      if (version != null) 'version': version,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? folderId,
    Value<String>? title,
    Value<String>? preview,
    Value<int>? contentLength,
    Value<int>? chunkCount,
    Value<bool>? isCompressed,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? hlcTimestamp,
    Value<String>? deviceId,
    Value<int>? version,
    Value<bool>? isDeleted,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      contentLength: contentLength ?? this.contentLength,
      chunkCount: chunkCount ?? this.chunkCount,
      isCompressed: isCompressed ?? this.isCompressed,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (contentLength.present) {
      map['content_length'] = Variable<int>(contentLength.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (isCompressed.present) {
      map['is_compressed'] = Variable<bool>(isCompressed.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (hlcTimestamp.present) {
      map['hlc_timestamp'] = Variable<String>(hlcTimestamp.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('contentLength: $contentLength, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('isCompressed: $isCompressed, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContentChunksTable extends ContentChunks
    with TableInfo<$ContentChunksTable, ContentChunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chunkIndexMeta = const VerificationMeta(
    'chunkIndex',
  );
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
    'chunk_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCompressedMeta = const VerificationMeta(
    'isCompressed',
  );
  @override
  late final GeneratedColumn<bool> isCompressed = GeneratedColumn<bool>(
    'is_compressed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_compressed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hlcTimestampMeta = const VerificationMeta(
    'hlcTimestamp',
  );
  @override
  late final GeneratedColumn<String> hlcTimestamp = GeneratedColumn<String>(
    'hlc_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    chunkIndex,
    content,
    isCompressed,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentChunk> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
        _chunkIndexMeta,
        chunkIndex.isAcceptableOrUnknown(data['chunk_index']!, _chunkIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('is_compressed')) {
      context.handle(
        _isCompressedMeta,
        isCompressed.isAcceptableOrUnknown(
          data['is_compressed']!,
          _isCompressedMeta,
        ),
      );
    }
    if (data.containsKey('hlc_timestamp')) {
      context.handle(
        _hlcTimestampMeta,
        hlcTimestamp.isAcceptableOrUnknown(
          data['hlc_timestamp']!,
          _hlcTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hlcTimestampMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentChunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentChunk(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      chunkIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_index'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      isCompressed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_compressed'],
      )!,
      hlcTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc_timestamp'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $ContentChunksTable createAlias(String alias) {
    return $ContentChunksTable(attachedDatabase, alias);
  }
}

class ContentChunk extends DataClass implements Insertable<ContentChunk> {
  final String id;
  final String noteId;
  final int chunkIndex;
  final String content;
  final bool isCompressed;
  final String hlcTimestamp;
  final String deviceId;
  final int version;
  final bool isDeleted;
  const ContentChunk({
    required this.id,
    required this.noteId,
    required this.chunkIndex,
    required this.content,
    required this.isCompressed,
    required this.hlcTimestamp,
    required this.deviceId,
    required this.version,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['content'] = Variable<String>(content);
    map['is_compressed'] = Variable<bool>(isCompressed);
    map['hlc_timestamp'] = Variable<String>(hlcTimestamp);
    map['device_id'] = Variable<String>(deviceId);
    map['version'] = Variable<int>(version);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  ContentChunksCompanion toCompanion(bool nullToAbsent) {
    return ContentChunksCompanion(
      id: Value(id),
      noteId: Value(noteId),
      chunkIndex: Value(chunkIndex),
      content: Value(content),
      isCompressed: Value(isCompressed),
      hlcTimestamp: Value(hlcTimestamp),
      deviceId: Value(deviceId),
      version: Value(version),
      isDeleted: Value(isDeleted),
    );
  }

  factory ContentChunk.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentChunk(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      content: serializer.fromJson<String>(json['content']),
      isCompressed: serializer.fromJson<bool>(json['isCompressed']),
      hlcTimestamp: serializer.fromJson<String>(json['hlcTimestamp']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      version: serializer.fromJson<int>(json['version']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'content': serializer.toJson<String>(content),
      'isCompressed': serializer.toJson<bool>(isCompressed),
      'hlcTimestamp': serializer.toJson<String>(hlcTimestamp),
      'deviceId': serializer.toJson<String>(deviceId),
      'version': serializer.toJson<int>(version),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  ContentChunk copyWith({
    String? id,
    String? noteId,
    int? chunkIndex,
    String? content,
    bool? isCompressed,
    String? hlcTimestamp,
    String? deviceId,
    int? version,
    bool? isDeleted,
  }) => ContentChunk(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    chunkIndex: chunkIndex ?? this.chunkIndex,
    content: content ?? this.content,
    isCompressed: isCompressed ?? this.isCompressed,
    hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
    deviceId: deviceId ?? this.deviceId,
    version: version ?? this.version,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  ContentChunk copyWithCompanion(ContentChunksCompanion data) {
    return ContentChunk(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      chunkIndex: data.chunkIndex.present
          ? data.chunkIndex.value
          : this.chunkIndex,
      content: data.content.present ? data.content.value : this.content,
      isCompressed: data.isCompressed.present
          ? data.isCompressed.value
          : this.isCompressed,
      hlcTimestamp: data.hlcTimestamp.present
          ? data.hlcTimestamp.value
          : this.hlcTimestamp,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      version: data.version.present ? data.version.value : this.version,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentChunk(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('content: $content, ')
          ..write('isCompressed: $isCompressed, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    chunkIndex,
    content,
    isCompressed,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentChunk &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.chunkIndex == this.chunkIndex &&
          other.content == this.content &&
          other.isCompressed == this.isCompressed &&
          other.hlcTimestamp == this.hlcTimestamp &&
          other.deviceId == this.deviceId &&
          other.version == this.version &&
          other.isDeleted == this.isDeleted);
}

class ContentChunksCompanion extends UpdateCompanion<ContentChunk> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<int> chunkIndex;
  final Value<String> content;
  final Value<bool> isCompressed;
  final Value<String> hlcTimestamp;
  final Value<String> deviceId;
  final Value<int> version;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const ContentChunksCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.content = const Value.absent(),
    this.isCompressed = const Value.absent(),
    this.hlcTimestamp = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContentChunksCompanion.insert({
    required String id,
    required String noteId,
    required int chunkIndex,
    required String content,
    this.isCompressed = const Value.absent(),
    required String hlcTimestamp,
    required String deviceId,
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       chunkIndex = Value(chunkIndex),
       content = Value(content),
       hlcTimestamp = Value(hlcTimestamp),
       deviceId = Value(deviceId);
  static Insertable<ContentChunk> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<int>? chunkIndex,
    Expression<String>? content,
    Expression<bool>? isCompressed,
    Expression<String>? hlcTimestamp,
    Expression<String>? deviceId,
    Expression<int>? version,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (content != null) 'content': content,
      if (isCompressed != null) 'is_compressed': isCompressed,
      if (hlcTimestamp != null) 'hlc_timestamp': hlcTimestamp,
      if (deviceId != null) 'device_id': deviceId,
      if (version != null) 'version': version,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContentChunksCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<int>? chunkIndex,
    Value<String>? content,
    Value<bool>? isCompressed,
    Value<String>? hlcTimestamp,
    Value<String>? deviceId,
    Value<int>? version,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return ContentChunksCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      content: content ?? this.content,
      isCompressed: isCompressed ?? this.isCompressed,
      hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (isCompressed.present) {
      map['is_compressed'] = Variable<bool>(isCompressed.value);
    }
    if (hlcTimestamp.present) {
      map['hlc_timestamp'] = Variable<String>(hlcTimestamp.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentChunksCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('content: $content, ')
          ..write('isCompressed: $isCompressed, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataTable extends SyncMetadata
    with TableInfo<$SyncMetadataTable, SyncMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncMetadataTable createAlias(String alias) {
    return $SyncMetadataTable(attachedDatabase, alias);
  }
}

class SyncMetadataData extends DataClass
    implements Insertable<SyncMetadataData> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const SyncMetadataData({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncMetadataData copyWith({
    String? key,
    String? value,
    DateTime? updatedAt,
  }) => SyncMetadataData(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncMetadataData copyWithCompanion(SyncMetadataCompanion data) {
    return SyncMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SyncMetadataCompanion extends UpdateCompanion<SyncMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetadataCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<SyncMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, UserSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  UserSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }
}

class UserSetting extends DataClass implements Insertable<UserSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const UserSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory UserSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UserSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      UserSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  UserSetting copyWithCompanion(UserSettingsCompanion data) {
    return UserSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class UserSettingsCompanion extends UpdateCompanion<UserSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UserSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<UserSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UserSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CountersTable extends Counters
    with TableInfo<$CountersTable, CounterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startValueMeta = const VerificationMeta(
    'startValue',
  );
  @override
  late final GeneratedColumn<int> startValue = GeneratedColumn<int>(
    'start_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<int> step = GeneratedColumn<int>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('global'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    startValue,
    step,
    scope,
    position,
    isPinned,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'counters';
  @override
  VerificationContext validateIntegrity(
    Insertable<CounterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('start_value')) {
      context.handle(
        _startValueMeta,
        startValue.isAcceptableOrUnknown(data['start_value']!, _startValueMeta),
      );
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CounterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CounterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_value'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CountersTable createAlias(String alias) {
    return $CountersTable(attachedDatabase, alias);
  }
}

class CounterRow extends DataClass implements Insertable<CounterRow> {
  final String id;
  final String name;
  final int startValue;
  final int step;
  final String scope;
  final int position;
  final bool isPinned;
  final DateTime createdAt;
  const CounterRow({
    required this.id,
    required this.name,
    required this.startValue,
    required this.step,
    required this.scope,
    required this.position,
    required this.isPinned,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['start_value'] = Variable<int>(startValue);
    map['step'] = Variable<int>(step);
    map['scope'] = Variable<String>(scope);
    map['position'] = Variable<int>(position);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CountersCompanion toCompanion(bool nullToAbsent) {
    return CountersCompanion(
      id: Value(id),
      name: Value(name),
      startValue: Value(startValue),
      step: Value(step),
      scope: Value(scope),
      position: Value(position),
      isPinned: Value(isPinned),
      createdAt: Value(createdAt),
    );
  }

  factory CounterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CounterRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      startValue: serializer.fromJson<int>(json['startValue']),
      step: serializer.fromJson<int>(json['step']),
      scope: serializer.fromJson<String>(json['scope']),
      position: serializer.fromJson<int>(json['position']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'startValue': serializer.toJson<int>(startValue),
      'step': serializer.toJson<int>(step),
      'scope': serializer.toJson<String>(scope),
      'position': serializer.toJson<int>(position),
      'isPinned': serializer.toJson<bool>(isPinned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CounterRow copyWith({
    String? id,
    String? name,
    int? startValue,
    int? step,
    String? scope,
    int? position,
    bool? isPinned,
    DateTime? createdAt,
  }) => CounterRow(
    id: id ?? this.id,
    name: name ?? this.name,
    startValue: startValue ?? this.startValue,
    step: step ?? this.step,
    scope: scope ?? this.scope,
    position: position ?? this.position,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt ?? this.createdAt,
  );
  CounterRow copyWithCompanion(CountersCompanion data) {
    return CounterRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      startValue: data.startValue.present
          ? data.startValue.value
          : this.startValue,
      step: data.step.present ? data.step.value : this.step,
      scope: data.scope.present ? data.scope.value : this.scope,
      position: data.position.present ? data.position.value : this.position,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CounterRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startValue: $startValue, ')
          ..write('step: $step, ')
          ..write('scope: $scope, ')
          ..write('position: $position, ')
          ..write('isPinned: $isPinned, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    startValue,
    step,
    scope,
    position,
    isPinned,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CounterRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.startValue == this.startValue &&
          other.step == this.step &&
          other.scope == this.scope &&
          other.position == this.position &&
          other.isPinned == this.isPinned &&
          other.createdAt == this.createdAt);
}

class CountersCompanion extends UpdateCompanion<CounterRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> startValue;
  final Value<int> step;
  final Value<String> scope;
  final Value<int> position;
  final Value<bool> isPinned;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CountersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.startValue = const Value.absent(),
    this.step = const Value.absent(),
    this.scope = const Value.absent(),
    this.position = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CountersCompanion.insert({
    required String id,
    required String name,
    this.startValue = const Value.absent(),
    this.step = const Value.absent(),
    this.scope = const Value.absent(),
    this.position = const Value.absent(),
    this.isPinned = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<CounterRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? startValue,
    Expression<int>? step,
    Expression<String>? scope,
    Expression<int>? position,
    Expression<bool>? isPinned,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (startValue != null) 'start_value': startValue,
      if (step != null) 'step': step,
      if (scope != null) 'scope': scope,
      if (position != null) 'position': position,
      if (isPinned != null) 'is_pinned': isPinned,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CountersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? startValue,
    Value<int>? step,
    Value<String>? scope,
    Value<int>? position,
    Value<bool>? isPinned,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CountersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      startValue: startValue ?? this.startValue,
      step: step ?? this.step,
      scope: scope ?? this.scope,
      position: position ?? this.position,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startValue.present) {
      map['start_value'] = Variable<int>(startValue.value);
    }
    if (step.present) {
      map['step'] = Variable<int>(step.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CountersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startValue: $startValue, ')
          ..write('step: $step, ')
          ..write('scope: $scope, ')
          ..write('position: $position, ')
          ..write('isPinned: $isPinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CounterValuesTable extends CounterValues
    with TableInfo<$CounterValuesTable, CounterValueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CounterValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _counterIdMeta = const VerificationMeta(
    'counterId',
  );
  @override
  late final GeneratedColumn<String> counterId = GeneratedColumn<String>(
    'counter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    counterId,
    noteId,
    value,
    position,
    isPinned,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'counter_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<CounterValueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('counter_id')) {
      context.handle(
        _counterIdMeta,
        counterId.isAcceptableOrUnknown(data['counter_id']!, _counterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_counterIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {counterId, noteId};
  @override
  CounterValueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CounterValueRow(
      counterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counter_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
    );
  }

  @override
  $CounterValuesTable createAlias(String alias) {
    return $CounterValuesTable(attachedDatabase, alias);
  }
}

class CounterValueRow extends DataClass implements Insertable<CounterValueRow> {
  final String counterId;
  final String noteId;
  final int value;
  final int position;
  final bool isPinned;
  const CounterValueRow({
    required this.counterId,
    required this.noteId,
    required this.value,
    required this.position,
    required this.isPinned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['counter_id'] = Variable<String>(counterId);
    map['note_id'] = Variable<String>(noteId);
    map['value'] = Variable<int>(value);
    map['position'] = Variable<int>(position);
    map['is_pinned'] = Variable<bool>(isPinned);
    return map;
  }

  CounterValuesCompanion toCompanion(bool nullToAbsent) {
    return CounterValuesCompanion(
      counterId: Value(counterId),
      noteId: Value(noteId),
      value: Value(value),
      position: Value(position),
      isPinned: Value(isPinned),
    );
  }

  factory CounterValueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CounterValueRow(
      counterId: serializer.fromJson<String>(json['counterId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      value: serializer.fromJson<int>(json['value']),
      position: serializer.fromJson<int>(json['position']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'counterId': serializer.toJson<String>(counterId),
      'noteId': serializer.toJson<String>(noteId),
      'value': serializer.toJson<int>(value),
      'position': serializer.toJson<int>(position),
      'isPinned': serializer.toJson<bool>(isPinned),
    };
  }

  CounterValueRow copyWith({
    String? counterId,
    String? noteId,
    int? value,
    int? position,
    bool? isPinned,
  }) => CounterValueRow(
    counterId: counterId ?? this.counterId,
    noteId: noteId ?? this.noteId,
    value: value ?? this.value,
    position: position ?? this.position,
    isPinned: isPinned ?? this.isPinned,
  );
  CounterValueRow copyWithCompanion(CounterValuesCompanion data) {
    return CounterValueRow(
      counterId: data.counterId.present ? data.counterId.value : this.counterId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      value: data.value.present ? data.value.value : this.value,
      position: data.position.present ? data.position.value : this.position,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CounterValueRow(')
          ..write('counterId: $counterId, ')
          ..write('noteId: $noteId, ')
          ..write('value: $value, ')
          ..write('position: $position, ')
          ..write('isPinned: $isPinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(counterId, noteId, value, position, isPinned);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CounterValueRow &&
          other.counterId == this.counterId &&
          other.noteId == this.noteId &&
          other.value == this.value &&
          other.position == this.position &&
          other.isPinned == this.isPinned);
}

class CounterValuesCompanion extends UpdateCompanion<CounterValueRow> {
  final Value<String> counterId;
  final Value<String> noteId;
  final Value<int> value;
  final Value<int> position;
  final Value<bool> isPinned;
  final Value<int> rowid;
  const CounterValuesCompanion({
    this.counterId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.value = const Value.absent(),
    this.position = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CounterValuesCompanion.insert({
    required String counterId,
    this.noteId = const Value.absent(),
    required int value,
    this.position = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : counterId = Value(counterId),
       value = Value(value);
  static Insertable<CounterValueRow> custom({
    Expression<String>? counterId,
    Expression<String>? noteId,
    Expression<int>? value,
    Expression<int>? position,
    Expression<bool>? isPinned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (counterId != null) 'counter_id': counterId,
      if (noteId != null) 'note_id': noteId,
      if (value != null) 'value': value,
      if (position != null) 'position': position,
      if (isPinned != null) 'is_pinned': isPinned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CounterValuesCompanion copyWith({
    Value<String>? counterId,
    Value<String>? noteId,
    Value<int>? value,
    Value<int>? position,
    Value<bool>? isPinned,
    Value<int>? rowid,
  }) {
    return CounterValuesCompanion(
      counterId: counterId ?? this.counterId,
      noteId: noteId ?? this.noteId,
      value: value ?? this.value,
      position: position ?? this.position,
      isPinned: isPinned ?? this.isPinned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (counterId.present) {
      map['counter_id'] = Variable<String>(counterId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CounterValuesCompanion(')
          ..write('counterId: $counterId, ')
          ..write('noteId: $noteId, ')
          ..write('value: $value, ')
          ..write('position: $position, ')
          ..write('isPinned: $isPinned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarEventsTable extends CalendarEvents
    with TableInfo<$CalendarEventsTable, CalendarEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allDayMeta = const VerificationMeta('allDay');
  @override
  late final GeneratedColumn<bool> allDay = GeneratedColumn<bool>(
    'all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _iconKeyMeta = const VerificationMeta(
    'iconKey',
  );
  @override
  late final GeneratedColumn<String> iconKey = GeneratedColumn<String>(
    'icon_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ruleKindMeta = const VerificationMeta(
    'ruleKind',
  );
  @override
  late final GeneratedColumn<String> ruleKind = GeneratedColumn<String>(
    'rule_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rulePayloadMeta = const VerificationMeta(
    'rulePayload',
  );
  @override
  late final GeneratedColumn<String> rulePayload = GeneratedColumn<String>(
    'rule_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMinutesMeta = const VerificationMeta(
    'durationMinutes',
  );
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
    'duration_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tintIconMeta = const VerificationMeta(
    'tintIcon',
  );
  @override
  late final GeneratedColumn<bool> tintIcon = GeneratedColumn<bool>(
    'tint_icon',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tint_icon" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3),
  );
  static const VerificationMeta _retroactiveMeta = const VerificationMeta(
    'retroactive',
  );
  @override
  late final GeneratedColumn<bool> retroactive = GeneratedColumn<bool>(
    'retroactive',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("retroactive" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _countOccurrencesMeta = const VerificationMeta(
    'countOccurrences',
  );
  @override
  late final GeneratedColumn<bool> countOccurrences = GeneratedColumn<bool>(
    'count_occurrences',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("count_occurrences" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _countStyleMeta = const VerificationMeta(
    'countStyle',
  );
  @override
  late final GeneratedColumn<String> countStyle = GeneratedColumn<String>(
    'count_style',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('numbered'),
  );
  static const VerificationMeta _tracksPresenceMeta = const VerificationMeta(
    'tracksPresence',
  );
  @override
  late final GeneratedColumn<bool> tracksPresence = GeneratedColumn<bool>(
    'tracks_presence',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tracks_presence" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    category,
    startDate,
    allDay,
    iconKey,
    ruleKind,
    rulePayload,
    endDate,
    startMinute,
    durationMinutes,
    description,
    noteId,
    colorValue,
    tintIcon,
    priority,
    retroactive,
    countOccurrences,
    countStyle,
    tracksPresence,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('all_day')) {
      context.handle(
        _allDayMeta,
        allDay.isAcceptableOrUnknown(data['all_day']!, _allDayMeta),
      );
    }
    if (data.containsKey('icon_key')) {
      context.handle(
        _iconKeyMeta,
        iconKey.isAcceptableOrUnknown(data['icon_key']!, _iconKeyMeta),
      );
    }
    if (data.containsKey('rule_kind')) {
      context.handle(
        _ruleKindMeta,
        ruleKind.isAcceptableOrUnknown(data['rule_kind']!, _ruleKindMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleKindMeta);
    }
    if (data.containsKey('rule_payload')) {
      context.handle(
        _rulePayloadMeta,
        rulePayload.isAcceptableOrUnknown(
          data['rule_payload']!,
          _rulePayloadMeta,
        ),
      );
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
        _durationMinutesMeta,
        durationMinutes.isAcceptableOrUnknown(
          data['duration_minutes']!,
          _durationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('tint_icon')) {
      context.handle(
        _tintIconMeta,
        tintIcon.isAcceptableOrUnknown(data['tint_icon']!, _tintIconMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('retroactive')) {
      context.handle(
        _retroactiveMeta,
        retroactive.isAcceptableOrUnknown(
          data['retroactive']!,
          _retroactiveMeta,
        ),
      );
    }
    if (data.containsKey('count_occurrences')) {
      context.handle(
        _countOccurrencesMeta,
        countOccurrences.isAcceptableOrUnknown(
          data['count_occurrences']!,
          _countOccurrencesMeta,
        ),
      );
    }
    if (data.containsKey('count_style')) {
      context.handle(
        _countStyleMeta,
        countStyle.isAcceptableOrUnknown(data['count_style']!, _countStyleMeta),
      );
    }
    if (data.containsKey('tracks_presence')) {
      context.handle(
        _tracksPresenceMeta,
        tracksPresence.isAcceptableOrUnknown(
          data['tracks_presence']!,
          _tracksPresenceMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      )!,
      allDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_day'],
      )!,
      iconKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_key'],
      ),
      ruleKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_kind'],
      )!,
      rulePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_payload'],
      ),
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      ),
      durationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_minutes'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      ),
      tintIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tint_icon'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      retroactive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}retroactive'],
      )!,
      countOccurrences: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}count_occurrences'],
      )!,
      countStyle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}count_style'],
      )!,
      tracksPresence: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tracks_presence'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CalendarEventsTable createAlias(String alias) {
    return $CalendarEventsTable(attachedDatabase, alias);
  }
}

class CalendarEventRow extends DataClass
    implements Insertable<CalendarEventRow> {
  final String id;
  final String title;
  final String category;
  final DateTime startDate;
  final bool allDay;
  final String? iconKey;
  final String ruleKind;
  final String? rulePayload;
  final DateTime? endDate;
  final int? startMinute;
  final int? durationMinutes;
  final String? description;
  final String? noteId;
  final int? colorValue;
  final bool tintIcon;
  final int priority;
  final bool retroactive;
  final bool countOccurrences;
  final String countStyle;
  final bool tracksPresence;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CalendarEventRow({
    required this.id,
    required this.title,
    required this.category,
    required this.startDate,
    required this.allDay,
    this.iconKey,
    required this.ruleKind,
    this.rulePayload,
    this.endDate,
    this.startMinute,
    this.durationMinutes,
    this.description,
    this.noteId,
    this.colorValue,
    required this.tintIcon,
    required this.priority,
    required this.retroactive,
    required this.countOccurrences,
    required this.countStyle,
    required this.tracksPresence,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['category'] = Variable<String>(category);
    map['start_date'] = Variable<DateTime>(startDate);
    map['all_day'] = Variable<bool>(allDay);
    if (!nullToAbsent || iconKey != null) {
      map['icon_key'] = Variable<String>(iconKey);
    }
    map['rule_kind'] = Variable<String>(ruleKind);
    if (!nullToAbsent || rulePayload != null) {
      map['rule_payload'] = Variable<String>(rulePayload);
    }
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    if (!nullToAbsent || startMinute != null) {
      map['start_minute'] = Variable<int>(startMinute);
    }
    if (!nullToAbsent || durationMinutes != null) {
      map['duration_minutes'] = Variable<int>(durationMinutes);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || noteId != null) {
      map['note_id'] = Variable<String>(noteId);
    }
    if (!nullToAbsent || colorValue != null) {
      map['color_value'] = Variable<int>(colorValue);
    }
    map['tint_icon'] = Variable<bool>(tintIcon);
    map['priority'] = Variable<int>(priority);
    map['retroactive'] = Variable<bool>(retroactive);
    map['count_occurrences'] = Variable<bool>(countOccurrences);
    map['count_style'] = Variable<String>(countStyle);
    map['tracks_presence'] = Variable<bool>(tracksPresence);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CalendarEventsCompanion toCompanion(bool nullToAbsent) {
    return CalendarEventsCompanion(
      id: Value(id),
      title: Value(title),
      category: Value(category),
      startDate: Value(startDate),
      allDay: Value(allDay),
      iconKey: iconKey == null && nullToAbsent
          ? const Value.absent()
          : Value(iconKey),
      ruleKind: Value(ruleKind),
      rulePayload: rulePayload == null && nullToAbsent
          ? const Value.absent()
          : Value(rulePayload),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      startMinute: startMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(startMinute),
      durationMinutes: durationMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMinutes),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      noteId: noteId == null && nullToAbsent
          ? const Value.absent()
          : Value(noteId),
      colorValue: colorValue == null && nullToAbsent
          ? const Value.absent()
          : Value(colorValue),
      tintIcon: Value(tintIcon),
      priority: Value(priority),
      retroactive: Value(retroactive),
      countOccurrences: Value(countOccurrences),
      countStyle: Value(countStyle),
      tracksPresence: Value(tracksPresence),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CalendarEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarEventRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      category: serializer.fromJson<String>(json['category']),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      allDay: serializer.fromJson<bool>(json['allDay']),
      iconKey: serializer.fromJson<String?>(json['iconKey']),
      ruleKind: serializer.fromJson<String>(json['ruleKind']),
      rulePayload: serializer.fromJson<String?>(json['rulePayload']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      startMinute: serializer.fromJson<int?>(json['startMinute']),
      durationMinutes: serializer.fromJson<int?>(json['durationMinutes']),
      description: serializer.fromJson<String?>(json['description']),
      noteId: serializer.fromJson<String?>(json['noteId']),
      colorValue: serializer.fromJson<int?>(json['colorValue']),
      tintIcon: serializer.fromJson<bool>(json['tintIcon']),
      priority: serializer.fromJson<int>(json['priority']),
      retroactive: serializer.fromJson<bool>(json['retroactive']),
      countOccurrences: serializer.fromJson<bool>(json['countOccurrences']),
      countStyle: serializer.fromJson<String>(json['countStyle']),
      tracksPresence: serializer.fromJson<bool>(json['tracksPresence']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'category': serializer.toJson<String>(category),
      'startDate': serializer.toJson<DateTime>(startDate),
      'allDay': serializer.toJson<bool>(allDay),
      'iconKey': serializer.toJson<String?>(iconKey),
      'ruleKind': serializer.toJson<String>(ruleKind),
      'rulePayload': serializer.toJson<String?>(rulePayload),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'startMinute': serializer.toJson<int?>(startMinute),
      'durationMinutes': serializer.toJson<int?>(durationMinutes),
      'description': serializer.toJson<String?>(description),
      'noteId': serializer.toJson<String?>(noteId),
      'colorValue': serializer.toJson<int?>(colorValue),
      'tintIcon': serializer.toJson<bool>(tintIcon),
      'priority': serializer.toJson<int>(priority),
      'retroactive': serializer.toJson<bool>(retroactive),
      'countOccurrences': serializer.toJson<bool>(countOccurrences),
      'countStyle': serializer.toJson<String>(countStyle),
      'tracksPresence': serializer.toJson<bool>(tracksPresence),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CalendarEventRow copyWith({
    String? id,
    String? title,
    String? category,
    DateTime? startDate,
    bool? allDay,
    Value<String?> iconKey = const Value.absent(),
    String? ruleKind,
    Value<String?> rulePayload = const Value.absent(),
    Value<DateTime?> endDate = const Value.absent(),
    Value<int?> startMinute = const Value.absent(),
    Value<int?> durationMinutes = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> noteId = const Value.absent(),
    Value<int?> colorValue = const Value.absent(),
    bool? tintIcon,
    int? priority,
    bool? retroactive,
    bool? countOccurrences,
    String? countStyle,
    bool? tracksPresence,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CalendarEventRow(
    id: id ?? this.id,
    title: title ?? this.title,
    category: category ?? this.category,
    startDate: startDate ?? this.startDate,
    allDay: allDay ?? this.allDay,
    iconKey: iconKey.present ? iconKey.value : this.iconKey,
    ruleKind: ruleKind ?? this.ruleKind,
    rulePayload: rulePayload.present ? rulePayload.value : this.rulePayload,
    endDate: endDate.present ? endDate.value : this.endDate,
    startMinute: startMinute.present ? startMinute.value : this.startMinute,
    durationMinutes: durationMinutes.present
        ? durationMinutes.value
        : this.durationMinutes,
    description: description.present ? description.value : this.description,
    noteId: noteId.present ? noteId.value : this.noteId,
    colorValue: colorValue.present ? colorValue.value : this.colorValue,
    tintIcon: tintIcon ?? this.tintIcon,
    priority: priority ?? this.priority,
    retroactive: retroactive ?? this.retroactive,
    countOccurrences: countOccurrences ?? this.countOccurrences,
    countStyle: countStyle ?? this.countStyle,
    tracksPresence: tracksPresence ?? this.tracksPresence,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CalendarEventRow copyWithCompanion(CalendarEventsCompanion data) {
    return CalendarEventRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      category: data.category.present ? data.category.value : this.category,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      allDay: data.allDay.present ? data.allDay.value : this.allDay,
      iconKey: data.iconKey.present ? data.iconKey.value : this.iconKey,
      ruleKind: data.ruleKind.present ? data.ruleKind.value : this.ruleKind,
      rulePayload: data.rulePayload.present
          ? data.rulePayload.value
          : this.rulePayload,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      description: data.description.present
          ? data.description.value
          : this.description,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      tintIcon: data.tintIcon.present ? data.tintIcon.value : this.tintIcon,
      priority: data.priority.present ? data.priority.value : this.priority,
      retroactive: data.retroactive.present
          ? data.retroactive.value
          : this.retroactive,
      countOccurrences: data.countOccurrences.present
          ? data.countOccurrences.value
          : this.countOccurrences,
      countStyle: data.countStyle.present
          ? data.countStyle.value
          : this.countStyle,
      tracksPresence: data.tracksPresence.present
          ? data.tracksPresence.value
          : this.tracksPresence,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEventRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('category: $category, ')
          ..write('startDate: $startDate, ')
          ..write('allDay: $allDay, ')
          ..write('iconKey: $iconKey, ')
          ..write('ruleKind: $ruleKind, ')
          ..write('rulePayload: $rulePayload, ')
          ..write('endDate: $endDate, ')
          ..write('startMinute: $startMinute, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('description: $description, ')
          ..write('noteId: $noteId, ')
          ..write('colorValue: $colorValue, ')
          ..write('tintIcon: $tintIcon, ')
          ..write('priority: $priority, ')
          ..write('retroactive: $retroactive, ')
          ..write('countOccurrences: $countOccurrences, ')
          ..write('countStyle: $countStyle, ')
          ..write('tracksPresence: $tracksPresence, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    category,
    startDate,
    allDay,
    iconKey,
    ruleKind,
    rulePayload,
    endDate,
    startMinute,
    durationMinutes,
    description,
    noteId,
    colorValue,
    tintIcon,
    priority,
    retroactive,
    countOccurrences,
    countStyle,
    tracksPresence,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarEventRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.category == this.category &&
          other.startDate == this.startDate &&
          other.allDay == this.allDay &&
          other.iconKey == this.iconKey &&
          other.ruleKind == this.ruleKind &&
          other.rulePayload == this.rulePayload &&
          other.endDate == this.endDate &&
          other.startMinute == this.startMinute &&
          other.durationMinutes == this.durationMinutes &&
          other.description == this.description &&
          other.noteId == this.noteId &&
          other.colorValue == this.colorValue &&
          other.tintIcon == this.tintIcon &&
          other.priority == this.priority &&
          other.retroactive == this.retroactive &&
          other.countOccurrences == this.countOccurrences &&
          other.countStyle == this.countStyle &&
          other.tracksPresence == this.tracksPresence &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CalendarEventsCompanion extends UpdateCompanion<CalendarEventRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> category;
  final Value<DateTime> startDate;
  final Value<bool> allDay;
  final Value<String?> iconKey;
  final Value<String> ruleKind;
  final Value<String?> rulePayload;
  final Value<DateTime?> endDate;
  final Value<int?> startMinute;
  final Value<int?> durationMinutes;
  final Value<String?> description;
  final Value<String?> noteId;
  final Value<int?> colorValue;
  final Value<bool> tintIcon;
  final Value<int> priority;
  final Value<bool> retroactive;
  final Value<bool> countOccurrences;
  final Value<String> countStyle;
  final Value<bool> tracksPresence;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CalendarEventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.category = const Value.absent(),
    this.startDate = const Value.absent(),
    this.allDay = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.ruleKind = const Value.absent(),
    this.rulePayload = const Value.absent(),
    this.endDate = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.description = const Value.absent(),
    this.noteId = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.tintIcon = const Value.absent(),
    this.priority = const Value.absent(),
    this.retroactive = const Value.absent(),
    this.countOccurrences = const Value.absent(),
    this.countStyle = const Value.absent(),
    this.tracksPresence = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarEventsCompanion.insert({
    required String id,
    required String title,
    required String category,
    required DateTime startDate,
    this.allDay = const Value.absent(),
    this.iconKey = const Value.absent(),
    required String ruleKind,
    this.rulePayload = const Value.absent(),
    this.endDate = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.description = const Value.absent(),
    this.noteId = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.tintIcon = const Value.absent(),
    this.priority = const Value.absent(),
    this.retroactive = const Value.absent(),
    this.countOccurrences = const Value.absent(),
    this.countStyle = const Value.absent(),
    this.tracksPresence = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       category = Value(category),
       startDate = Value(startDate),
       ruleKind = Value(ruleKind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CalendarEventRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? category,
    Expression<DateTime>? startDate,
    Expression<bool>? allDay,
    Expression<String>? iconKey,
    Expression<String>? ruleKind,
    Expression<String>? rulePayload,
    Expression<DateTime>? endDate,
    Expression<int>? startMinute,
    Expression<int>? durationMinutes,
    Expression<String>? description,
    Expression<String>? noteId,
    Expression<int>? colorValue,
    Expression<bool>? tintIcon,
    Expression<int>? priority,
    Expression<bool>? retroactive,
    Expression<bool>? countOccurrences,
    Expression<String>? countStyle,
    Expression<bool>? tracksPresence,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (category != null) 'category': category,
      if (startDate != null) 'start_date': startDate,
      if (allDay != null) 'all_day': allDay,
      if (iconKey != null) 'icon_key': iconKey,
      if (ruleKind != null) 'rule_kind': ruleKind,
      if (rulePayload != null) 'rule_payload': rulePayload,
      if (endDate != null) 'end_date': endDate,
      if (startMinute != null) 'start_minute': startMinute,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (description != null) 'description': description,
      if (noteId != null) 'note_id': noteId,
      if (colorValue != null) 'color_value': colorValue,
      if (tintIcon != null) 'tint_icon': tintIcon,
      if (priority != null) 'priority': priority,
      if (retroactive != null) 'retroactive': retroactive,
      if (countOccurrences != null) 'count_occurrences': countOccurrences,
      if (countStyle != null) 'count_style': countStyle,
      if (tracksPresence != null) 'tracks_presence': tracksPresence,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? category,
    Value<DateTime>? startDate,
    Value<bool>? allDay,
    Value<String?>? iconKey,
    Value<String>? ruleKind,
    Value<String?>? rulePayload,
    Value<DateTime?>? endDate,
    Value<int?>? startMinute,
    Value<int?>? durationMinutes,
    Value<String?>? description,
    Value<String?>? noteId,
    Value<int?>? colorValue,
    Value<bool>? tintIcon,
    Value<int>? priority,
    Value<bool>? retroactive,
    Value<bool>? countOccurrences,
    Value<String>? countStyle,
    Value<bool>? tracksPresence,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CalendarEventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      allDay: allDay ?? this.allDay,
      iconKey: iconKey ?? this.iconKey,
      ruleKind: ruleKind ?? this.ruleKind,
      rulePayload: rulePayload ?? this.rulePayload,
      endDate: endDate ?? this.endDate,
      startMinute: startMinute ?? this.startMinute,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      description: description ?? this.description,
      noteId: noteId ?? this.noteId,
      colorValue: colorValue ?? this.colorValue,
      tintIcon: tintIcon ?? this.tintIcon,
      priority: priority ?? this.priority,
      retroactive: retroactive ?? this.retroactive,
      countOccurrences: countOccurrences ?? this.countOccurrences,
      countStyle: countStyle ?? this.countStyle,
      tracksPresence: tracksPresence ?? this.tracksPresence,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (allDay.present) {
      map['all_day'] = Variable<bool>(allDay.value);
    }
    if (iconKey.present) {
      map['icon_key'] = Variable<String>(iconKey.value);
    }
    if (ruleKind.present) {
      map['rule_kind'] = Variable<String>(ruleKind.value);
    }
    if (rulePayload.present) {
      map['rule_payload'] = Variable<String>(rulePayload.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (tintIcon.present) {
      map['tint_icon'] = Variable<bool>(tintIcon.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (retroactive.present) {
      map['retroactive'] = Variable<bool>(retroactive.value);
    }
    if (countOccurrences.present) {
      map['count_occurrences'] = Variable<bool>(countOccurrences.value);
    }
    if (countStyle.present) {
      map['count_style'] = Variable<String>(countStyle.value);
    }
    if (tracksPresence.present) {
      map['tracks_presence'] = Variable<bool>(tracksPresence.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('category: $category, ')
          ..write('startDate: $startDate, ')
          ..write('allDay: $allDay, ')
          ..write('iconKey: $iconKey, ')
          ..write('ruleKind: $ruleKind, ')
          ..write('rulePayload: $rulePayload, ')
          ..write('endDate: $endDate, ')
          ..write('startMinute: $startMinute, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('description: $description, ')
          ..write('noteId: $noteId, ')
          ..write('colorValue: $colorValue, ')
          ..write('tintIcon: $tintIcon, ')
          ..write('priority: $priority, ')
          ..write('retroactive: $retroactive, ')
          ..write('countOccurrences: $countOccurrences, ')
          ..write('countStyle: $countStyle, ')
          ..write('tracksPresence: $tracksPresence, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PublicHolidaysTableTable extends PublicHolidaysTable
    with TableInfo<$PublicHolidaysTableTable, PublicHolidayRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PublicHolidaysTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  @override
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileMeta = const VerificationMeta(
    'profile',
  );
  @override
  late final GeneratedColumn<String> profile = GeneratedColumn<String>(
    'profile',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('generic'),
  );
  static const VerificationMeta _customLabelMeta = const VerificationMeta(
    'customLabel',
  );
  @override
  late final GeneratedColumn<String> customLabel = GeneratedColumn<String>(
    'custom_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suppressedMeta = const VerificationMeta(
    'suppressed',
  );
  @override
  late final GeneratedColumn<bool> suppressed = GeneratedColumn<bool>(
    'suppressed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("suppressed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    nameKey,
    profile,
    customLabel,
    suppressed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'public_holidays';
  @override
  VerificationContext validateIntegrity(
    Insertable<PublicHolidayRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKeyMeta);
    }
    if (data.containsKey('profile')) {
      context.handle(
        _profileMeta,
        profile.isAcceptableOrUnknown(data['profile']!, _profileMeta),
      );
    }
    if (data.containsKey('custom_label')) {
      context.handle(
        _customLabelMeta,
        customLabel.isAcceptableOrUnknown(
          data['custom_label']!,
          _customLabelMeta,
        ),
      );
    }
    if (data.containsKey('suppressed')) {
      context.handle(
        _suppressedMeta,
        suppressed.isAcceptableOrUnknown(data['suppressed']!, _suppressedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date, nameKey};
  @override
  PublicHolidayRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PublicHolidayRow(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      )!,
      profile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile'],
      )!,
      customLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_label'],
      ),
      suppressed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}suppressed'],
      )!,
    );
  }

  @override
  $PublicHolidaysTableTable createAlias(String alias) {
    return $PublicHolidaysTableTable(attachedDatabase, alias);
  }
}

class PublicHolidayRow extends DataClass
    implements Insertable<PublicHolidayRow> {
  /// UTC date-only (year, month, day).
  final DateTime date;
  final String nameKey;

  /// Owning `HolidayProfile.name` for built-in rows, or the sentinel
  /// `custom` for user-added rows. Defaulted in SQL so legacy rows from
  /// schema versions ≤ 12 (which had no profile concept) cleanly back-fill
  /// to the historical Catholic-leaning seed set.
  final String profile;
  final String? customLabel;

  /// User-suppressed for this specific dated row. Built-in rows are kept
  /// (not deleted) when suppressed, precisely so the seeder's
  /// insert-if-missing pass never resurrects them on the next app start
  /// or after a backup restore; `PublicHolidayService._load()` skips
  /// suppressed rows when building the lookup cache. Custom rows are
  /// still hard-deleted on removal since there is no re-seed to defend
  /// against. Defaults to `false` so existing rows are unaffected.
  final bool suppressed;
  const PublicHolidayRow({
    required this.date,
    required this.nameKey,
    required this.profile,
    this.customLabel,
    required this.suppressed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<DateTime>(date);
    map['name_key'] = Variable<String>(nameKey);
    map['profile'] = Variable<String>(profile);
    if (!nullToAbsent || customLabel != null) {
      map['custom_label'] = Variable<String>(customLabel);
    }
    map['suppressed'] = Variable<bool>(suppressed);
    return map;
  }

  PublicHolidaysTableCompanion toCompanion(bool nullToAbsent) {
    return PublicHolidaysTableCompanion(
      date: Value(date),
      nameKey: Value(nameKey),
      profile: Value(profile),
      customLabel: customLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(customLabel),
      suppressed: Value(suppressed),
    );
  }

  factory PublicHolidayRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PublicHolidayRow(
      date: serializer.fromJson<DateTime>(json['date']),
      nameKey: serializer.fromJson<String>(json['nameKey']),
      profile: serializer.fromJson<String>(json['profile']),
      customLabel: serializer.fromJson<String?>(json['customLabel']),
      suppressed: serializer.fromJson<bool>(json['suppressed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<DateTime>(date),
      'nameKey': serializer.toJson<String>(nameKey),
      'profile': serializer.toJson<String>(profile),
      'customLabel': serializer.toJson<String?>(customLabel),
      'suppressed': serializer.toJson<bool>(suppressed),
    };
  }

  PublicHolidayRow copyWith({
    DateTime? date,
    String? nameKey,
    String? profile,
    Value<String?> customLabel = const Value.absent(),
    bool? suppressed,
  }) => PublicHolidayRow(
    date: date ?? this.date,
    nameKey: nameKey ?? this.nameKey,
    profile: profile ?? this.profile,
    customLabel: customLabel.present ? customLabel.value : this.customLabel,
    suppressed: suppressed ?? this.suppressed,
  );
  PublicHolidayRow copyWithCompanion(PublicHolidaysTableCompanion data) {
    return PublicHolidayRow(
      date: data.date.present ? data.date.value : this.date,
      nameKey: data.nameKey.present ? data.nameKey.value : this.nameKey,
      profile: data.profile.present ? data.profile.value : this.profile,
      customLabel: data.customLabel.present
          ? data.customLabel.value
          : this.customLabel,
      suppressed: data.suppressed.present
          ? data.suppressed.value
          : this.suppressed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PublicHolidayRow(')
          ..write('date: $date, ')
          ..write('nameKey: $nameKey, ')
          ..write('profile: $profile, ')
          ..write('customLabel: $customLabel, ')
          ..write('suppressed: $suppressed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(date, nameKey, profile, customLabel, suppressed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PublicHolidayRow &&
          other.date == this.date &&
          other.nameKey == this.nameKey &&
          other.profile == this.profile &&
          other.customLabel == this.customLabel &&
          other.suppressed == this.suppressed);
}

class PublicHolidaysTableCompanion extends UpdateCompanion<PublicHolidayRow> {
  final Value<DateTime> date;
  final Value<String> nameKey;
  final Value<String> profile;
  final Value<String?> customLabel;
  final Value<bool> suppressed;
  final Value<int> rowid;
  const PublicHolidaysTableCompanion({
    this.date = const Value.absent(),
    this.nameKey = const Value.absent(),
    this.profile = const Value.absent(),
    this.customLabel = const Value.absent(),
    this.suppressed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PublicHolidaysTableCompanion.insert({
    required DateTime date,
    required String nameKey,
    this.profile = const Value.absent(),
    this.customLabel = const Value.absent(),
    this.suppressed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       nameKey = Value(nameKey);
  static Insertable<PublicHolidayRow> custom({
    Expression<DateTime>? date,
    Expression<String>? nameKey,
    Expression<String>? profile,
    Expression<String>? customLabel,
    Expression<bool>? suppressed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (nameKey != null) 'name_key': nameKey,
      if (profile != null) 'profile': profile,
      if (customLabel != null) 'custom_label': customLabel,
      if (suppressed != null) 'suppressed': suppressed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PublicHolidaysTableCompanion copyWith({
    Value<DateTime>? date,
    Value<String>? nameKey,
    Value<String>? profile,
    Value<String?>? customLabel,
    Value<bool>? suppressed,
    Value<int>? rowid,
  }) {
    return PublicHolidaysTableCompanion(
      date: date ?? this.date,
      nameKey: nameKey ?? this.nameKey,
      profile: profile ?? this.profile,
      customLabel: customLabel ?? this.customLabel,
      suppressed: suppressed ?? this.suppressed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (nameKey.present) {
      map['name_key'] = Variable<String>(nameKey.value);
    }
    if (profile.present) {
      map['profile'] = Variable<String>(profile.value);
    }
    if (customLabel.present) {
      map['custom_label'] = Variable<String>(customLabel.value);
    }
    if (suppressed.present) {
      map['suppressed'] = Variable<bool>(suppressed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PublicHolidaysTableCompanion(')
          ..write('date: $date, ')
          ..write('nameKey: $nameKey, ')
          ..write('profile: $profile, ')
          ..write('customLabel: $customLabel, ')
          ..write('suppressed: $suppressed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarCategoriesTable extends CalendarCategories
    with TableInfo<$CalendarCategoriesTable, CalendarCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconKeyMeta = const VerificationMeta(
    'iconKey',
  );
  @override
  late final GeneratedColumn<String> iconKey = GeneratedColumn<String>(
    'icon_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isBuiltInMeta = const VerificationMeta(
    'isBuiltIn',
  );
  @override
  late final GeneratedColumn<bool> isBuiltIn = GeneratedColumn<bool>(
    'is_built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_built_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    colorValue,
    iconKey,
    sortOrder,
    isBuiltIn,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('icon_key')) {
      context.handle(
        _iconKeyMeta,
        iconKey.isAcceptableOrUnknown(data['icon_key']!, _iconKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_iconKeyMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_built_in')) {
      context.handle(
        _isBuiltInMeta,
        isBuiltIn.isAcceptableOrUnknown(data['is_built_in']!, _isBuiltInMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarCategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      iconKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_key'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isBuiltIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_built_in'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CalendarCategoriesTable createAlias(String alias) {
    return $CalendarCategoriesTable(attachedDatabase, alias);
  }
}

class CalendarCategoryRow extends DataClass
    implements Insertable<CalendarCategoryRow> {
  final String id;
  final String name;

  /// 32-bit ARGB color value.
  final int colorValue;

  /// Key into the `CalendarIcons` palette.
  final String iconKey;
  final int sortOrder;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CalendarCategoryRow({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.sortOrder,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['icon_key'] = Variable<String>(iconKey);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_built_in'] = Variable<bool>(isBuiltIn);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CalendarCategoriesCompanion toCompanion(bool nullToAbsent) {
    return CalendarCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
      iconKey: Value(iconKey),
      sortOrder: Value(sortOrder),
      isBuiltIn: Value(isBuiltIn),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CalendarCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarCategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      iconKey: serializer.fromJson<String>(json['iconKey']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isBuiltIn: serializer.fromJson<bool>(json['isBuiltIn']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'iconKey': serializer.toJson<String>(iconKey),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isBuiltIn': serializer.toJson<bool>(isBuiltIn),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CalendarCategoryRow copyWith({
    String? id,
    String? name,
    int? colorValue,
    String? iconKey,
    int? sortOrder,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CalendarCategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    iconKey: iconKey ?? this.iconKey,
    sortOrder: sortOrder ?? this.sortOrder,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CalendarCategoryRow copyWithCompanion(CalendarCategoriesCompanion data) {
    return CalendarCategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      iconKey: data.iconKey.present ? data.iconKey.value : this.iconKey,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isBuiltIn: data.isBuiltIn.present ? data.isBuiltIn.value : this.isBuiltIn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarCategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('iconKey: $iconKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorValue,
    iconKey,
    sortOrder,
    isBuiltIn,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarCategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.iconKey == this.iconKey &&
          other.sortOrder == this.sortOrder &&
          other.isBuiltIn == this.isBuiltIn &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CalendarCategoriesCompanion extends UpdateCompanion<CalendarCategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<String> iconKey;
  final Value<int> sortOrder;
  final Value<bool> isBuiltIn;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CalendarCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarCategoriesCompanion.insert({
    required String id,
    required String name,
    required int colorValue,
    required String iconKey,
    this.sortOrder = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       colorValue = Value(colorValue),
       iconKey = Value(iconKey),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CalendarCategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<String>? iconKey,
    Expression<int>? sortOrder,
    Expression<bool>? isBuiltIn,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (iconKey != null) 'icon_key': iconKey,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isBuiltIn != null) 'is_built_in': isBuiltIn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? colorValue,
    Value<String>? iconKey,
    Value<int>? sortOrder,
    Value<bool>? isBuiltIn,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CalendarCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (iconKey.present) {
      map['icon_key'] = Variable<String>(iconKey.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isBuiltIn.present) {
      map['is_built_in'] = Variable<bool>(isBuiltIn.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('iconKey: $iconKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventOccurrenceDescriptionsTable extends EventOccurrenceDescriptions
    with TableInfo<$EventOccurrenceDescriptionsTable, EventOccurrenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventOccurrenceDescriptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<DateTime> day = GeneratedColumn<DateTime>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    day,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_event_occurrences';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventOccurrenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId, day};
  @override
  EventOccurrenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventOccurrenceRow(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}day'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EventOccurrenceDescriptionsTable createAlias(String alias) {
    return $EventOccurrenceDescriptionsTable(attachedDatabase, alias);
  }
}

class EventOccurrenceRow extends DataClass
    implements Insertable<EventOccurrenceRow> {
  final String eventId;

  /// UTC date-only (year, month, day).
  final DateTime day;

  /// Materialized markdown source for this one occurrence. Non-nullable: the
  /// row's existence is the override, and an empty string is a meaningful
  /// value (see the class doc).
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const EventOccurrenceRow({
    required this.eventId,
    required this.day,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['day'] = Variable<DateTime>(day);
    map['description'] = Variable<String>(description);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EventOccurrenceDescriptionsCompanion toCompanion(bool nullToAbsent) {
    return EventOccurrenceDescriptionsCompanion(
      eventId: Value(eventId),
      day: Value(day),
      description: Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory EventOccurrenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventOccurrenceRow(
      eventId: serializer.fromJson<String>(json['eventId']),
      day: serializer.fromJson<DateTime>(json['day']),
      description: serializer.fromJson<String>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'day': serializer.toJson<DateTime>(day),
      'description': serializer.toJson<String>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EventOccurrenceRow copyWith({
    String? eventId,
    DateTime? day,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => EventOccurrenceRow(
    eventId: eventId ?? this.eventId,
    day: day ?? this.day,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EventOccurrenceRow copyWithCompanion(
    EventOccurrenceDescriptionsCompanion data,
  ) {
    return EventOccurrenceRow(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      day: data.day.present ? data.day.value : this.day,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventOccurrenceRow(')
          ..write('eventId: $eventId, ')
          ..write('day: $day, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(eventId, day, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventOccurrenceRow &&
          other.eventId == this.eventId &&
          other.day == this.day &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EventOccurrenceDescriptionsCompanion
    extends UpdateCompanion<EventOccurrenceRow> {
  final Value<String> eventId;
  final Value<DateTime> day;
  final Value<String> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EventOccurrenceDescriptionsCompanion({
    this.eventId = const Value.absent(),
    this.day = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventOccurrenceDescriptionsCompanion.insert({
    required String eventId,
    required DateTime day,
    required String description,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       day = Value(day),
       description = Value(description),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<EventOccurrenceRow> custom({
    Expression<String>? eventId,
    Expression<DateTime>? day,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (day != null) 'day': day,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventOccurrenceDescriptionsCompanion copyWith({
    Value<String>? eventId,
    Value<DateTime>? day,
    Value<String>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EventOccurrenceDescriptionsCompanion(
      eventId: eventId ?? this.eventId,
      day: day ?? this.day,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (day.present) {
      map['day'] = Variable<DateTime>(day.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventOccurrenceDescriptionsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('day: $day, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventAbsencesTable extends EventAbsences
    with TableInfo<$EventAbsencesTable, EventAbsenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventAbsencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<DateTime> day = GeneratedColumn<DateTime>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcTimestampMeta = const VerificationMeta(
    'hlcTimestamp',
  );
  @override
  late final GeneratedColumn<String> hlcTimestamp = GeneratedColumn<String>(
    'hlc_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    day,
    createdAt,
    updatedAt,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_event_absences';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventAbsenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('hlc_timestamp')) {
      context.handle(
        _hlcTimestampMeta,
        hlcTimestamp.isAcceptableOrUnknown(
          data['hlc_timestamp']!,
          _hlcTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hlcTimestampMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId, day};
  @override
  EventAbsenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventAbsenceRow(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}day'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      hlcTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc_timestamp'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $EventAbsencesTable createAlias(String alias) {
    return $EventAbsencesTable(attachedDatabase, alias);
  }
}

class EventAbsenceRow extends DataClass implements Insertable<EventAbsenceRow> {
  final String eventId;

  /// UTC date-only (year, month, day).
  final DateTime day;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String hlcTimestamp;
  final String deviceId;
  final int version;
  final bool isDeleted;
  final DateTime? deletedAt;
  const EventAbsenceRow({
    required this.eventId,
    required this.day,
    required this.createdAt,
    required this.updatedAt,
    required this.hlcTimestamp,
    required this.deviceId,
    required this.version,
    required this.isDeleted,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['day'] = Variable<DateTime>(day);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['hlc_timestamp'] = Variable<String>(hlcTimestamp);
    map['device_id'] = Variable<String>(deviceId);
    map['version'] = Variable<int>(version);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  EventAbsencesCompanion toCompanion(bool nullToAbsent) {
    return EventAbsencesCompanion(
      eventId: Value(eventId),
      day: Value(day),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      hlcTimestamp: Value(hlcTimestamp),
      deviceId: Value(deviceId),
      version: Value(version),
      isDeleted: Value(isDeleted),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory EventAbsenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventAbsenceRow(
      eventId: serializer.fromJson<String>(json['eventId']),
      day: serializer.fromJson<DateTime>(json['day']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      hlcTimestamp: serializer.fromJson<String>(json['hlcTimestamp']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      version: serializer.fromJson<int>(json['version']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'day': serializer.toJson<DateTime>(day),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'hlcTimestamp': serializer.toJson<String>(hlcTimestamp),
      'deviceId': serializer.toJson<String>(deviceId),
      'version': serializer.toJson<int>(version),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  EventAbsenceRow copyWith({
    String? eventId,
    DateTime? day,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? hlcTimestamp,
    String? deviceId,
    int? version,
    bool? isDeleted,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => EventAbsenceRow(
    eventId: eventId ?? this.eventId,
    day: day ?? this.day,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
    deviceId: deviceId ?? this.deviceId,
    version: version ?? this.version,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  EventAbsenceRow copyWithCompanion(EventAbsencesCompanion data) {
    return EventAbsenceRow(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      day: data.day.present ? data.day.value : this.day,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      hlcTimestamp: data.hlcTimestamp.present
          ? data.hlcTimestamp.value
          : this.hlcTimestamp,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      version: data.version.present ? data.version.value : this.version,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventAbsenceRow(')
          ..write('eventId: $eventId, ')
          ..write('day: $day, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    day,
    createdAt,
    updatedAt,
    hlcTimestamp,
    deviceId,
    version,
    isDeleted,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventAbsenceRow &&
          other.eventId == this.eventId &&
          other.day == this.day &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.hlcTimestamp == this.hlcTimestamp &&
          other.deviceId == this.deviceId &&
          other.version == this.version &&
          other.isDeleted == this.isDeleted &&
          other.deletedAt == this.deletedAt);
}

class EventAbsencesCompanion extends UpdateCompanion<EventAbsenceRow> {
  final Value<String> eventId;
  final Value<DateTime> day;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> hlcTimestamp;
  final Value<String> deviceId;
  final Value<int> version;
  final Value<bool> isDeleted;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const EventAbsencesCompanion({
    this.eventId = const Value.absent(),
    this.day = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.hlcTimestamp = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventAbsencesCompanion.insert({
    required String eventId,
    required DateTime day,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String hlcTimestamp,
    required String deviceId,
    this.version = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       day = Value(day),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlcTimestamp = Value(hlcTimestamp),
       deviceId = Value(deviceId);
  static Insertable<EventAbsenceRow> custom({
    Expression<String>? eventId,
    Expression<DateTime>? day,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? hlcTimestamp,
    Expression<String>? deviceId,
    Expression<int>? version,
    Expression<bool>? isDeleted,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (day != null) 'day': day,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (hlcTimestamp != null) 'hlc_timestamp': hlcTimestamp,
      if (deviceId != null) 'device_id': deviceId,
      if (version != null) 'version': version,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventAbsencesCompanion copyWith({
    Value<String>? eventId,
    Value<DateTime>? day,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? hlcTimestamp,
    Value<String>? deviceId,
    Value<int>? version,
    Value<bool>? isDeleted,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return EventAbsencesCompanion(
      eventId: eventId ?? this.eventId,
      day: day ?? this.day,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (day.present) {
      map['day'] = Variable<DateTime>(day.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (hlcTimestamp.present) {
      map['hlc_timestamp'] = Variable<String>(hlcTimestamp.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventAbsencesCompanion(')
          ..write('eventId: $eventId, ')
          ..write('day: $day, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('hlcTimestamp: $hlcTimestamp, ')
          ..write('deviceId: $deviceId, ')
          ..write('version: $version, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $ContentChunksTable contentChunks = $ContentChunksTable(this);
  late final $SyncMetadataTable syncMetadata = $SyncMetadataTable(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final $CountersTable counters = $CountersTable(this);
  late final $CounterValuesTable counterValues = $CounterValuesTable(this);
  late final $CalendarEventsTable calendarEvents = $CalendarEventsTable(this);
  late final $PublicHolidaysTableTable publicHolidaysTable =
      $PublicHolidaysTableTable(this);
  late final $CalendarCategoriesTable calendarCategories =
      $CalendarCategoriesTable(this);
  late final $EventOccurrenceDescriptionsTable eventOccurrenceDescriptions =
      $EventOccurrenceDescriptionsTable(this);
  late final $EventAbsencesTable eventAbsences = $EventAbsencesTable(this);
  late final FolderDao folderDao = FolderDao(this as AppDatabase);
  late final NoteDao noteDao = NoteDao(this as AppDatabase);
  late final ContentChunkDao contentChunkDao = ContentChunkDao(
    this as AppDatabase,
  );
  late final SyncDao syncDao = SyncDao(this as AppDatabase);
  late final UserSettingsDao userSettingsDao = UserSettingsDao(
    this as AppDatabase,
  );
  late final CounterDao counterDao = CounterDao(this as AppDatabase);
  late final CalendarEventDao calendarEventDao = CalendarEventDao(
    this as AppDatabase,
  );
  late final PublicHolidayDao publicHolidayDao = PublicHolidayDao(
    this as AppDatabase,
  );
  late final CalendarCategoryDao calendarCategoryDao = CalendarCategoryDao(
    this as AppDatabase,
  );
  late final EventOccurrenceDao eventOccurrenceDao = EventOccurrenceDao(
    this as AppDatabase,
  );
  late final EventAbsenceDao eventAbsenceDao = EventAbsenceDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    folders,
    notes,
    contentChunks,
    syncMetadata,
    userSettings,
    counters,
    counterValues,
    calendarEvents,
    publicHolidaysTable,
    calendarCategories,
    eventOccurrenceDescriptions,
    eventAbsences,
  ];
}

typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      required String id,
      required String name,
      Value<String?> parentId,
      Value<int> position,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> noteSortOrder,
      Value<String?> subfolderSortOrder,
      required String hlcTimestamp,
      required String deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> parentId,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> noteSortOrder,
      Value<String?> subfolderSortOrder,
      Value<String> hlcTimestamp,
      Value<String> deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteSortOrder => $composableBuilder(
    column: $table.noteSortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subfolderSortOrder => $composableBuilder(
    column: $table.subfolderSortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteSortOrder => $composableBuilder(
    column: $table.noteSortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subfolderSortOrder => $composableBuilder(
    column: $table.subfolderSortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get noteSortOrder => $composableBuilder(
    column: $table.noteSortOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subfolderSortOrder => $composableBuilder(
    column: $table.subfolderSortOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, BaseReferences<_$AppDatabase, $FoldersTable, Folder>),
          Folder,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> noteSortOrder = const Value.absent(),
                Value<String?> subfolderSortOrder = const Value.absent(),
                Value<String> hlcTimestamp = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                name: name,
                parentId: parentId,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                noteSortOrder: noteSortOrder,
                subfolderSortOrder: subfolderSortOrder,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> parentId = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> noteSortOrder = const Value.absent(),
                Value<String?> subfolderSortOrder = const Value.absent(),
                required String hlcTimestamp,
                required String deviceId,
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                name: name,
                parentId: parentId,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                noteSortOrder: noteSortOrder,
                subfolderSortOrder: subfolderSortOrder,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, BaseReferences<_$AppDatabase, $FoldersTable, Folder>),
      Folder,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      required String folderId,
      required String title,
      Value<String> preview,
      Value<int> contentLength,
      Value<int> chunkCount,
      Value<bool> isCompressed,
      Value<int> position,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String hlcTimestamp,
      required String deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String> folderId,
      Value<String> title,
      Value<String> preview,
      Value<int> contentLength,
      Value<int> chunkCount,
      Value<bool> isCompressed,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> hlcTimestamp,
      Value<String> deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentLength => $composableBuilder(
    column: $table.contentLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentLength => $composableBuilder(
    column: $table.contentLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<int> get contentLength => $composableBuilder(
    column: $table.contentLength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
          Note,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> folderId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> preview = const Value.absent(),
                Value<int> contentLength = const Value.absent(),
                Value<int> chunkCount = const Value.absent(),
                Value<bool> isCompressed = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> hlcTimestamp = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                folderId: folderId,
                title: title,
                preview: preview,
                contentLength: contentLength,
                chunkCount: chunkCount,
                isCompressed: isCompressed,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String folderId,
                required String title,
                Value<String> preview = const Value.absent(),
                Value<int> contentLength = const Value.absent(),
                Value<int> chunkCount = const Value.absent(),
                Value<bool> isCompressed = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                required String hlcTimestamp,
                required String deviceId,
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                folderId: folderId,
                title: title,
                preview: preview,
                contentLength: contentLength,
                chunkCount: chunkCount,
                isCompressed: isCompressed,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
      Note,
      PrefetchHooks Function()
    >;
typedef $$ContentChunksTableCreateCompanionBuilder =
    ContentChunksCompanion Function({
      required String id,
      required String noteId,
      required int chunkIndex,
      required String content,
      Value<bool> isCompressed,
      required String hlcTimestamp,
      required String deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$ContentChunksTableUpdateCompanionBuilder =
    ContentChunksCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<int> chunkIndex,
      Value<String> content,
      Value<bool> isCompressed,
      Value<String> hlcTimestamp,
      Value<String> deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

class $$ContentChunksTableFilterComposer
    extends Composer<_$AppDatabase, $ContentChunksTable> {
  $$ContentChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContentChunksTableOrderingComposer
    extends Composer<_$AppDatabase, $ContentChunksTable> {
  $$ContentChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContentChunksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContentChunksTable> {
  $$ContentChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get isCompressed => $composableBuilder(
    column: $table.isCompressed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);
}

class $$ContentChunksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContentChunksTable,
          ContentChunk,
          $$ContentChunksTableFilterComposer,
          $$ContentChunksTableOrderingComposer,
          $$ContentChunksTableAnnotationComposer,
          $$ContentChunksTableCreateCompanionBuilder,
          $$ContentChunksTableUpdateCompanionBuilder,
          (
            ContentChunk,
            BaseReferences<_$AppDatabase, $ContentChunksTable, ContentChunk>,
          ),
          ContentChunk,
          PrefetchHooks Function()
        > {
  $$ContentChunksTableTableManager(_$AppDatabase db, $ContentChunksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<int> chunkIndex = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<bool> isCompressed = const Value.absent(),
                Value<String> hlcTimestamp = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentChunksCompanion(
                id: id,
                noteId: noteId,
                chunkIndex: chunkIndex,
                content: content,
                isCompressed: isCompressed,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required int chunkIndex,
                required String content,
                Value<bool> isCompressed = const Value.absent(),
                required String hlcTimestamp,
                required String deviceId,
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContentChunksCompanion.insert(
                id: id,
                noteId: noteId,
                chunkIndex: chunkIndex,
                content: content,
                isCompressed: isCompressed,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContentChunksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContentChunksTable,
      ContentChunk,
      $$ContentChunksTableFilterComposer,
      $$ContentChunksTableOrderingComposer,
      $$ContentChunksTableAnnotationComposer,
      $$ContentChunksTableCreateCompanionBuilder,
      $$ContentChunksTableUpdateCompanionBuilder,
      (
        ContentChunk,
        BaseReferences<_$AppDatabase, $ContentChunksTable, ContentChunk>,
      ),
      ContentChunk,
      PrefetchHooks Function()
    >;
typedef $$SyncMetadataTableCreateCompanionBuilder =
    SyncMetadataCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncMetadataTableUpdateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetadataTable,
          SyncMetadataData,
          $$SyncMetadataTableFilterComposer,
          $$SyncMetadataTableOrderingComposer,
          $$SyncMetadataTableAnnotationComposer,
          $$SyncMetadataTableCreateCompanionBuilder,
          $$SyncMetadataTableUpdateCompanionBuilder,
          (
            SyncMetadataData,
            BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataData>,
          ),
          SyncMetadataData,
          PrefetchHooks Function()
        > {
  $$SyncMetadataTableTableManager(_$AppDatabase db, $SyncMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetadataCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetadataCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetadataTable,
      SyncMetadataData,
      $$SyncMetadataTableFilterComposer,
      $$SyncMetadataTableOrderingComposer,
      $$SyncMetadataTableAnnotationComposer,
      $$SyncMetadataTableCreateCompanionBuilder,
      $$SyncMetadataTableUpdateCompanionBuilder,
      (
        SyncMetadataData,
        BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataData>,
      ),
      SyncMetadataData,
      PrefetchHooks Function()
    >;
typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          UserSetting,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            UserSetting,
            BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
          ),
          UserSetting,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => UserSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      UserSetting,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (
        UserSetting,
        BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>,
      ),
      UserSetting,
      PrefetchHooks Function()
    >;
typedef $$CountersTableCreateCompanionBuilder =
    CountersCompanion Function({
      required String id,
      required String name,
      Value<int> startValue,
      Value<int> step,
      Value<String> scope,
      Value<int> position,
      Value<bool> isPinned,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$CountersTableUpdateCompanionBuilder =
    CountersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> startValue,
      Value<int> step,
      Value<String> scope,
      Value<int> position,
      Value<bool> isPinned,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$CountersTableFilterComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startValue => $composableBuilder(
    column: $table.startValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CountersTableOrderingComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startValue => $composableBuilder(
    column: $table.startValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CountersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startValue => $composableBuilder(
    column: $table.startValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CountersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CountersTable,
          CounterRow,
          $$CountersTableFilterComposer,
          $$CountersTableOrderingComposer,
          $$CountersTableAnnotationComposer,
          $$CountersTableCreateCompanionBuilder,
          $$CountersTableUpdateCompanionBuilder,
          (
            CounterRow,
            BaseReferences<_$AppDatabase, $CountersTable, CounterRow>,
          ),
          CounterRow,
          PrefetchHooks Function()
        > {
  $$CountersTableTableManager(_$AppDatabase db, $CountersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> startValue = const Value.absent(),
                Value<int> step = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CountersCompanion(
                id: id,
                name: name,
                startValue: startValue,
                step: step,
                scope: scope,
                position: position,
                isPinned: isPinned,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> startValue = const Value.absent(),
                Value<int> step = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CountersCompanion.insert(
                id: id,
                name: name,
                startValue: startValue,
                step: step,
                scope: scope,
                position: position,
                isPinned: isPinned,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CountersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CountersTable,
      CounterRow,
      $$CountersTableFilterComposer,
      $$CountersTableOrderingComposer,
      $$CountersTableAnnotationComposer,
      $$CountersTableCreateCompanionBuilder,
      $$CountersTableUpdateCompanionBuilder,
      (CounterRow, BaseReferences<_$AppDatabase, $CountersTable, CounterRow>),
      CounterRow,
      PrefetchHooks Function()
    >;
typedef $$CounterValuesTableCreateCompanionBuilder =
    CounterValuesCompanion Function({
      required String counterId,
      Value<String> noteId,
      required int value,
      Value<int> position,
      Value<bool> isPinned,
      Value<int> rowid,
    });
typedef $$CounterValuesTableUpdateCompanionBuilder =
    CounterValuesCompanion Function({
      Value<String> counterId,
      Value<String> noteId,
      Value<int> value,
      Value<int> position,
      Value<bool> isPinned,
      Value<int> rowid,
    });

class $$CounterValuesTableFilterComposer
    extends Composer<_$AppDatabase, $CounterValuesTable> {
  $$CounterValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get counterId => $composableBuilder(
    column: $table.counterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CounterValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $CounterValuesTable> {
  $$CounterValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get counterId => $composableBuilder(
    column: $table.counterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CounterValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CounterValuesTable> {
  $$CounterValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get counterId =>
      $composableBuilder(column: $table.counterId, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);
}

class $$CounterValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CounterValuesTable,
          CounterValueRow,
          $$CounterValuesTableFilterComposer,
          $$CounterValuesTableOrderingComposer,
          $$CounterValuesTableAnnotationComposer,
          $$CounterValuesTableCreateCompanionBuilder,
          $$CounterValuesTableUpdateCompanionBuilder,
          (
            CounterValueRow,
            BaseReferences<_$AppDatabase, $CounterValuesTable, CounterValueRow>,
          ),
          CounterValueRow,
          PrefetchHooks Function()
        > {
  $$CounterValuesTableTableManager(_$AppDatabase db, $CounterValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CounterValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CounterValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CounterValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> counterId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<int> value = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CounterValuesCompanion(
                counterId: counterId,
                noteId: noteId,
                value: value,
                position: position,
                isPinned: isPinned,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String counterId,
                Value<String> noteId = const Value.absent(),
                required int value,
                Value<int> position = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CounterValuesCompanion.insert(
                counterId: counterId,
                noteId: noteId,
                value: value,
                position: position,
                isPinned: isPinned,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CounterValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CounterValuesTable,
      CounterValueRow,
      $$CounterValuesTableFilterComposer,
      $$CounterValuesTableOrderingComposer,
      $$CounterValuesTableAnnotationComposer,
      $$CounterValuesTableCreateCompanionBuilder,
      $$CounterValuesTableUpdateCompanionBuilder,
      (
        CounterValueRow,
        BaseReferences<_$AppDatabase, $CounterValuesTable, CounterValueRow>,
      ),
      CounterValueRow,
      PrefetchHooks Function()
    >;
typedef $$CalendarEventsTableCreateCompanionBuilder =
    CalendarEventsCompanion Function({
      required String id,
      required String title,
      required String category,
      required DateTime startDate,
      Value<bool> allDay,
      Value<String?> iconKey,
      required String ruleKind,
      Value<String?> rulePayload,
      Value<DateTime?> endDate,
      Value<int?> startMinute,
      Value<int?> durationMinutes,
      Value<String?> description,
      Value<String?> noteId,
      Value<int?> colorValue,
      Value<bool> tintIcon,
      Value<int> priority,
      Value<bool> retroactive,
      Value<bool> countOccurrences,
      Value<String> countStyle,
      Value<bool> tracksPresence,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CalendarEventsTableUpdateCompanionBuilder =
    CalendarEventsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> category,
      Value<DateTime> startDate,
      Value<bool> allDay,
      Value<String?> iconKey,
      Value<String> ruleKind,
      Value<String?> rulePayload,
      Value<DateTime?> endDate,
      Value<int?> startMinute,
      Value<int?> durationMinutes,
      Value<String?> description,
      Value<String?> noteId,
      Value<int?> colorValue,
      Value<bool> tintIcon,
      Value<int> priority,
      Value<bool> retroactive,
      Value<bool> countOccurrences,
      Value<String> countStyle,
      Value<bool> tracksPresence,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CalendarEventsTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleKind => $composableBuilder(
    column: $table.ruleKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rulePayload => $composableBuilder(
    column: $table.rulePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tintIcon => $composableBuilder(
    column: $table.tintIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get retroactive => $composableBuilder(
    column: $table.retroactive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get countOccurrences => $composableBuilder(
    column: $table.countOccurrences,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countStyle => $composableBuilder(
    column: $table.countStyle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tracksPresence => $composableBuilder(
    column: $table.tracksPresence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CalendarEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleKind => $composableBuilder(
    column: $table.ruleKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rulePayload => $composableBuilder(
    column: $table.rulePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tintIcon => $composableBuilder(
    column: $table.tintIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get retroactive => $composableBuilder(
    column: $table.retroactive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get countOccurrences => $composableBuilder(
    column: $table.countOccurrences,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countStyle => $composableBuilder(
    column: $table.countStyle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tracksPresence => $composableBuilder(
    column: $table.tracksPresence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CalendarEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<bool> get allDay =>
      $composableBuilder(column: $table.allDay, builder: (column) => column);

  GeneratedColumn<String> get iconKey =>
      $composableBuilder(column: $table.iconKey, builder: (column) => column);

  GeneratedColumn<String> get ruleKind =>
      $composableBuilder(column: $table.ruleKind, builder: (column) => column);

  GeneratedColumn<String> get rulePayload => $composableBuilder(
    column: $table.rulePayload,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
    column: $table.durationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get tintIcon =>
      $composableBuilder(column: $table.tintIcon, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get retroactive => $composableBuilder(
    column: $table.retroactive,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get countOccurrences => $composableBuilder(
    column: $table.countOccurrences,
    builder: (column) => column,
  );

  GeneratedColumn<String> get countStyle => $composableBuilder(
    column: $table.countStyle,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get tracksPresence => $composableBuilder(
    column: $table.tracksPresence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CalendarEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarEventsTable,
          CalendarEventRow,
          $$CalendarEventsTableFilterComposer,
          $$CalendarEventsTableOrderingComposer,
          $$CalendarEventsTableAnnotationComposer,
          $$CalendarEventsTableCreateCompanionBuilder,
          $$CalendarEventsTableUpdateCompanionBuilder,
          (
            CalendarEventRow,
            BaseReferences<
              _$AppDatabase,
              $CalendarEventsTable,
              CalendarEventRow
            >,
          ),
          CalendarEventRow,
          PrefetchHooks Function()
        > {
  $$CalendarEventsTableTableManager(
    _$AppDatabase db,
    $CalendarEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<bool> allDay = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                Value<String> ruleKind = const Value.absent(),
                Value<String?> rulePayload = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<int?> startMinute = const Value.absent(),
                Value<int?> durationMinutes = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> tintIcon = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<bool> retroactive = const Value.absent(),
                Value<bool> countOccurrences = const Value.absent(),
                Value<String> countStyle = const Value.absent(),
                Value<bool> tracksPresence = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarEventsCompanion(
                id: id,
                title: title,
                category: category,
                startDate: startDate,
                allDay: allDay,
                iconKey: iconKey,
                ruleKind: ruleKind,
                rulePayload: rulePayload,
                endDate: endDate,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                description: description,
                noteId: noteId,
                colorValue: colorValue,
                tintIcon: tintIcon,
                priority: priority,
                retroactive: retroactive,
                countOccurrences: countOccurrences,
                countStyle: countStyle,
                tracksPresence: tracksPresence,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String category,
                required DateTime startDate,
                Value<bool> allDay = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                required String ruleKind,
                Value<String?> rulePayload = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<int?> startMinute = const Value.absent(),
                Value<int?> durationMinutes = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<int?> colorValue = const Value.absent(),
                Value<bool> tintIcon = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<bool> retroactive = const Value.absent(),
                Value<bool> countOccurrences = const Value.absent(),
                Value<String> countStyle = const Value.absent(),
                Value<bool> tracksPresence = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CalendarEventsCompanion.insert(
                id: id,
                title: title,
                category: category,
                startDate: startDate,
                allDay: allDay,
                iconKey: iconKey,
                ruleKind: ruleKind,
                rulePayload: rulePayload,
                endDate: endDate,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                description: description,
                noteId: noteId,
                colorValue: colorValue,
                tintIcon: tintIcon,
                priority: priority,
                retroactive: retroactive,
                countOccurrences: countOccurrences,
                countStyle: countStyle,
                tracksPresence: tracksPresence,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CalendarEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarEventsTable,
      CalendarEventRow,
      $$CalendarEventsTableFilterComposer,
      $$CalendarEventsTableOrderingComposer,
      $$CalendarEventsTableAnnotationComposer,
      $$CalendarEventsTableCreateCompanionBuilder,
      $$CalendarEventsTableUpdateCompanionBuilder,
      (
        CalendarEventRow,
        BaseReferences<_$AppDatabase, $CalendarEventsTable, CalendarEventRow>,
      ),
      CalendarEventRow,
      PrefetchHooks Function()
    >;
typedef $$PublicHolidaysTableTableCreateCompanionBuilder =
    PublicHolidaysTableCompanion Function({
      required DateTime date,
      required String nameKey,
      Value<String> profile,
      Value<String?> customLabel,
      Value<bool> suppressed,
      Value<int> rowid,
    });
typedef $$PublicHolidaysTableTableUpdateCompanionBuilder =
    PublicHolidaysTableCompanion Function({
      Value<DateTime> date,
      Value<String> nameKey,
      Value<String> profile,
      Value<String?> customLabel,
      Value<bool> suppressed,
      Value<int> rowid,
    });

class $$PublicHolidaysTableTableFilterComposer
    extends Composer<_$AppDatabase, $PublicHolidaysTableTable> {
  $$PublicHolidaysTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get suppressed => $composableBuilder(
    column: $table.suppressed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PublicHolidaysTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PublicHolidaysTableTable> {
  $$PublicHolidaysTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get suppressed => $composableBuilder(
    column: $table.suppressed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PublicHolidaysTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PublicHolidaysTableTable> {
  $$PublicHolidaysTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  GeneratedColumn<String> get profile =>
      $composableBuilder(column: $table.profile, builder: (column) => column);

  GeneratedColumn<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get suppressed => $composableBuilder(
    column: $table.suppressed,
    builder: (column) => column,
  );
}

class $$PublicHolidaysTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PublicHolidaysTableTable,
          PublicHolidayRow,
          $$PublicHolidaysTableTableFilterComposer,
          $$PublicHolidaysTableTableOrderingComposer,
          $$PublicHolidaysTableTableAnnotationComposer,
          $$PublicHolidaysTableTableCreateCompanionBuilder,
          $$PublicHolidaysTableTableUpdateCompanionBuilder,
          (
            PublicHolidayRow,
            BaseReferences<
              _$AppDatabase,
              $PublicHolidaysTableTable,
              PublicHolidayRow
            >,
          ),
          PublicHolidayRow,
          PrefetchHooks Function()
        > {
  $$PublicHolidaysTableTableTableManager(
    _$AppDatabase db,
    $PublicHolidaysTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PublicHolidaysTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PublicHolidaysTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PublicHolidaysTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<DateTime> date = const Value.absent(),
                Value<String> nameKey = const Value.absent(),
                Value<String> profile = const Value.absent(),
                Value<String?> customLabel = const Value.absent(),
                Value<bool> suppressed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PublicHolidaysTableCompanion(
                date: date,
                nameKey: nameKey,
                profile: profile,
                customLabel: customLabel,
                suppressed: suppressed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime date,
                required String nameKey,
                Value<String> profile = const Value.absent(),
                Value<String?> customLabel = const Value.absent(),
                Value<bool> suppressed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PublicHolidaysTableCompanion.insert(
                date: date,
                nameKey: nameKey,
                profile: profile,
                customLabel: customLabel,
                suppressed: suppressed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PublicHolidaysTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PublicHolidaysTableTable,
      PublicHolidayRow,
      $$PublicHolidaysTableTableFilterComposer,
      $$PublicHolidaysTableTableOrderingComposer,
      $$PublicHolidaysTableTableAnnotationComposer,
      $$PublicHolidaysTableTableCreateCompanionBuilder,
      $$PublicHolidaysTableTableUpdateCompanionBuilder,
      (
        PublicHolidayRow,
        BaseReferences<
          _$AppDatabase,
          $PublicHolidaysTableTable,
          PublicHolidayRow
        >,
      ),
      PublicHolidayRow,
      PrefetchHooks Function()
    >;
typedef $$CalendarCategoriesTableCreateCompanionBuilder =
    CalendarCategoriesCompanion Function({
      required String id,
      required String name,
      required int colorValue,
      required String iconKey,
      Value<int> sortOrder,
      Value<bool> isBuiltIn,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CalendarCategoriesTableUpdateCompanionBuilder =
    CalendarCategoriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> colorValue,
      Value<String> iconKey,
      Value<int> sortOrder,
      Value<bool> isBuiltIn,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CalendarCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarCategoriesTable> {
  $$CalendarCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CalendarCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarCategoriesTable> {
  $$CalendarCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CalendarCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarCategoriesTable> {
  $$CalendarCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iconKey =>
      $composableBuilder(column: $table.iconKey, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltIn =>
      $composableBuilder(column: $table.isBuiltIn, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CalendarCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarCategoriesTable,
          CalendarCategoryRow,
          $$CalendarCategoriesTableFilterComposer,
          $$CalendarCategoriesTableOrderingComposer,
          $$CalendarCategoriesTableAnnotationComposer,
          $$CalendarCategoriesTableCreateCompanionBuilder,
          $$CalendarCategoriesTableUpdateCompanionBuilder,
          (
            CalendarCategoryRow,
            BaseReferences<
              _$AppDatabase,
              $CalendarCategoriesTable,
              CalendarCategoryRow
            >,
          ),
          CalendarCategoryRow,
          PrefetchHooks Function()
        > {
  $$CalendarCategoriesTableTableManager(
    _$AppDatabase db,
    $CalendarCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String> iconKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isBuiltIn = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarCategoriesCompanion(
                id: id,
                name: name,
                colorValue: colorValue,
                iconKey: iconKey,
                sortOrder: sortOrder,
                isBuiltIn: isBuiltIn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int colorValue,
                required String iconKey,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isBuiltIn = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CalendarCategoriesCompanion.insert(
                id: id,
                name: name,
                colorValue: colorValue,
                iconKey: iconKey,
                sortOrder: sortOrder,
                isBuiltIn: isBuiltIn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CalendarCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarCategoriesTable,
      CalendarCategoryRow,
      $$CalendarCategoriesTableFilterComposer,
      $$CalendarCategoriesTableOrderingComposer,
      $$CalendarCategoriesTableAnnotationComposer,
      $$CalendarCategoriesTableCreateCompanionBuilder,
      $$CalendarCategoriesTableUpdateCompanionBuilder,
      (
        CalendarCategoryRow,
        BaseReferences<
          _$AppDatabase,
          $CalendarCategoriesTable,
          CalendarCategoryRow
        >,
      ),
      CalendarCategoryRow,
      PrefetchHooks Function()
    >;
typedef $$EventOccurrenceDescriptionsTableCreateCompanionBuilder =
    EventOccurrenceDescriptionsCompanion Function({
      required String eventId,
      required DateTime day,
      required String description,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$EventOccurrenceDescriptionsTableUpdateCompanionBuilder =
    EventOccurrenceDescriptionsCompanion Function({
      Value<String> eventId,
      Value<DateTime> day,
      Value<String> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$EventOccurrenceDescriptionsTableFilterComposer
    extends Composer<_$AppDatabase, $EventOccurrenceDescriptionsTable> {
  $$EventOccurrenceDescriptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventOccurrenceDescriptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventOccurrenceDescriptionsTable> {
  $$EventOccurrenceDescriptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventOccurrenceDescriptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventOccurrenceDescriptionsTable> {
  $$EventOccurrenceDescriptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<DateTime> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EventOccurrenceDescriptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventOccurrenceDescriptionsTable,
          EventOccurrenceRow,
          $$EventOccurrenceDescriptionsTableFilterComposer,
          $$EventOccurrenceDescriptionsTableOrderingComposer,
          $$EventOccurrenceDescriptionsTableAnnotationComposer,
          $$EventOccurrenceDescriptionsTableCreateCompanionBuilder,
          $$EventOccurrenceDescriptionsTableUpdateCompanionBuilder,
          (
            EventOccurrenceRow,
            BaseReferences<
              _$AppDatabase,
              $EventOccurrenceDescriptionsTable,
              EventOccurrenceRow
            >,
          ),
          EventOccurrenceRow,
          PrefetchHooks Function()
        > {
  $$EventOccurrenceDescriptionsTableTableManager(
    _$AppDatabase db,
    $EventOccurrenceDescriptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventOccurrenceDescriptionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$EventOccurrenceDescriptionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EventOccurrenceDescriptionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<DateTime> day = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventOccurrenceDescriptionsCompanion(
                eventId: eventId,
                day: day,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required DateTime day,
                required String description,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EventOccurrenceDescriptionsCompanion.insert(
                eventId: eventId,
                day: day,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventOccurrenceDescriptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventOccurrenceDescriptionsTable,
      EventOccurrenceRow,
      $$EventOccurrenceDescriptionsTableFilterComposer,
      $$EventOccurrenceDescriptionsTableOrderingComposer,
      $$EventOccurrenceDescriptionsTableAnnotationComposer,
      $$EventOccurrenceDescriptionsTableCreateCompanionBuilder,
      $$EventOccurrenceDescriptionsTableUpdateCompanionBuilder,
      (
        EventOccurrenceRow,
        BaseReferences<
          _$AppDatabase,
          $EventOccurrenceDescriptionsTable,
          EventOccurrenceRow
        >,
      ),
      EventOccurrenceRow,
      PrefetchHooks Function()
    >;
typedef $$EventAbsencesTableCreateCompanionBuilder =
    EventAbsencesCompanion Function({
      required String eventId,
      required DateTime day,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String hlcTimestamp,
      required String deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$EventAbsencesTableUpdateCompanionBuilder =
    EventAbsencesCompanion Function({
      Value<String> eventId,
      Value<DateTime> day,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> hlcTimestamp,
      Value<String> deviceId,
      Value<int> version,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$EventAbsencesTableFilterComposer
    extends Composer<_$AppDatabase, $EventAbsencesTable> {
  $$EventAbsencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventAbsencesTableOrderingComposer
    extends Composer<_$AppDatabase, $EventAbsencesTable> {
  $$EventAbsencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventAbsencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventAbsencesTable> {
  $$EventAbsencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<DateTime> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get hlcTimestamp => $composableBuilder(
    column: $table.hlcTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$EventAbsencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventAbsencesTable,
          EventAbsenceRow,
          $$EventAbsencesTableFilterComposer,
          $$EventAbsencesTableOrderingComposer,
          $$EventAbsencesTableAnnotationComposer,
          $$EventAbsencesTableCreateCompanionBuilder,
          $$EventAbsencesTableUpdateCompanionBuilder,
          (
            EventAbsenceRow,
            BaseReferences<_$AppDatabase, $EventAbsencesTable, EventAbsenceRow>,
          ),
          EventAbsenceRow,
          PrefetchHooks Function()
        > {
  $$EventAbsencesTableTableManager(_$AppDatabase db, $EventAbsencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventAbsencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventAbsencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventAbsencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<DateTime> day = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> hlcTimestamp = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventAbsencesCompanion(
                eventId: eventId,
                day: day,
                createdAt: createdAt,
                updatedAt: updatedAt,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required DateTime day,
                required DateTime createdAt,
                required DateTime updatedAt,
                required String hlcTimestamp,
                required String deviceId,
                Value<int> version = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventAbsencesCompanion.insert(
                eventId: eventId,
                day: day,
                createdAt: createdAt,
                updatedAt: updatedAt,
                hlcTimestamp: hlcTimestamp,
                deviceId: deviceId,
                version: version,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventAbsencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventAbsencesTable,
      EventAbsenceRow,
      $$EventAbsencesTableFilterComposer,
      $$EventAbsencesTableOrderingComposer,
      $$EventAbsencesTableAnnotationComposer,
      $$EventAbsencesTableCreateCompanionBuilder,
      $$EventAbsencesTableUpdateCompanionBuilder,
      (
        EventAbsenceRow,
        BaseReferences<_$AppDatabase, $EventAbsencesTable, EventAbsenceRow>,
      ),
      EventAbsenceRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$ContentChunksTableTableManager get contentChunks =>
      $$ContentChunksTableTableManager(_db, _db.contentChunks);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db, _db.syncMetadata);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
  $$CountersTableTableManager get counters =>
      $$CountersTableTableManager(_db, _db.counters);
  $$CounterValuesTableTableManager get counterValues =>
      $$CounterValuesTableTableManager(_db, _db.counterValues);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(_db, _db.calendarEvents);
  $$PublicHolidaysTableTableTableManager get publicHolidaysTable =>
      $$PublicHolidaysTableTableTableManager(_db, _db.publicHolidaysTable);
  $$CalendarCategoriesTableTableManager get calendarCategories =>
      $$CalendarCategoriesTableTableManager(_db, _db.calendarCategories);
  $$EventOccurrenceDescriptionsTableTableManager
  get eventOccurrenceDescriptions =>
      $$EventOccurrenceDescriptionsTableTableManager(
        _db,
        _db.eventOccurrenceDescriptions,
      );
  $$EventAbsencesTableTableManager get eventAbsences =>
      $$EventAbsencesTableTableManager(_db, _db.eventAbsences);
}
