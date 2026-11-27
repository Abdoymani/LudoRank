import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/features/backup/data/data_export_service.dart';
import 'package:ludo_rank/features/backup/presentation/widgets/export_data_button.dart';

class _FakeService extends DataExportService {
  final bool fail;
  int calls = 0;

  _FakeService(AppDatabase db, {this.fail = false})
    : super(
        database: db,
        waitForPendingSaves: () async {},
        outputDirectory: () async => Directory.systemTemp,
      );

  @override
  Future<DataExport> export() async {
    calls++;
    if (fail) throw const FileSystemException('disk full');
    return DataExport(databaseFile: File('a.db'), jsonFile: File('a.json'));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget button) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(actions: [button])),
      ),
    );
  }

  testWidgets('exports, then opens the share sheet with both files', (
    tester,
  ) async {
    final service = _FakeService(db);
    final shared = <DataExport>[];
    await pump(
      tester,
      ExportDataButton(
        service: () => service,
        share: (export, origin) async => shared.add(export),
      ),
    );

    await tester.tap(find.byTooltip('تصدير البيانات'));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(shared.single.files.map((f) => f.path), ['a.db', 'a.json']);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed export shows a message', (tester) async {
    var shareCalls = 0;
    await pump(
      tester,
      ExportDataButton(
        service: () => _FakeService(db, fail: true),
        share: (export, origin) async => shareCalls++,
      ),
    );

    await tester.tap(find.byTooltip('تصدير البيانات'));
    await tester.pumpAndSettle();

    expect(shareCalls, 0);
    expect(find.text('تعذر تصدير البيانات، حاول مرة أخرى'), findsOneWidget);
  });
}
