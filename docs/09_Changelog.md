# سجل التعديلات

الأحدث فوق. كل بند: اتعمل إيه، وليه، والملفات الأساسية.

---

## 2026-11-22: الأصوات، المكتبات، تنظيف الكود، وCI

### 1. الأصوات
- **المشكلة:** صوت خطوة القطعة كان بيطلب audio focus، فكان بيوقف أي موسيقى شغالة عند المستخدم (Spotify، YouTube…). ومفيش زرار كتم صوت، وكل خطوة كانت بتعمل `stop()` وبعدين `play()`، فكان فيه تقطيع.
- **الإصلاح:** `SoundController` جديد في `lib/core/audio/`:
  - على أندرويد مش بيطلب audio focus (`AndroidAudioFocus.none`، `usage = game`)، وعلى iOS بيستخدم `ambient`. يعني الأصوات بتشتغل **مع** موسيقى المستخدم، وفي iOS بتحترم زرار الصامت.
  - وضع `lowLatency`، و3 players لكل صوت، فالخطوات السريعة ورا بعض مش بتقطع بعضها.
  - **زرار كتم صوت** (🔊/🔇) في الـ AppBar بتاع كل الشاشات وشاشة المباراة، والاختيار بيتحفظ.
- **أصوات جديدة (8):** خطوة، رمي النرد، 6، خروج قطعة من البيت، أكل، وصول للبيت، إلغاء الدور (تالت 6)، فوز. كلها متولّدة بالكود (`tool/generate_sounds.py`)، يعني مفيش أي حقوق ملكية لحد تاني. ولو عايز تعدّل صوت: عدّل السكربت وشغّل `python3 tool/generate_sounds.py assets/audio`.
- **مين بيشغّل إيه:** `GameSoundEvents` (`lib/features/matches/presentation/providers/game_sound_events.dart`) بيقارن حالة اللعبة قبل وبعد الرمية أو الحركة ويقرر الصوت. اللوحة بتشغّل صوت الخطوة بس.
- **اختبارات:** `test/features/matches/presentation/providers/game_sound_events_test.dart` و`test/core/audio/sound_controller_test.dart`.

### 2. المكتبات
- **`hive` و`hive_flutter` اتشالوا.** كانوا مستخدمين لحفظ الثيم بس، واتبدلوا بـ `shared_preferences` (من فريق Flutter) عن طريق `AppSettings` (`lib/core/settings/app_settings.dart`). **ملاحظة:** اختيار الثيم القديم مش بيتنقل، فأول مرة بعد التحديث الثيم بيرجع "حسب النظام" لحد ما المستخدم يختار تاني. ومفيش أي تأثير على البطولات والمباريات، لأنها في قاعدة البيانات.
- **`sqlite3_flutter_libs` اتشالت.** Drift 2.35 بيستخدم `sqlite3` 3.x، وده بينزّل مكتبة SQLite الأصلية لوحده (build hooks)، فالمكتبة القديمة بقت ملهاش لازمة وآخر نسخة منها مكتوب عليها EOL. ملف قاعدة البيانات ومكانه زي ما هم.

### 3. تنظيف الكود
- اتمسح 62 ملف Dart مش مستخدمين (حوالي 3,600 سطر): البروتوتايب القديم للوحة (`ludo_board.dart`، `prototype/`، `ludo_match_prototype_page.dart`، و`ludo_match_prototype_main.dart` اللي كان متكرر مرتين)، و`ludo_match_footer.dart`، وحوالي 30 use-case مش مستخدمين، و18 ملف فاضي في `config/` و`core/theme/` و`core/tournament_engine/`.
- اتمسح كمان: `ludorank_move_animation_fix.patch`، و`Untitled Folder/`، و`lib/README_AR.md`، و`assets/images/branding/splash_reference.png`، و`assets/audio/ludorank_token_step.mp3` (اتبدل بالأصوات الجديدة).
- `dart format` على 4 ملفات كانوا مش متنسقين.

### 4. CI
- `.github/workflows/ci.yml`: مع كل Pull Request وكل push على `main` بيتعمل فحص للتنسيق (`dart format`)، و`flutter analyze` (الـ infos مش بتفشّله)، و`flutter test`، وبعدها بناء APK (debug) بيترفع كـ artifact لمدة 7 أيام.
- الـ CI متثبّت على Flutter **3.47.9**، لأن 3.50 بيرفض يبني أندرويد بـ Gradle 8.14 اللي في المشروع (محتاج 9.3.1). أول ما Gradle يترقّى، غيّر `flutter-version` في الـ workflow.

---

## 2026-11-22: إضافة لاعبين للبطولة الجارية

