# طريقة الشغل كفريق

## ريبو واحد أساسي

- **الأساسي:** `iso-abdo/LudoRank`، وفرع `main` فيه هو المرجع.
- أي نسخة تانية (fork) زي `Abdoymani/LudoRank` تتحدّث من الأساسي، والتعديلات ترجع له بـ Pull Request.

## الخطوات لكل شغلانة

1. **اسحب آخر تحديث قبل ما تبدأ:**
   ```bash
   git checkout main
   git pull origin main
   ```
   (لو شغال من fork: `git fetch upstream && git merge upstream/main`. ولأول مرة بس: `git remote add upstream https://github.com/iso-abdo/LudoRank.git`)
2. **اعمل branch باسم واضح:**
   ```bash
   git checkout -b fix/tournament-tiebreak
   ```
   أمثلة: `fix/...` للإصلاح، و`feat/...` لميزة جديدة، و`docs/...` للتوثيق.
3. **اشتغل وشغّل الاختبارات** قبل الـ commit: `flutter test` و`flutter analyze`.
4. **commit برسالة بتشرح** اتعمل إيه وليه.
5. **ارفع وافتح Pull Request** على `main`، واكتب فيه اتعمل إيه وجربته إزاي.
6. **التاني يراجع** ويجرّب، وبعدها merge.
7. سطر في [09_Changelog.md](09_Changelog.md) لو التعديل مهم.

## قواعد تقلل المشاكل

- **ما حدّش يعمل push على `main` مباشرة.**
- **اتفقوا مين ماسك إيه** (مثلاً واحد على قاعدة البيانات والمحرك، والتاني على الشاشات). كده الـ conflicts بتقل.
- **PR صغير أحسن من PR كبير.** بيتراجع أسرع وأسهل ترجع فيه.
- **قاعدة البيانات:** أي تغيير في الجداول لازم:
  1. ترفع `schemaVersion` في `database.dart`.
  2. تكتب migration في `onUpgrade`.
  3. تشغّل `dart run build_runner build --delete-conflicting-outputs`.
  4. تكتب اختبار migration (شوف `test/core/database/schema_v5_test.dart` لأبسط مثال).
  ولو ما عملتش كده، الموبايلات اللي عليها النسخة القديمة هتقع.
- **قواعد اللعبة:** أي تغيير لازم يتكتب في [08_Decisions.md](08_Decisions.md) ويكون عليه اختبار.
- **ما ترفعش** ملفات `build/` ولا مفاتيح التوقيع (`key.properties`، `*.jks`).

## لو حصل conflict

```bash
git checkout my-branch
git fetch origin
git merge origin/main      # حل التعارضات في الملفات، وبعدين:
git add .
git commit
flutter test               # اتأكد إن كله لسه شغال
git push
```
