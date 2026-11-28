import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';

class MatchModel extends Match {
  const MatchModel({
    required super.id,
    required super.tournamentId,
    super.matchNumber,
    required super.playersCount,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
  });

  factory MatchModel.fromDrift(MatchData row) {
    return MatchModel(
      id: row.id,
      tournamentId: row.tournamentId,
      matchNumber: row.matchNumber,
      //playersCount: 0,  سيتم حسابها من MatchPlayers
      playersCount: row.playersCount,
      status: parseStatus(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Unknown stored values become [MatchStatus.unknown] instead of
  /// crashing the whole list.
  static MatchStatus parseStatus(String value) {
    for (final status in MatchStatus.values) {
      if (status != MatchStatus.unknown && status.name == value) return status;
    }
    debugPrint('Unknown match status "$value"; shown as unknown.');
    return MatchStatus.unknown;
  }

  factory MatchModel.fromEntity(Match match) {
    return MatchModel(
      id: match.id,
      tournamentId: match.tournamentId,
      matchNumber: match.matchNumber,
      playersCount: match.playersCount,
      status: match.status,
      createdAt: match.createdAt,
      updatedAt: match.updatedAt,
    );
  }

  MatchesCompanion toCompanion() {
    if (status == MatchStatus.unknown) {
      throw StateError('لا يمكن حفظ مباراة حالتها غير معروفة.');
    }

    return MatchesCompanion(
      id: Value(id),
      tournamentId: Value(tournamentId),
      matchNumber: Value(matchNumber),
      playersCount: Value(playersCount),
      status: Value(status.name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }
}
