import 'package:drift/drift.dart';

class Players extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().unique()();

  /// The name as normalizePlayerName returns it. Unique, so two players
  /// cannot differ only by case, hamza, tashkeel or spacing.
  TextColumn get normalizedName => text().unique()();

  TextColumn get nickname => text().nullable()();

  TextColumn get avatar => text().nullable()();

  TextColumn get notes => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
