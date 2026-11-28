import 'package:flutter/material.dart';
import 'package:ludo_rank/features/players/domain/exceptions/duplicate_player_name_exception.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/presentation/providers/player_provider.dart';

/// Adds a player, or edits [player] (name, nickname, notes) when given.
class AddPlayerDialog extends StatefulWidget {
  final Player? player;

  const AddPlayerDialog({super.key, this.player});

  @override
  State<AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<AddPlayerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController(text: widget.player?.name);
  late final _nicknameController = TextEditingController(
    text: widget.player?.nickname,
  );
  late final _notesController = TextEditingController(
    text: widget.player?.notes,
  );

  bool get _editing => widget.player != null;

  /// Shown under the name field when the name is already taken.
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // A taken name stays flagged until the user edits it (onChanged).
    if (_saving || _nameError != null) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<PlayerProvider>();

    final existing = widget.player;
    final now = DateTime.now();
    final player = Player(
      id: existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      nickname: _nicknameController.text.trim().isEmpty
          ? null
          : _nicknameController.text.trim(),
      avatar: existing?.avatar,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    try {
      if (_editing) {
        await provider.updatePlayer(player);
      } else {
        await provider.addPlayer(player);
      }

      if (!mounted) return;

      Navigator.pop(context);
    } on DuplicatePlayerNameException catch (e) {
      if (!mounted) return;

      // Inline, next to the field, so the dialog stays open for a fix.
      setState(() => _nameError = e.message);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? 'تعذر حفظ اللاعب، حاول مرة أخرى'
                : 'تعذر إضافة اللاعب، حاول مرة أخرى',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'تعديل اللاعب' : 'إضافة لاعب'),

      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: !_editing,
                maxLength: Player.maxNameLength,
                decoration: const InputDecoration(
                  labelText: 'اسم اللاعب',
                  errorMaxLines: 4,
                ),
                forceErrorText: _nameError,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الاسم مطلوب';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _nicknameController,
                maxLength: Player.maxNicknameLength,
                decoration: const InputDecoration(labelText: 'اللقب'),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                maxLength: Player.maxNotesLength,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('إلغاء'),
        ),

        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
