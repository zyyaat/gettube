/// Lightweight in-app localization (Arabic default + English).
/// No code-generation needed; toggleable from Settings.
enum AppLang { arabic, english }

extension AppLangX on AppLang {
  String get code => this == AppLang.arabic ? 'ar' : 'en';
  String get displayName => this == AppLang.arabic ? 'العربية' : 'English';
}

class L {
  L._();

  static AppLang lang = AppLang.arabic;
  static bool get _ar => lang == AppLang.arabic;

  // ---- General ----
  static String get appName => 'GetTube';
  static String get ok => _ar ? 'حسناً' : 'OK';
  static String get cancel => _ar ? 'إلغاء' : 'Cancel';
  static String get delete => _ar ? 'حذف' : 'Delete';
  static String get retry => _ar ? 'إعادة المحاولة' : 'Retry';
  static String get error => _ar ? 'خطأ' : 'Error';
  static String get free => _ar ? 'مجاني' : 'Free';
  static String get open => _ar ? 'فتح' : 'Open';

  // ---- Home / search ----
  static String get searchHint => _ar ? 'ابحث على يوتيوب أو الصق رابطاً…' : 'Search YouTube or paste a link…';
  static String get search => _ar ? 'بحث' : 'Search';
  static String get recentSearches => _ar ? 'أحدث عمليات البحث' : 'Recent searches';
  static String get clearAll => _ar ? 'مسح الكل' : 'Clear all';
  static String get noResults => _ar ? 'لا توجد نتائج' : 'No results found';
  static String get loadMore => _ar ? 'تحميل المزيد' : 'Load more';
  static String get heroTagline => _ar ? 'نزّل أي فيديو بأي جودة — مجاناً للأبد' : 'Download any video in any quality — free forever';
  static String get featAllQualities => _ar ? 'كل الجودات حتى 8K' : 'All qualities up to 8K';
  static String get featNoAds => _ar ? 'بدون إعلانات' : 'Zero ads';
  static String get featNoPaywall => _ar ? 'بدون اشتراكات' : 'No paywall';
  static String get invalidLink => _ar ? 'الرابط غير صالح' : 'Invalid link';

  // ---- Video screen ----
  static String get downloadVideo => _ar ? 'تنزيل فيديو' : 'Download video';
  static String get downloadAudio => _ar ? 'تنزيل صوت' : 'Download audio';
  static String get openInYouTube => _ar ? 'فتح في يوتيوب' : 'Open in YouTube';
  static String get views => _ar ? 'مشاهدة' : 'views';
  static String get loadingQualities => _ar ? 'جاري تحليل الجودات المتاحة…' : 'Analyzing available qualities…';
  static String get qualitiesFailed => _ar ? 'تعذر جلب الجودات، حاول مرة أخرى' : 'Could not fetch qualities, try again';
  static String get viewsAndDate => _ar ? 'نشر' : 'Published';

  // ---- Quality sheet ----
  static String get chooseQuality => _ar ? 'اختر الجودة' : 'Choose quality';
  static String get sectionReady => _ar ? 'فيديو + صوت (جاهز فوراً)' : 'Video + audio (instant)';
  static String get sectionHigh => _ar ? 'جودات عالية — دمج تلقائي' : 'High quality — auto muxed';
  static String get sectionAudio => _ar ? 'الصوت فقط' : 'Audio only';
  static String get autoMuxNote => _ar ? 'يتم دمج الفيديو والصوت تلقائياً بعد التنزيل' : 'Video and audio are merged automatically after download';
  static String get recommended => _ar ? 'الأفضل' : 'Best';
  static String get downloadStarted => _ar ? 'بدأ التنزيل ✓' : 'Download started ✓';

