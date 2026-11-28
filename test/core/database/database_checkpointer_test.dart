import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/database/database_checkpointer.dart';

void main() {
  test('waits for in-flight saves before checkpointing', () async {
    final events = <String>[];
    final save = Completer<void>();
    final checkpointer = DatabaseCheckpointer(() async {
      events.add('checkpoint');
    });

    Future<void> waiter() async {
      await save.future;
      events.add('save done');
    }

    checkpointer.addPendingSaveWaiter(waiter);
    final done = checkpointer.checkpoint();
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);

    save.complete();
    await done;
    expect(events, ['save done', 'checkpoint']);

    checkpointer.removePendingSaveWaiter(waiter);
    events.clear();
    await checkpointer.checkpoint();
    expect(events, ['checkpoint']);
  });

  test('a failing checkpoint does not throw', () async {
    final checkpointer = DatabaseCheckpointer(() async {
      throw StateError('busy');
    });
    await checkpointer.checkpoint();
  });

  test('checkpointWal empties the WAL file into the database file', () async {
    final dir = await Directory.systemTemp.createTemp('ludorank_wal_');
    final file = File('${dir.path}/ludorank.db');
    final database = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (db) => db.execute('PRAGMA journal_mode = WAL'),
      ),
    );
    final wal = File('${file.path}-wal');

    await database.customStatement(
      "INSERT INTO players (id, name, normalized_name, created_at, updated_at) "
      "VALUES ('p1', 'Ahmed', 'ahmed', 0, 0)",
    );
    expect(wal.existsSync() && wal.lengthSync() > 0, isTrue);

    await database.checkpointWal();
    expect(wal.existsSync() ? wal.lengthSync() : 0, 0);

    await database.close();
    await dir.delete(recursive: true);
  });
}
