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
  static String get sectionHigh => _ar ? 'جودات عالية' : 'High quality';
  static String get sectionAudio => _ar ? 'الصوت فقط' : 'Audio only';
  static String get autoMuxNote => _ar
      ? 'أعلى دقة مع أنقى صوت — قد تستغرق وقتاً أطول قليلاً'
      : 'Best picture with the cleanest audio — may take a bit longer';
  static String get recommended => _ar ? 'الأفضل' : 'Best';
  static String get download => _ar ? 'تنزيل' : 'Download';
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
  static String get processing => _ar ? 'جاري تجهيز الملف…' : 'Finalizing…';
  static String get saving => _ar ? 'جاري حفظ الملف…' : 'Saving file…';
  static String get waitingForWifi => _ar ? 'بانتظار Wi-Fi' : 'Waiting for Wi-Fi';
  static String get wifiGateHint => _ar
      ? 'التنزيل عبر بيانات الهاتف مقفول — شغّل Wi-Fi أو اسمح بالتنزيل بالبيانات'
      : 'Mobile data downloads are off — connect to Wi-Fi or allow mobile data';
  static String get allowMobileData => _ar ? 'السماح بالتنزيل بالبيانات' : 'Allow mobile data';
  static String get paused => _ar ? 'متوقف مؤقتاً' : 'Paused';
  static String get completed => _ar ? 'اكتمل' : 'Completed';
  static String get failed => _ar ? 'فشل' : 'Failed';
  static String get canceled => _ar ? 'ملغي' : 'Canceled';
  static String get pause => _ar ? 'إيقاف مؤقت' : 'Pause';
  static String get resume => _ar ? 'استكمال' : 'Resume';
  static String get fileDeleted => _ar ? 'تم حذف الملف' : 'File deleted';
  static String get fileMissing => _ar ? 'الملف غير موجود' : 'File not found';
  static String get refresh => _ar ? 'تحديث' : 'Refresh';

  // ---- Downloads library (SnapTube-style manager) ----
  static String get tabAll => _ar ? 'الكل' : 'All';
  static String get tabVideos => _ar ? 'فيديو' : 'Videos';
  static String get tabMusic => _ar ? 'صوت' : 'Music';
  static String get searchDownloads => _ar ? 'ابحث في التنزيلات…' : 'Search downloads…';
  static String get sortBy => _ar ? 'الترتيب' : 'Sort';
  static String get sortNewest => _ar ? 'الأحدث أولاً' : 'Newest first';
  static String get sortLargest => _ar ? 'الأكبر حجماً' : 'Largest first';
  static String get sortName => _ar ? 'الاسم (أ-ي)' : 'Name (A-Z)';
  static String get share => _ar ? 'مشاركة' : 'Share';
  static String get details => _ar ? 'التفاصيل' : 'Details';
  static String get selectAll => _ar ? 'تحديد الكل' : 'Select all';
  static String get exitSelection => _ar ? 'إنهاء التحديد' : 'Exit selection';
  static String get storageUsed => _ar ? 'المساحة المستخدمة' : 'Storage used';
  static String get filePath => _ar ? 'المسار' : 'Path';
  static String get fileSize => _ar ? 'الحجم' : 'Size';
  static String get fileDate => _ar ? 'التاريخ' : 'Date';
  static String get shareFailed => _ar ? 'تعذر مشاركة الملف' : 'Could not share the file';
  static String get openFolderMenu => _ar ? 'فتح المجلد' : 'Open folder';
  static String get folderOpenFailed => _ar ? 'تعذر فتح المجلد' : 'Could not open the folder';
  static String selectedCount(int n) => _ar ? 'تم تحديد $n' : '$n selected';
  static String deleteConfirm(int n) => _ar ? 'حذف $n ملف نهائياً؟' : 'Delete $n file(s) permanently?';
  static String deletedCount(int n) => _ar ? 'تم حذف $n ملف' : '$n file(s) deleted';

  // ---- Settings ----
  static String get settings => _ar ? 'الإعدادات' : 'Settings';

  // Tabs
  static String get tabGeneral => _ar ? 'عام' : 'General';
  static String get tabDownloads => _ar ? 'التنزيلات' : 'Downloads';
  static String get tabStorage => _ar ? 'التخزين' : 'Storage';
  static String get tabAbout => _ar ? 'حول' : 'About';

  // General tab
  static String get appearance => _ar ? 'المظهر' : 'Appearance';
  static String get language => _ar ? 'اللغة' : 'Language';
  static String get theme => _ar ? 'الوضع' : 'Theme';
  static String get themeSystem => _ar ? 'حسب النظام' : 'System';
  static String get themeLight => _ar ? 'فاتح' : 'Light';
  static String get themeDark => _ar ? 'داكن' : 'Dark';
  static String get notifications => _ar ? 'إشعار اكتمال التنزيل' : 'Download completion notification';

  // Downloads tab
  static String get maxTasks => _ar ? 'عدد التنزيلات المتزامنة' : 'Simultaneous downloads';
  static String get maxTasksHint => _ar ? 'كم فيديو ينزل في نفس الوقت' : 'How many videos download at the same time';
  static String get mobileData => _ar ? 'التنزيل عبر بيانات الهاتف' : 'Download over mobile data';
  static String get mobileDataHint => _ar ? 'عند الإيقاف ينتظر التنزيل اتصال Wi-Fi' : 'When off, downloads wait for Wi-Fi';
  static String get clearCache => _ar ? 'مسح الملفات المؤقتة' : 'Clear temporary files';
  static String get cacheCleared => _ar ? 'تم مسح الملفات المؤقتة' : 'Temporary files cleared';

  // Storage tab
  static String get saveLocation => _ar ? 'مكان الحفظ' : 'Save location';
  static String get saveLocationHint => _ar ? 'حدد أين تُحفظ تنزيلاتك' : 'Choose where your downloads are saved';
  static String get phoneStorage => _ar ? 'ذاكرة الهاتف' : 'Phone storage';
  static String get sdCard => _ar ? 'بطاقة SD' : 'SD card';
  static String get noSdCard => _ar ? 'لا توجد بطاقة SD مثبتة' : 'No SD card detected';
  static String get customFolder => _ar ? 'مجلد مخصص' : 'Custom folder';
  static String get customFolderHint => _ar ? 'اختر أي مجلد — من الذاكرة أو بطاقة SD' : 'Pick any folder — internal or SD card';
  static String get appPrivate => _ar ? 'ذاكرة التطبيق' : 'App storage';
  static String get appPrivateHint => _ar ? 'ملفات خاصة تُحذف مع حذف التطبيق' : 'Private files, removed if the app is uninstalled';
  static String get chooseAnotherFolder => _ar ? 'اختيار مجلد آخر' : 'Choose another folder';
  static String get newFolder => _ar ? 'مجلد جديد' : 'New folder';
  static String get folderName => _ar ? 'اسم المجلد' : 'Folder name';
  static String get folderCreated => _ar ? 'تم إنشاء المجلد' : 'Folder created';
  static String get folderCreateFailed => _ar ? 'تعذر إنشاء المجلد' : 'Could not create the folder';
  static String get locationChanged => _ar ? 'تم تحديث مكان الحفظ' : 'Save location updated';

  // About tab
  static String get about => _ar ? 'حول التطبيق' : 'About';
  static String get versionLabel => _ar ? 'الإصدار' : 'Version';
  static String get aboutText => _ar
      ? 'نزّل الفيديو والصوت من يوتيوب بأي جودة — بدون إعلانات وبدون اشتراكات. خصوصيتك محفوظة: لا حسابات ولا تتبع ولا جمع بيانات. استخدم التطبيق للمحتوى المسموح به وللاستخدام الشخصي فقط.'
      : 'Download video & audio from YouTube in any quality — no ads, no subscriptions. Your privacy is respected: no accounts, no tracking, no data collection. Use it only for permitted content and personal use.';
  static String get reportProblem => _ar ? 'الإبلاغ عن مشكلة' : 'Report a problem';
  static String get reportProblemHint => _ar ? 'انسخ التفاصيل وأرسلها لنا إذا واجهت أي مشكلة' : 'Copy the details and send them to us if something goes wrong';

  // ---- First-run disclaimer ----
  static String get disclaimerTitle => _ar ? 'مرحباً بك في GetTube 👋' : 'Welcome to GetTube 👋';
  static String get disclaimerBody => _ar
      ? '• كل الجودات مجانية للأبد — حتى 8K، بدون إعلانات.\n• نحترم خصوصيتك: لا حسابات، لا تتبع، لا جمع بيانات.\n• استخدم التطبيق لتنزيل المحتوى المسموح به وللاستخدام الشخصي فقط، واحترم حقوق أصحاب المحتوى.'
      : '• Every quality is free forever — up to 8K, zero ads.\n• We respect your privacy: no accounts, no tracking, no data collection.\n• Download only permitted content for personal use and respect creators\' rights.';
  static String get letsGo => _ar ? 'يلا نبدأ' : "Let's go";

  // ---- Diagnostics ----
  static String get diagnostics => _ar ? 'الإبلاغ عن مشكلة' : 'Report a problem';
  static String get errorLog => _ar ? 'تفاصيل المشاكل' : 'Problem details';
  static String get errorLogHint => _ar ? 'انسخ التفاصيل وأرسلها لنا إذا واجهت أي مشكلة' : 'Copy the details and send them to us if something goes wrong';
  static String get errorLogEmpty => _ar ? 'لا أخطاء مسجلة — كل شيء يعمل بشكل ممتاز' : 'No errors recorded — all good';
  static String get copyError => _ar ? 'نسخ السجل' : 'Copy log';
  static String get logCopied => _ar ? 'تم نسخ السجل' : 'Log copied';
  static String get clearLog => _ar ? 'مسح السجل' : 'Clear log';

  // ---- Download errors ----
  static String get streamRejected => _ar
      ? 'تعذر إكمال التنزيل الآن — اضغط إعادة المحاولة وسيجدد التطبيق الرابط تلقائياً'
      : 'Could not finish this download — tap retry and the link refreshes automatically';

  // ---- Misc ----
  static String get storageDenied => _ar ? 'لم يتم منح إذن التخزين' : 'Storage permission denied';
  static String get qualityNotAvailable => _ar ? 'هذه الجودة غير متاحة حالياً، جرّب جودة أخرى' : 'This quality is unavailable now, try another';
  static String get downloadFailedGeneric => _ar
      ? 'حدث خطأ أثناء التنزيل — تحقق من اتصالك وحاول مجدداً'
      : 'Something went wrong — check your connection and try again';
}
