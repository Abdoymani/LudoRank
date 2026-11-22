import '../constants/ludo_paths.dart';
import '../entities/ludo_token.dart';
import '../entities/position.dart';

/// خطوة واحدة في حركة قطعة.
///
/// الرقم 51 لوحده مش كفاية: ممكن يكون Main Loop أو Home Lane،
/// عشان كده بنرجّع [useHomeLane] و[position] مع كل خطوة.
class LudoPathStep {
  final int step;
  final bool useHomeLane;
  final Position position;

  const LudoPathStep({
    required this.step,
    required this.useHomeLane,
    required this.position,
  });
}

/// المصدر الوحيد لحساب مسار حركة قطعة خطوة بخطوة.
///
/// المحرك بيستخدمه عشان يعرف مكان الوصول، وأنيميشن اللوحة بيستخدمه
/// عشان يرسم نفس الطريق بالظبط. ما تكررش المنطق ده في أي مكان تاني.
class LudoMoveTracer {
  const LudoMoveTracer._();

  /// بيرجّع كل الخانات اللي القطعة هتعدّي عليها (من غير خانة البداية)،
  /// وآخر عنصر هو مكان الوصول.
  ///
  /// بيرجّع null لو الحركة مش ممكنة (بتعدّي خانة النهاية، أو القطعة
  /// مش على المسار).
  static List<LudoPathStep>? trace({
    required LudoPath path,
    required bool hasCaptured,
    required LudoToken token,
    required int steps,
  }) {
    if (steps <= 0) {
      return null;
    }

    if (token.positionInPath < 0 ||
        token.positionInPath > LudoPath.finishStep) {
      return null;
    }

    var step = token.positionInPath;

    // قطعة واقفة فعليًا على خانة 51 في الـ Main Loop
    // (مش 51 Home Lane) تكون عدّت مدخل الـ Home Lane خلاص.
    // لو اللاعب أكل أول مرة بقطعة تانية بعد كده،
    // القطعة دي لازم تكمّل الدورة: 51(Main) -> 0 -> ... -> 50 -> 51(Home)
    var homeEntryPending =
        token.homeEntryPending ||
        path.isParkedOnMainLoopEnd(
          step: token.positionInPath,
          position: token.position,
        );

    final result = <LudoPathStep>[];

    for (var i = 0; i < steps; i++) {
      // Finish نقطة نهائية ولا يمكن تجاوزها.
      if (step == LudoPath.finishStep) {
        return null;
      }

      // قبل الأكل: 51 = Main Loop.
      // بعد الأكل: 51 = Home Lane،
      // إلا لو القطعة نفسها على 51 Main ومعاها homeEntryPending،
      // ساعتها: 51(Main) -> 0.
      final useHomeLane =
          hasCaptured &&
          !(homeEntryPending && step == LudoPath.lastMainLoopStep);

      final nextStep = path.nextStep(
        currentStep: step,
        useHomeLane: useHomeLane,
      );

      final nextUsesHomeLane =
          useHomeLane && nextStep >= LudoPath.homeLaneStartStep;

      // أول ما توصل 51 Home Lane تكون كمّلت اللفة المطلوبة.
      if (nextUsesHomeLane && nextStep == LudoPath.homeLaneStartStep) {
        homeEntryPending = false;
      }

      step = nextStep;

      result.add(
        LudoPathStep(
          step: step,
          useHomeLane: nextUsesHomeLane,
          position: path.positionAt(step: step, useHomeLane: nextUsesHomeLane),
        ),
      );
    }

    return result;
  }
}