  // ---- Downloads ----
  static String get downloads => _ar ? 'التنزيلات' : 'Downloads';
  static String get activeDownloads => _ar ? 'جاري التنزيل' : 'In progress';
  static String get savedFiles => _ar ? 'الملفات المحفوظة' : 'Saved files';
  static String get noDownloads => _ar ? 'لا توجد تنزيلات بعد' : 'No downloads yet';
  static String get noSavedFiles => _ar ? 'لم يتم حفظ ملفات بعد' : 'No saved files yet';
  static String get queued => _ar ? 'في الانتظار' : 'Queued';
  static String get preparing => _ar ? 'تحضير…' : 'Preparing…';
  static String get downloading => _ar ? 'جاري التنزيل' : 'Downloading';
  static String get processing => _ar ? 'معالجة ودمج…' : 'Processing & muxing…';
  static String get paused => _ar ? 'متوقف مؤقتاً' : 'Paused';
  static String get completed => _ar ? 'اكتمل' : 'Completed';
  static String get failed => _ar ? 'فشل' : 'Failed';
  static String get canceled => _ar ? 'ملغي' : 'Canceled';
  static String get pause => _ar ? 'إيقاف مؤقت' : 'Pause';
  static String get resume => _ar ? 'استكمال' : 'Resume';
  static String get fileDeleted => _ar ? 'تم حذف الملف' : 'File deleted';
  static String get fileMissing => _ar ? 'الملف غير موجود' : 'File not found';
  static String get refresh => _ar ? 'تحديث' : 'Refresh';

  // ---- Settings ----
  static String get settings => _ar ? 'الإعدادات' : 'Settings';
  static String get appearance => _ar ? 'المظهر' : 'Appearance';
  static String get language => _ar ? 'اللغة' : 'Language';
  static String get theme => _ar ? 'الوضع' : 'Theme';
  static String get themeSystem => _ar ? 'حسب النظام' : 'System';
  static String get themeLight => _ar ? 'فاتح' : 'Light';
  static String get themeDark => _ar ? 'داكن' : 'Dark';
  static String get downloadEngine => _ar ? 'محرك التنزيل' : 'Download engine';
  static String get parallelDownloads => _ar ? 'التنزيلات المتوازية' : 'Parallel downloads';
  static String get savePublic => _ar ? 'الحفظ في مجلد التنزيلات العام' : 'Save to public Downloads folder';
  static String get savePublicHint => _ar ? 'تظهر الملفات في تطبيق "الملفات" والمعرض' : 'Files appear in the Files app and gallery';
  static String get notifications => _ar ? 'إشعار اكتمال التنزيل' : 'Download completion notification';
  static String get clearCache => _ar ? 'مسح الملفات المؤقتة' : 'Clear temporary files';
  static String get cacheCleared => _ar ? 'تم مسح الملفات المؤقتة' : 'Temporary files cleared';
  static String get about => _ar ? 'حول التطبيق' : 'About';
  static String get aboutText => _ar
      ? 'GetTube تطبيق مفتوح المصدر لتنزيل الفيديو والصوت من يوتيوب بكل الجودات المتاحة — بدون إعلانات وبدون اشتراكات. استخدمه لتنزيل المحتوى المسموح به للاستخدام الشخصي فقط.'
      : 'GetTube is an open-source YouTube video & audio downloader with every available quality — no ads, no subscriptions. Use it only for permitted content and personal use.';
  static String get projectOnGithub => _ar ? 'المشروع على GitHub' : 'Project on GitHub';

  // ---- First-run disclaimer ----
  static String get disclaimerTitle => _ar ? 'مرحباً بك في GetTube 👋' : 'Welcome to GetTube 👋';
  static String get disclaimerBody => _ar
      ? '• كل الجودات مجانية للأبد — حتى 8K، بدون إعلانات.\n• نحترم خصوصيتك: لا حسابات، لا تتبع، لا جمع بيانات.\n• استخدم التطبيق لتنزيل المحتوى المسموح به وللاستخدام الشخصي فقط، واحترم حقوق أصحاب المحتوى.'
      : '• Every quality is free forever — up to 8K, zero ads.\n• We respect your privacy: no accounts, no tracking, no data collection.\n• Download only permitted content for personal use and respect creators\' rights.';
  static String get letsGo => _ar ? 'يلا نبدأ' : "Let's go";

  // ---- Misc ----
  static String get storageDenied => _ar ? 'لم يتم منح إذن التخزين' : 'Storage permission denied';
  static String get qualityNotAvailable => _ar ? 'هذه الجودة غير متاحة حالياً، جرّب جودة أخرى' : 'This quality is unavailable now, try another';
}
