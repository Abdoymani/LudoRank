import 'package:equatable/equatable.dart';

class Player extends Equatable {
  /// Input limits for the add-player form. Longer names break list
  /// layouts and are cut on the match board anyway.
  static const int maxNameLength = 30;
  static const int maxNicknameLength = 20;
  static const int maxNotesLength = 200;

  final String id;
  final String name;
  final String? nickname;
  final String? avatar;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Player({
    required this.id,
    required this.name,
    this.nickname,
    this.avatar,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Player copyWith({
    String? id,
    String? name,
    String? nickname,
    String? avatar,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    nickname,
    avatar,
    notes,
    isActive,
    createdAt,
    updatedAt,
  ];
}
