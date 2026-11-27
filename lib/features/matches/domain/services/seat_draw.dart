import 'dart:math';

/// Seat draw ("قرعة المقاعد"): returns [players] in a random seat order,
/// index 0 being seat 1.
///
/// Seat 1 is always green and moves first, so the draw is what decides
/// who starts. The app passes `Random.secure()`; tests pass a seeded one.
List<T> drawSeats<T>(Iterable<T> players, Random random) {
  return players.toList()..shuffle(random);
}
