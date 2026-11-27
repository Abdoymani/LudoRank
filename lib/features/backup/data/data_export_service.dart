import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'package:ludo_rank/core/database/database.dart';

/// The two files of one export.
class DataExport {
  /// A complete SQLite copy of the database (VACUUM INTO).
  final File databaseFile;

  /// Every player, tournament, tournament player, match and match player
  /// as JSON, with schemaVersion and exportedAt.
  final File jsonFile;

  const DataExport({required this.databaseFile, required this.jsonFile});

  List<File> get files => [databaseFile, jsonFile];
}

/// Writes the user's data to files that can be shared or kept outside the
/// app (Files, Drive, WhatsApp...).
///
/// Export only: nothing here reads a file back into the app.
class DataExportService {
  /// Marks a JSON file as a LudoRank export.
  static const format = 'ludorank-export';

  final AppDatabase _database;

  /// Waits for board saves still being written (see DatabaseCheckpointer).
  final Future<void> Function() _waitForPendingSaves;

  /// Where the files are written; the share sheet copies them from there.
  final Future<Directory> Function() _outputDirectory;

  final DateTime Function() _now;

  DataExportService({
    required AppDatabase database,
    required Future<void> Function() waitForPendingSaves,
    required Future<Directory> Function() outputDirectory,
    DateTime Function()? now,
  }) : _database = database,
       _waitForPendingSaves = waitForPendingSaves,
       _outputDirectory = outputDirectory,
       _now = now ?? DateTime.now;

  Future<DataExport> export() async {
    await _waitForPendingSaves();
    await _database.checkpointWal();

    final exportedAt = _now().toUtc();
    final stamp = _fileStamp(exportedAt);

    // One folder for all exports; older ones are removed so the cache
    // does not grow with every export.
    final root = Directory(p.join((await _outputDirectory()).path, 'export'));
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);

    final databaseFile = File(p.join(root.path, 'ludorank-$stamp.db'));
    final jsonFile = File(p.join(root.path, 'ludorank-$stamp.json'));

    // VACUUM INTO writes a compact, self-contained copy (no -wal file) of
    // one consistent snapshot, even while the app keeps the database open.
    await _database.customStatement('VACUUM INTO ?', [databaseFile.path]);

    final data = await buildJson(exportedAt: exportedAt);
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );

    return DataExport(databaseFile: databaseFile, jsonFile: jsonFile);
  }

  /// The JSON content of an export, read in one transaction so the five
  /// lists agree with each other.
  Future<Map<String, Object?>> buildJson({required DateTime exportedAt}) {
    const serializer = _ExportValueSerializer();
    final db = _database;

    List<Map<String, Object?>> json(List<DataClass> rows) {
      return [for (final row in rows) row.toJson(serializer: serializer)];
    }

    return db.transaction(() async {
      final players = json(
        await (db.select(db.players)..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get(),
      );
      final tournaments = json(
        await (db.select(db.tournaments)..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get(),
      );
      final tournamentPlayers = json(
        await (db.select(db.tournamentPlayers)..orderBy([
              (t) => OrderingTerm.asc(t.tournamentId),
              (t) => OrderingTerm.asc(t.joinedAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get(),
      );
      final matches = json(
        await (db.select(db.matches)..orderBy([
              (t) => OrderingTerm.asc(t.tournamentId),
              (t) => OrderingTerm.asc(t.matchNumber),
            ]))
            .get(),
      );
      final matchPlayers = json(
        await (db.select(db.matchPlayers)..orderBy([
              (t) => OrderingTerm.asc(t.matchId),
              (t) => OrderingTerm.asc(t.seat),
            ]))
            .get(),
      );

      return <String, Object?>{
        'format': format,
        'schemaVersion': db.schemaVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'counts': {
          'players': players.length,
          'tournaments': tournaments.length,
          'tournamentPlayers': tournamentPlayers.length,
          'matches': matches.length,
          'matchPlayers': matchPlayers.length,
        },
        'players': players,
        'tournaments': tournaments,
        'tournamentPlayers': tournamentPlayers,
        'matches': matches,
        'matchPlayers': matchPlayers,
      };
    });
  }

  /// 2026-11-27T10:30:05Z -> 20261127-103005
  static String _fileStamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}

/// Drift's default JSON values, with dates as UTC ISO-8601 strings
/// ("2026-11-27T10:30:05.000Z") instead of local time or epoch numbers.
class _ExportValueSerializer extends ValueSerializer {
  const _ExportValueSerializer();

  static const _defaults = ValueSerializer.defaults();

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return _defaults.toJson<T>(value);
  }

  @override
  T fromJson<T>(dynamic json) => _defaults.fromJson<T>(json);
}
