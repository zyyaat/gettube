<div align="center">

# 📥 GetTube

**نزّل أي فيديو بأي جودة — مجاناً للأبد. بدون إعلانات. بدون اشتراكات.**
**Download any video in any quality — free forever. No ads. No paywalls.**

Flutter • Open Source • كل جودات يوتيوب (144p → 8K) • All YouTube qualities unlocked

[![Export APK](https://github.com/zyyaat/gettube/actions/workflows/export.yml/badge.svg)](https://github.com/zyyaat/gettube/actions/workflows/export.yml)
[![Latest APK](https://img.shields.io/badge/⬇️_Download-arm32_APK-red)](https://github.com/zyyaat/gettube/releases/latest)

</div>

---

## 📦 حمّل الـ APK الجاهز / Grab the ready APK

كل push على `main` بيتبنى تلقائياً على GitHub Actions ويُنشر كـ **Release** — مش محتاج تبني بنفسك:

> Every push to `main` is built automatically and published as a GitHub Release (arm32 / armeabi-v7a):

**→ [آخر إصدار / Latest release](https://github.com/zyyaat/gettube/releases/latest)** — نزّل ملف `GetTube-arm32-r*.apk` وثبّته على أي موبايل أندرويد (ARM 32-bit أو أعلى).

---

## 🇪🇬 ليه GetTube؟

تطبيقات التحميل المشهورة (زي سناب تيوب) بتعرض عليك تجربة مليانة إعلانات، والجودات العالية (HD/4K) غالباً وراء اشتراك بريميوم. GetTube اتولد لعكس المعادلة بالكامل:

| | سناب تيوب وغيره | **GetTube** |
|---|---|---|
| الجودات | HD/4K خلف اشتراك مدفوع | **كل جودة يوتيوب يقدمها حرفياً (حتى 8K) مجاناً** |
| الإعلانات | عدوانية (بانرز + فول سكرين) | **صفر إعلانات، للأبد** |
| الخصوصية | تراكرات وتاريخ أمني مثير للجدل | **لا حسابات، لا تتبع، كود مفتوح للمراجعة** |
| المعالجة | جودات عالية مدفوعة | **دمج تلقائي للفيديو+الصوت بـ FFmpeg بدون فقدان جودة** |
| المصدر | مغلق | **مفتوح 100% — MIT License** |

### ✨ المميزات
- 🔍 **بحث يوتيوب مدمج** — أو الصق رابط فيديو مباشرة
- 🎚️ **كل الجودات المتاحة حرفياً**: 144p → 8K (4320p) مع عرض الحجم الفعلي لكل جودة
- 🎬 **دمج تلقائي (DASH)**: يوتيوب بيقدم الجودات العالية كـ فيديو وصوت منفصلين — GetTube بينزّل الاتنين ويدمجهم بـ **FFmpeg** (نسخ بدون إعادة ترميز = نفس الجودة الأصلية 100%)
- 🎵 **الصوت فقط**: M4A (AAC) / OPUS أو **تحويل MP3 192kbps**
- ⏸️ **وقفة / استكمال** حقيقي عبر HTTP Range — حتى بعد قفل التطبيق
- 🚀 **تنزيلات متوازية** (حتى 4 في نفس الوقت) + عرض السرعة اللحظية
- 📂 **حفظ في مجلد التنزيلات العام** (MediaStore على أندرويد 10+) — الملفات تظهر في المعرض وتطبيق الملفات
- 🌙 واجهة Material 3 + **عربي/English** + وضع داكن
- 🔔 إشعار اكتمال التنزيل
- 🛡️ صلاحيات أقل حاجة ممكنة — مفيش أي شيء بيتجمع أو بيتتبع

---

## 🇬🇧 Why GetTube?

Popular downloader apps (like SnapTube) wrap their experience in ads and often gate HD/4K quality behind a premium subscription. GetTube flips the equation: **every quality YouTube serves — including 4K and 8K — is free**, downloads are resumable, and the code is fully open source (MIT).

### Features
- Built-in YouTube search (or paste any link)
- **Every available stream** (144p → 8K) with real file sizes, no paywall
- **Automatic DASH muxing** via FFmpeg (stream copy — zero quality loss)
- Audio-only: M4A / Opus / **MP3 (192kbps) conversion**
- Real pause/resume via HTTP Range + parallel queue (up to 4)
- Saves to the **public Downloads folder** via MediaStore (Android 10+)
- Material 3 UI, Arabic/English, dark mode, completion notifications

---

## 🏗️ المعمارية التقنية / Tech Stack

| الطبقة / Layer | التقنية |
|---|---|
| UI | Flutter + Material 3 (Provider state management) |
| YouTube parsing | [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) — full stream manifest, no API key |
| Download engine | Custom queue on `dio` — resumable (Range), parallel, retry-safe `.part` files |
| Muxing / MP3 | [`ffmpeg_kit_flutter_new`](https://pub.dev/packages/ffmpeg_kit_flutter_new) (Full-GPL, stream copy) |
| Public storage | Platform channel → `MediaStore.Downloads` (Android 10+) / direct write (9-) |
| Notifications | `flutter_local_notifications` |

```
lib/
├── main.dart                    # App shell + bottom navigation + theme
├── core/                        # constants, i18n (ar/en), formatters
├── models/                      # QualityOption, DownloadTask, SavedFile
├── services/
│   ├── youtube_service.dart     # search + manifest → all quality options
│   ├── download_manager.dart    # the queue engine (pause/resume/mux)
│   ├── media_service.dart       # FFmpeg mux + MP3 conversion
│   ├── storage_service.dart     # MediaStore publish + saved registry
│   └── notification_service.dart
├── state/settings_controller.dart
├── screens/                     # home (search), video, downloads, settings
└── widgets/                     # video_card, quality_sheet, download_tile
android_patch/                   # manifest permissions + MainActivity (MediaStore channel)
tool/setup_android.sh            # one-time scaffolding script
```

---

## 🚀 التشغيل / Getting Started

**المتطلبات:** Flutter 3.22+ (Dart 3.4+)، Android SDK 24+

```bash
git clone https://github.com/YOUR_USERNAME/gettube.git
cd gettube

# 1) one-time: generate the android/ folder + apply permissions & platform channel
./tool/setup_android.sh

# 2) run
flutter pub get
flutter run

# 3) release APK
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

> 💡 لو `setup_android.sh` فشل في تعديل minSdk، افتح `android/app/build.gradle(.kts)` يدوياً وخلّي `minSdk = 24` (مطلوب من مكتبة FFmpeg).
>
> 💡 If Gradle asks for NDK or shows codec warnings, just accept defaults — FFmpeg binaries ship prebuilt.

---

## ☁️ الرفع على GitHub / Publishing

### التصدير التلقائي / Auto-export (مفعّل ✅)
الريبو فيه workflow جاهز: `.github/workflows/export.yml` — على كل `git push` لفرع `main`:
1. يبني APK **arm32 (armeabi-v7a)** نسخة release
2. ينشره في **GitHub Releases** (tag `build-<رقم>`) — بدون استهلاك مساحة Actions
3. يرفع artifact إضافي مدة صلاحيتك 7 أيام

```bash
git push origin main        # البناء يبدأ تلقائياً
# تابع: Actions → Export APK → Release جاهز بعد ~10 دقائق
```

### يدوياً / Manual build

```bash
cd gettube
git init
git add -A
git commit -m "GetTube v1.0 — free YouTube downloader, all qualities, zero ads"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/gettube.git
git push -u origin main
```

للتوزيع: اعمل **GitHub Releases** وارفع ملف `app-release.apk` — نفس نموذج توزيع سناب تيوب (APK مباشر، غير متاح على Google Play بسبب سياسات يوتيوب).

For distribution: build the release APK and attach it to a GitHub Release. YouTube-downloaders cannot be listed on Google Play (same as every app in this category) — APK distribution is the norm.

---

## ⚖️ استخدام مسؤول / Responsible Use

استخدم GetTube لتنزيل المحتوى المسموح به وللاستخدام الشخصي فقط، واحترم حقوق أصحاب المحتوى وشروط المنصات. المشروع مفتوح المصدر لأغراض تعليمية وتنموية، ولا علاقة له بمطوري أي تطبيق آخر.

Use GetTube only to download permitted content for personal use and respect creators' rights and platform terms. This project is open source for educational purposes and is not affiliated with any other app or its developers.

---

## 🗺️ خارطة الطريق / Roadmap

- [ ] دعم قوائم التشغيل (Playlists) والتنزيل الجماعي
- [ ] خزنة خاصة للملفات (Vault) قابلة للقفل
- [ ] مشغل فيديو مدمج
- [ ] دعم منصات إضافية (البنية جاهزة للتوسيع)
- [ ] Windows / macOS desktop builds
- [ ] أسماء ملفات مخصصة وقوالب تسمية

## 📜 License

MIT — انظر [LICENSE](LICENSE)
