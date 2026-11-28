/// The form of a player name used to detect duplicates.
///
/// Two names are the same player name when their normalised forms are
/// equal: case, hamza forms of alef, alef maqsura, taa marbuta, tashkeel,
/// tatweel and repeated or surrounding spaces are ignored. So "أحمد",
/// "احمد" and "إحْمَد " clash, and so do "Ali" and "ali".
///
/// Stored in `players.normalized_name`, which is unique. The function is
/// idempotent: normalising a normalised name returns it unchanged (the
/// schema-6 migration relies on that).
String normalizePlayerName(String name) {
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    if (_isStripped(rune)) continue;
    buffer.writeCharCode(_replacements[rune] ?? rune);
  }
  return buffer.toString().trim().replaceAll(_whitespace, ' ');
}

final _whitespace = RegExp(r'\s+');

const _replacements = <int, int>{
  0x0623: 0x0627, // أ -> ا
  0x0625: 0x0627, // إ -> ا
  0x0622: 0x0627, // آ -> ا
  0x0649: 0x064A, // ى -> ي
  0x0629: 0x0647, // ة -> ه
};

bool _isStripped(int rune) {
  return rune == 0x0640 || // tatweel
      (rune >= 0x064B && rune <= 0x065F) || // tashkeel (harakat, shadda...)
      rune == 0x0670; // superscript alef
}
