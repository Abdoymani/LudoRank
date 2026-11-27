import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/features/matches/domain/services/seat_draw.dart';

void main() {
  test('keeps every player once and does not touch the input', () {
    final players = ['a', 'b', 'c', 'd'];
    final seats = drawSeats(players, Random(7));

    expect(seats, unorderedEquals(players));
    expect(players, ['a', 'b', 'c', 'd']);
  });

  test('the same seed gives the same draw', () {
    final players = ['a', 'b', 'c', 'd'];

    expect(drawSeats(players, Random(3)), drawSeats(players, Random(3)));
  });

  test('every player gets seat 1 about equally often', () {
    final random = Random(42);
    final firstSeat = <String, int>{};
    const draws = 8000;

    for (var i = 0; i < draws; i++) {
      final seats = drawSeats(['a', 'b', 'c', 'd'], random);
      firstSeat.update(seats.first, (n) => n + 1, ifAbsent: () => 1);
    }

    expect(firstSeat.keys, unorderedEquals(['a', 'b', 'c', 'd']));
    for (final count in firstSeat.values) {
      expect(count, inInclusiveRange(draws ~/ 4 - 200, draws ~/ 4 + 200));
    }
  });
}
