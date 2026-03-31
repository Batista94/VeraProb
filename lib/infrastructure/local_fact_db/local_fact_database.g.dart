// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_fact_database.dart';

// ignore_for_file: type=lint
class $PendingFactsTable extends PendingFacts
    with TableInfo<$PendingFactsTable, PendingFact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _factIdMeta = const VerificationMeta('factId');
  @override
  late final GeneratedColumn<String> factId = GeneratedColumn<String>(
    'fact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _factPayloadJsonMeta = const VerificationMeta(
    'factPayloadJson',
  );
  @override
  late final GeneratedColumn<String> factPayloadJson = GeneratedColumn<String>(
    'fact_payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtUtcMeta = const VerificationMeta(
    'receivedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAtUtc =
      GeneratedColumn<DateTime>(
        'received_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _queuedAtUtcMeta = const VerificationMeta(
    'queuedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> queuedAtUtc = GeneratedColumn<DateTime>(
    'queued_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localSequenceMeta = const VerificationMeta(
    'localSequence',
  );
  @override
  late final GeneratedColumn<int> localSequence = GeneratedColumn<int>(
    'local_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    factId,
    organizationId,
    contentHash,
    factPayloadJson,
    receivedAtUtc,
    queuedAtUtc,
    syncStatus,
    retryCount,
    errorMessage,
    localSequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_facts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingFact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fact_id')) {
      context.handle(
        _factIdMeta,
        factId.isAcceptableOrUnknown(data['fact_id']!, _factIdMeta),
      );
    } else if (isInserting) {
      context.missing(_factIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('fact_payload_json')) {
      context.handle(
        _factPayloadJsonMeta,
        factPayloadJson.isAcceptableOrUnknown(
          data['fact_payload_json']!,
          _factPayloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_factPayloadJsonMeta);
    }
    if (data.containsKey('received_at_utc')) {
      context.handle(
        _receivedAtUtcMeta,
        receivedAtUtc.isAcceptableOrUnknown(
          data['received_at_utc']!,
          _receivedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receivedAtUtcMeta);
    }
    if (data.containsKey('queued_at_utc')) {
      context.handle(
        _queuedAtUtcMeta,
        queuedAtUtc.isAcceptableOrUnknown(
          data['queued_at_utc']!,
          _queuedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_queuedAtUtcMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStatusMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('local_sequence')) {
      context.handle(
        _localSequenceMeta,
        localSequence.isAcceptableOrUnknown(
          data['local_sequence']!,
          _localSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localSequenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {factId};
  @override
  PendingFact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingFact(
      factId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fact_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      factPayloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fact_payload_json'],
      )!,
      receivedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at_utc'],
      )!,
      queuedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queued_at_utc'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      localSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_sequence'],
      )!,
    );
  }

  @override
  $PendingFactsTable createAlias(String alias) {
    return $PendingFactsTable(attachedDatabase, alias);
  }
}

class PendingFact extends DataClass implements Insertable<PendingFact> {
  final String factId;
  final String organizationId;
  final String contentHash;
  final String factPayloadJson;
  final DateTime receivedAtUtc;
  final DateTime queuedAtUtc;
  final String syncStatus;
  final int retryCount;
  final String? errorMessage;
  final int localSequence;
  const PendingFact({
    required this.factId,
    required this.organizationId,
    required this.contentHash,
    required this.factPayloadJson,
    required this.receivedAtUtc,
    required this.queuedAtUtc,
    required this.syncStatus,
    required this.retryCount,
    this.errorMessage,
    required this.localSequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fact_id'] = Variable<String>(factId);
    map['organization_id'] = Variable<String>(organizationId);
    map['content_hash'] = Variable<String>(contentHash);
    map['fact_payload_json'] = Variable<String>(factPayloadJson);
    map['received_at_utc'] = Variable<DateTime>(receivedAtUtc);
    map['queued_at_utc'] = Variable<DateTime>(queuedAtUtc);
    map['sync_status'] = Variable<String>(syncStatus);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['local_sequence'] = Variable<int>(localSequence);
    return map;
  }

  PendingFactsCompanion toCompanion(bool nullToAbsent) {
    return PendingFactsCompanion(
      factId: Value(factId),
      organizationId: Value(organizationId),
      contentHash: Value(contentHash),
      factPayloadJson: Value(factPayloadJson),
      receivedAtUtc: Value(receivedAtUtc),
      queuedAtUtc: Value(queuedAtUtc),
      syncStatus: Value(syncStatus),
      retryCount: Value(retryCount),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      localSequence: Value(localSequence),
    );
  }

  factory PendingFact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingFact(
      factId: serializer.fromJson<String>(json['factId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      factPayloadJson: serializer.fromJson<String>(json['factPayloadJson']),
      receivedAtUtc: serializer.fromJson<DateTime>(json['receivedAtUtc']),
      queuedAtUtc: serializer.fromJson<DateTime>(json['queuedAtUtc']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      localSequence: serializer.fromJson<int>(json['localSequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'factId': serializer.toJson<String>(factId),
      'organizationId': serializer.toJson<String>(organizationId),
      'contentHash': serializer.toJson<String>(contentHash),
      'factPayloadJson': serializer.toJson<String>(factPayloadJson),
      'receivedAtUtc': serializer.toJson<DateTime>(receivedAtUtc),
      'queuedAtUtc': serializer.toJson<DateTime>(queuedAtUtc),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'retryCount': serializer.toJson<int>(retryCount),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'localSequence': serializer.toJson<int>(localSequence),
    };
  }

  PendingFact copyWith({
    String? factId,
    String? organizationId,
    String? contentHash,
    String? factPayloadJson,
    DateTime? receivedAtUtc,
    DateTime? queuedAtUtc,
    String? syncStatus,
    int? retryCount,
    Value<String?> errorMessage = const Value.absent(),
    int? localSequence,
  }) => PendingFact(
    factId: factId ?? this.factId,
    organizationId: organizationId ?? this.organizationId,
    contentHash: contentHash ?? this.contentHash,
    factPayloadJson: factPayloadJson ?? this.factPayloadJson,
    receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
    queuedAtUtc: queuedAtUtc ?? this.queuedAtUtc,
    syncStatus: syncStatus ?? this.syncStatus,
    retryCount: retryCount ?? this.retryCount,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    localSequence: localSequence ?? this.localSequence,
  );
  PendingFact copyWithCompanion(PendingFactsCompanion data) {
    return PendingFact(
      factId: data.factId.present ? data.factId.value : this.factId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      factPayloadJson: data.factPayloadJson.present
          ? data.factPayloadJson.value
          : this.factPayloadJson,
      receivedAtUtc: data.receivedAtUtc.present
          ? data.receivedAtUtc.value
          : this.receivedAtUtc,
      queuedAtUtc: data.queuedAtUtc.present
          ? data.queuedAtUtc.value
          : this.queuedAtUtc,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      localSequence: data.localSequence.present
          ? data.localSequence.value
          : this.localSequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingFact(')
          ..write('factId: $factId, ')
          ..write('organizationId: $organizationId, ')
          ..write('contentHash: $contentHash, ')
          ..write('factPayloadJson: $factPayloadJson, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('queuedAtUtc: $queuedAtUtc, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('retryCount: $retryCount, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('localSequence: $localSequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    factId,
    organizationId,
    contentHash,
    factPayloadJson,
    receivedAtUtc,
    queuedAtUtc,
    syncStatus,
    retryCount,
    errorMessage,
    localSequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingFact &&
          other.factId == this.factId &&
          other.organizationId == this.organizationId &&
          other.contentHash == this.contentHash &&
          other.factPayloadJson == this.factPayloadJson &&
          other.receivedAtUtc == this.receivedAtUtc &&
          other.queuedAtUtc == this.queuedAtUtc &&
          other.syncStatus == this.syncStatus &&
          other.retryCount == this.retryCount &&
          other.errorMessage == this.errorMessage &&
          other.localSequence == this.localSequence);
}

class PendingFactsCompanion extends UpdateCompanion<PendingFact> {
  final Value<String> factId;
  final Value<String> organizationId;
  final Value<String> contentHash;
  final Value<String> factPayloadJson;
  final Value<DateTime> receivedAtUtc;
  final Value<DateTime> queuedAtUtc;
  final Value<String> syncStatus;
  final Value<int> retryCount;
  final Value<String?> errorMessage;
  final Value<int> localSequence;
  final Value<int> rowid;
  const PendingFactsCompanion({
    this.factId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.factPayloadJson = const Value.absent(),
    this.receivedAtUtc = const Value.absent(),
    this.queuedAtUtc = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.localSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingFactsCompanion.insert({
    required String factId,
    required String organizationId,
    required String contentHash,
    required String factPayloadJson,
    required DateTime receivedAtUtc,
    required DateTime queuedAtUtc,
    required String syncStatus,
    this.retryCount = const Value.absent(),
    this.errorMessage = const Value.absent(),
    required int localSequence,
    this.rowid = const Value.absent(),
  }) : factId = Value(factId),
       organizationId = Value(organizationId),
       contentHash = Value(contentHash),
       factPayloadJson = Value(factPayloadJson),
       receivedAtUtc = Value(receivedAtUtc),
       queuedAtUtc = Value(queuedAtUtc),
       syncStatus = Value(syncStatus),
       localSequence = Value(localSequence);
  static Insertable<PendingFact> custom({
    Expression<String>? factId,
    Expression<String>? organizationId,
    Expression<String>? contentHash,
    Expression<String>? factPayloadJson,
    Expression<DateTime>? receivedAtUtc,
    Expression<DateTime>? queuedAtUtc,
    Expression<String>? syncStatus,
    Expression<int>? retryCount,
    Expression<String>? errorMessage,
    Expression<int>? localSequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (factId != null) 'fact_id': factId,
      if (organizationId != null) 'organization_id': organizationId,
      if (contentHash != null) 'content_hash': contentHash,
      if (factPayloadJson != null) 'fact_payload_json': factPayloadJson,
      if (receivedAtUtc != null) 'received_at_utc': receivedAtUtc,
      if (queuedAtUtc != null) 'queued_at_utc': queuedAtUtc,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (retryCount != null) 'retry_count': retryCount,
      if (errorMessage != null) 'error_message': errorMessage,
      if (localSequence != null) 'local_sequence': localSequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingFactsCompanion copyWith({
    Value<String>? factId,
    Value<String>? organizationId,
    Value<String>? contentHash,
    Value<String>? factPayloadJson,
    Value<DateTime>? receivedAtUtc,
    Value<DateTime>? queuedAtUtc,
    Value<String>? syncStatus,
    Value<int>? retryCount,
    Value<String?>? errorMessage,
    Value<int>? localSequence,
    Value<int>? rowid,
  }) {
    return PendingFactsCompanion(
      factId: factId ?? this.factId,
      organizationId: organizationId ?? this.organizationId,
      contentHash: contentHash ?? this.contentHash,
      factPayloadJson: factPayloadJson ?? this.factPayloadJson,
      receivedAtUtc: receivedAtUtc ?? this.receivedAtUtc,
      queuedAtUtc: queuedAtUtc ?? this.queuedAtUtc,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      localSequence: localSequence ?? this.localSequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (factId.present) {
      map['fact_id'] = Variable<String>(factId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (factPayloadJson.present) {
      map['fact_payload_json'] = Variable<String>(factPayloadJson.value);
    }
    if (receivedAtUtc.present) {
      map['received_at_utc'] = Variable<DateTime>(receivedAtUtc.value);
    }
    if (queuedAtUtc.present) {
      map['queued_at_utc'] = Variable<DateTime>(queuedAtUtc.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (localSequence.present) {
      map['local_sequence'] = Variable<int>(localSequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingFactsCompanion(')
          ..write('factId: $factId, ')
          ..write('organizationId: $organizationId, ')
          ..write('contentHash: $contentHash, ')
          ..write('factPayloadJson: $factPayloadJson, ')
          ..write('receivedAtUtc: $receivedAtUtc, ')
          ..write('queuedAtUtc: $queuedAtUtc, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('retryCount: $retryCount, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('localSequence: $localSequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalFactDatabase extends GeneratedDatabase {
  _$LocalFactDatabase(QueryExecutor e) : super(e);
  $LocalFactDatabaseManager get managers => $LocalFactDatabaseManager(this);
  late final $PendingFactsTable pendingFacts = $PendingFactsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [pendingFacts];
}

typedef $$PendingFactsTableCreateCompanionBuilder =
    PendingFactsCompanion Function({
      required String factId,
      required String organizationId,
      required String contentHash,
      required String factPayloadJson,
      required DateTime receivedAtUtc,
      required DateTime queuedAtUtc,
      required String syncStatus,
      Value<int> retryCount,
      Value<String?> errorMessage,
      required int localSequence,
      Value<int> rowid,
    });
typedef $$PendingFactsTableUpdateCompanionBuilder =
    PendingFactsCompanion Function({
      Value<String> factId,
      Value<String> organizationId,
      Value<String> contentHash,
      Value<String> factPayloadJson,
      Value<DateTime> receivedAtUtc,
      Value<DateTime> queuedAtUtc,
      Value<String> syncStatus,
      Value<int> retryCount,
      Value<String?> errorMessage,
      Value<int> localSequence,
      Value<int> rowid,
    });

class $$PendingFactsTableFilterComposer
    extends Composer<_$LocalFactDatabase, $PendingFactsTable> {
  $$PendingFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get factId => $composableBuilder(
    column: $table.factId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get factPayloadJson => $composableBuilder(
    column: $table.factPayloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAtUtc => $composableBuilder(
    column: $table.receivedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queuedAtUtc => $composableBuilder(
    column: $table.queuedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingFactsTableOrderingComposer
    extends Composer<_$LocalFactDatabase, $PendingFactsTable> {
  $$PendingFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get factId => $composableBuilder(
    column: $table.factId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get factPayloadJson => $composableBuilder(
    column: $table.factPayloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAtUtc => $composableBuilder(
    column: $table.receivedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queuedAtUtc => $composableBuilder(
    column: $table.queuedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingFactsTableAnnotationComposer
    extends Composer<_$LocalFactDatabase, $PendingFactsTable> {
  $$PendingFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get factId =>
      $composableBuilder(column: $table.factId, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get factPayloadJson => $composableBuilder(
    column: $table.factPayloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receivedAtUtc => $composableBuilder(
    column: $table.receivedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get queuedAtUtc => $composableBuilder(
    column: $table.queuedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => column,
  );
}

class $$PendingFactsTableTableManager
    extends
        RootTableManager<
          _$LocalFactDatabase,
          $PendingFactsTable,
          PendingFact,
          $$PendingFactsTableFilterComposer,
          $$PendingFactsTableOrderingComposer,
          $$PendingFactsTableAnnotationComposer,
          $$PendingFactsTableCreateCompanionBuilder,
          $$PendingFactsTableUpdateCompanionBuilder,
          (
            PendingFact,
            BaseReferences<
              _$LocalFactDatabase,
              $PendingFactsTable,
              PendingFact
            >,
          ),
          PendingFact,
          PrefetchHooks Function()
        > {
  $$PendingFactsTableTableManager(
    _$LocalFactDatabase db,
    $PendingFactsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> factId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String> factPayloadJson = const Value.absent(),
                Value<DateTime> receivedAtUtc = const Value.absent(),
                Value<DateTime> queuedAtUtc = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> localSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingFactsCompanion(
                factId: factId,
                organizationId: organizationId,
                contentHash: contentHash,
                factPayloadJson: factPayloadJson,
                receivedAtUtc: receivedAtUtc,
                queuedAtUtc: queuedAtUtc,
                syncStatus: syncStatus,
                retryCount: retryCount,
                errorMessage: errorMessage,
                localSequence: localSequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String factId,
                required String organizationId,
                required String contentHash,
                required String factPayloadJson,
                required DateTime receivedAtUtc,
                required DateTime queuedAtUtc,
                required String syncStatus,
                Value<int> retryCount = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                required int localSequence,
                Value<int> rowid = const Value.absent(),
              }) => PendingFactsCompanion.insert(
                factId: factId,
                organizationId: organizationId,
                contentHash: contentHash,
                factPayloadJson: factPayloadJson,
                receivedAtUtc: receivedAtUtc,
                queuedAtUtc: queuedAtUtc,
                syncStatus: syncStatus,
                retryCount: retryCount,
                errorMessage: errorMessage,
                localSequence: localSequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalFactDatabase,
      $PendingFactsTable,
      PendingFact,
      $$PendingFactsTableFilterComposer,
      $$PendingFactsTableOrderingComposer,
      $$PendingFactsTableAnnotationComposer,
      $$PendingFactsTableCreateCompanionBuilder,
      $$PendingFactsTableUpdateCompanionBuilder,
      (
        PendingFact,
        BaseReferences<_$LocalFactDatabase, $PendingFactsTable, PendingFact>,
      ),
      PendingFact,
      PrefetchHooks Function()
    >;

class $LocalFactDatabaseManager {
  final _$LocalFactDatabase _db;
  $LocalFactDatabaseManager(this._db);
  $$PendingFactsTableTableManager get pendingFacts =>
      $$PendingFactsTableTableManager(_db, _db.pendingFacts);
}
