import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/domain/entities/player_stats.dart';
import 'package:ludo_rank/features/players/domain/exceptions/duplicate_player_name_exception.dart';
import 'package:ludo_rank/features/players/domain/repositories/player_repository.dart';
import 'package:ludo_rank/features/players/presentation/providers/player_provider.dart';
import 'package:ludo_rank/features/players/presentation/widgets/add_player_dialog.dart';
import 'package:provider/provider.dart';

class _Repository implements PlayerRepository {
  final added = <Player>[];

  @override
  Future<void> addPlayer(Player player) async {
    if (player.name == 'أحمد') throw const DuplicatePlayerNameException();
    added.add(player);
  }

  @override
  Future<List<Player>> getAllPlayers() async => added;

  @override
  Future<Player?> getPlayerById(String id) async => null;

  @override
  Future<void> updatePlayer(Player player) async {}

  @override
  Future<void> deletePlayer(String id) async {}

  @override
  Future<Map<String, PlayerStats>> getPlayerStats() async => const {};
}

void main() {
  testWidgets('a taken name is shown under the field and the dialog stays', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PlayerProvider(repository),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AddPlayerDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'أحمد');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final message = const DuplicatePlayerNameException().message;
    expect(find.text(message), findsOneWidget);
    expect(find.byType(AddPlayerDialog), findsOneWidget);

    // Editing the name clears the error; a free name closes the dialog.
    await tester.enterText(nameField, 'محمود');
    await tester.pump();
    expect(find.text(message), findsNothing);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.byType(AddPlayerDialog), findsNothing);
    expect(repository.added.single.name, 'محمود');
  });

  testWidgets('name, nickname and notes are capped at their max length', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PlayerProvider(_Repository()),
        child: const MaterialApp(home: Scaffold(body: AddPlayerDialog())),
      ),
    );

    final fields = find.byType(TextFormField);
    final limits = [
      Player.maxNameLength,
      Player.maxNicknameLength,
      Player.maxNotesLength,
    ];
    for (var i = 0; i < limits.length; i++) {
      await tester.enterText(fields.at(i), 'ا' * (limits[i] + 15));
      await tester.pump();
      final field = tester.widget<EditableText>(
        find.descendant(of: fields.at(i), matching: find.byType(EditableText)),
      );
      expect(field.controller.text.length, limits[i]);
    }
  });
}
