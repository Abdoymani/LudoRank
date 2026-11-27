enum MatchStatus {
  pending,
  playing,
  finished,
  cancelled,

  /// Read-only placeholder for a stored status this app version does not
  /// know (damaged row or a newer app). It is never written: every write
  /// path rejects it, so the original value stays in the database.
  unknown,
}
