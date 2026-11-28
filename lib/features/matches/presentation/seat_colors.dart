import 'package:flutter/material.dart';

/// Board colour of a seat, as the match board deals them: two players
/// get green and blue; three or four get green, yellow, blue, red.
/// Seat 1 is always green and moves first.
Color seatColor(int seat, int playersCount) {
  if (playersCount == 2) {
    return seat == 1 ? Colors.green : Colors.blue;
  }

  return switch (seat) {
    1 => Colors.green,
    2 => Colors.yellow.shade700,
    3 => Colors.blue,
    4 => Colors.red,
    _ => Colors.grey,
  };
}

/// Arabic name of [seatColor].
String seatColorName(int seat, int playersCount) {
  if (playersCount == 2) {
    return seat == 1 ? 'أخضر' : 'أزرق';
  }

  return switch (seat) {
    1 => 'أخضر',
    2 => 'أصفر',
    3 => 'أزرق',
    4 => 'أحمر',
    _ => 'غير محدد',
  };
}

/// Readable text colour on top of [background].
Color onSeatColor(Color background) {
  return background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
}
