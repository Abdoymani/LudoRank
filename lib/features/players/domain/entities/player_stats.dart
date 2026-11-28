/// A player's record over every finished match (all tournaments).
class PlayerStats {
  final int matches;
  final int wins;
  final int points;

  const PlayerStats({
    required this.matches,
    required this.wins,
    required this.points,
  });

  static const PlayerStats empty = PlayerStats(matches: 0, wins: 0, points: 0);
}