- اتقرر إن إضافة لاعبين للبطولة وهي جارية **مسموحة** (زي 02). الكود كان بيسمح أصلاً، فاتضاف اختبار يثبّت ده، واتعدل سطر في 01 عشان ما يتعارضش.

## 2026-11-22: توثيق

- README جديد بالعربي (مع سطر إنجليزي) فيه الفكرة والتشغيل والهيكل.
- فولدر `docs/` اتنظم: فهرس، قواعد اللعبة، الفحص، القرارات، السجل ده، دليل التجربة، وطريقة الشغل كفريق.

## 2026-11-21: المرحلة 1 من خطة الفحص

### 1. باج خانة 51 (محرك اللعبة)

- **المشكلة:** قطعة واقفة على خانة 51 في الدورة الرئيسية (يعني عدّت مدخل البيت)، ولما اللاعب ياكل أول مرة بقطعة تانية، القطعة دي كانت بتتحرك على خانة 52 **جوه البيت** على طول.
- **الإصلاح:** القطعة دي بقت تكمّل لفة كاملة (51 ← 0 ← … ← 50 ← 51 بيت). القرار بيتاخد من **مكان** القطعة، فالمباريات المحفوظة القديمة بتشتغل صح كمان.
- **الملفات:** `ludo_paths.dart` (دالة `isParkedOnMainLoopEnd`)، `ludo_game_engine.dart`، `ludo_match_board.dart` (مسار الأنيميشن).
- **اختبار:** `test/features/ludo_game/engine_regressions_test.dart`. بيفشل على الكود القديم وبينجح بعد الإصلاح.
- **كمان:** اختبار بيثبّت قاعدة الثلاث ستات المقصودة (من غير ما يغيّرها).

### 2. قاعدة البيانات: schema v4

- **الفهارس بقت بتتعمل فعلاً:** الطريقة القديمة (`List<Index> get indexes`) Drift كان بيتجاهلها. اتحولت لـ `@TableIndex`.
- **`tournament_players`:** بقى ليه `PRIMARY KEY (id)` وفهرس فريد على `(tournament_id, player_id)`، فنفس اللاعب ما ينفعش يتضاف للبطولة مرتين.
- **`matches`:** رقم المباراة بقى حقيقي (1، 2، 3… لكل بطولة) وبيتحط تلقائيًا في `MatchDao.insertMatch`، وعليه فهرس فريد.
- **المفاتيح الأجنبية اتفعّلت** (`PRAGMA foreign_keys = ON` في `beforeOpen`).
- **المسح:** `deleteMatch` و`deleteTournament` بيمسحوا الصفوف التابعة معاهم في transaction.
- **الـ migration من v3 لـ v4** (`database.dart` → `_migrateTo4`):
  1. بتمسح التكرار القديم في `tournament_players` وبتسيب أقدم صف.
  2. بتعيد بناء الجدول بالـ primary key.
  3. بترقّم المباريات القديمة بترتيب إنشائها.
  4. بتعمل كل الفهارس.
- **الواجهة:** شاشة اختيار اللاعبين بتخبّي اللي متسجلين في البطولة خلاص، ولو حصل تكرار بتطلع رسالة مفهومة.
- **اختبارات:** `test/core/database/schema_v4_test.dart` (قاعدة جديدة + migration حقيقية من v3 فيها تكرار).

### 3. حالة البطولة وإلغاء المباراة

- **`TournamentLifecycleService`** (`tournaments/domain/services/`):
  - أول مباراة بتتعمل: البطولة من مسودة لـ **جارية**.
  - زرار **"إنهاء البطولة"** في صفحة البطولة: من جارية لـ **منتهية** (بالشروط اللي في [08_Decisions.md](08_Decisions.md)).
  - البطولة المنتهية أو الملغية ترفض مباريات ولاعبين جداد.
- **`CancelMatch`** (`matches/domain/Use-cases/cancel_match.dart`): زرار **"إلغاء"** على المباراة اللي لسه ما بدأتش أو اللي شغالة، بيسأل تأكيد، وبيمسح الحالة المحفوظة.
- **قايمة المباريات** بتعرض "مباراة رقم N" ومرتبة بالرقم.
- **صفحة البطولة** بتحدّث الحالة والترتيب لما ترجع من صفحة المباريات.
- **اختبارات:** `test/features/tournaments/domain/services/tournament_lifecycle_test.dart`.

**النتيجة:** 146 اختبار ناجحين (121 قدام + 25 جداد). `flutter analyze` ما طلعش أي مشكلة جديدة.
**الـ PR:** https://github.com/Abdoymani/LudoRank/pull/1

## قبل كده

- `fix/move-animation-lifecycle`: إصلاح دورة حياة أنيميشن الحركة (اتدمج في `main`، الـ commit رقم `1d5d5ce`).
