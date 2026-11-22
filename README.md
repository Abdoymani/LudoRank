# LudoRank

تطبيق موبايل (Flutter) لتنظيم **بطولات لودو** واللعب عليها، **من غير إنترنت**.
بتعمل بطولة، تضيف لاعبين، تلعب المباريات على نفس الموبايل، والتطبيق بيحسب النقاط والترتيب لوحده.

*An offline Flutter app for running Ludo tournaments: create a tournament, add players, play the matches on one device, and LudoRank keeps the points and the leaderboard.*

---

## المميزات

- **لعبة لودو كاملة** لـ 2 أو 3 أو 4 لاعبين على نفس الجهاز (Fast Mode).
- **بطولات:** إنشاء بطولة، إضافة لاعبين، إنشاء مباريات مرقّمة (مباراة رقم 1، 2، 3…).
- **نقاط تلقائية:** نقاط اللاعب = عدد لاعبي المباراة − مركزه + 1 (مثلاً في مباراة 4 لاعبين: 4، 3، 2، 1).
- **ترتيب البطولة** بيتحدّث بعد كل مباراة.
- **حفظ تلقائي:** لو خرجت من المباراة تقدر تكمّلها من مكانها.
- **إلغاء مباراة** و**إنهاء البطولة** يدويًا.
- **أصوات للعبة** (النرد، الـ6، خروج القطعة، الأكل، الوصول للبيت، الفوز) بتشتغل **مع** موسيقى المستخدم من غير ما توقفها، وفيه **زرار كتم صوت** فوق في كل شاشة.
- كل البيانات محفوظة على الجهاز (SQLite)، ومفيش أي اتصال بالإنترنت.

## التقنيات

| الجزء | المستخدم |
| --- | --- |
| الإطار | Flutter 3.44+ (مجرَّب على 3.50) / Dart 3.11+ |
| قاعدة البيانات | Drift (SQLite) |
| إدارة الحالة | Provider |
| حقن الاعتماديات | get_it |
| التنقل | go_router |
| الإعدادات (الثيم والصوت) | shared_preferences |
| الأصوات | audioplayers (ملفات WAV متولّدة بـ `tool/generate_sounds.py`) |

## التشغيل بسرعة

```bash
git clone https://github.com/iso-abdo/LudoRank.git
cd LudoRank
flutter pub get
flutter test          # كل الاختبارات لازم تنجح
flutter run           # تشغيل على موبايل أو محاكي متوصّل
```

بناء APK:

```bash
flutter build apk --release
# الملف: build/app/outputs/flutter-apk/app-release.apk
```

> لو غيّرت جداول قاعدة البيانات أو أي ملف عليه `@DriftDatabase` / `@DriftAccessor`، شغّل:
> `dart run build_runner build --delete-conflicting-outputs`

## هيكل المشروع

```
lib/
  app/                 تطبيق، راوتر، ثيم
  core/
    audio/             الأصوات: GameSound + SoundController (الكتم والتشغيل)
    settings/          AppSettings: الثيم والصوت (shared_preferences)
    database/          Drift: الجداول، المايجريشن، database.dart
    dependency_injection/  تسجيل كل الخدمات (get_it)
  features/
    ludo_game/         محرك اللعبة (domain) + اللوحة والأنيميشن (presentation)
    matches/           المباريات: إنشاء، لعب، حفظ، إنهاء، إلغاء
    tournaments/       البطولات وحالتها والترتيب
    tournament_players/ لاعبو كل بطولة
    players/           اللاعبون
    match_players/     لاعبو كل مباراة ونتايجهم
    home/              الشاشة الرئيسية
test/                  الاختبارات (محرك اللعبة، قاعدة البيانات، البطولات…)
tool/                  سكربتات مساعدة (توليد الأصوات)
docs/                  التوثيق
.github/workflows/     الـ CI
```

كل feature مقسومة لـ `data` / `domain` / `presentation`.
**محرك اللعبة** (`LudoGameEngine`) Dart خالص ومنفصل عن Flutter، وده اللي مسهّل اختباره.

## التوثيق

ابدأ من **[docs/README.md](docs/README.md)**، وفيه:

- [قواعد اللعبة](docs/03_Game_Rules.md)
- [القرارات المتفق عليها](docs/08_Decisions.md) (مثلاً قاعدة الثلاث ستات)
- [سجل التعديلات](docs/09_Changelog.md)
- [إزاي تجرّب](docs/10_Testing_Guide.md)
- [طريقة الشغل كفريق](docs/11_Team_Workflow.md)

## المساهمة

كل Pull Request بيتفحص أوتوماتيك على GitHub Actions (تنسيق الكود، `flutter analyze`، كل الاختبارات، وبناء APK). لازم يبقى أخضر قبل الدمج.

ما حدّش يشتغل على `main` مباشرة: اعمل **branch** لكل حاجة، وافتح **Pull Request**، وخلّي التاني يراجعه.
التفاصيل في [docs/11_Team_Workflow.md](docs/11_Team_Workflow.md).
