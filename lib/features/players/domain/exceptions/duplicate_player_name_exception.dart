/// Thrown when a player name is already used by another player once both
/// are normalised (see normalizePlayerName).
class DuplicatePlayerNameException implements Exception {
  const DuplicatePlayerNameException();

  /// Shown to the user.
  String get message =>
      'يوجد لاعب بنفس الاسم بالفعل. '
      'الأسماء اللي بتختلف في الهمزة أو التشكيل أو المسافات أو حالة الحروف '
      'بتتحسب نفس الاسم، اختر اسمًا مختلفًا.';

  @override
  String toString() => 'DuplicatePlayerNameException: $message';
}
