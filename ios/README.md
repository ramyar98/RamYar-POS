# ڕێنمایی iOS — RAMYAR POS

ئەم فایلە ڕوونکردنەوەی هەموو ئەو شتانەیە کە بە تایبەت بۆ iOS لە پرۆژەکەدا ڕێکخراون،
و ئەو خاڵانەی کە دەبێت لە کاتی بەکارهێنان یان داگرتن (build) لە بیرت بێت.

---

## 1. زانیاری بنەڕەتی پرۆژە

| شت | بەها |
|---|---|
| Bundle ID | `com.kalakchi.ramyar.pos` |
| ناوی پیشاندراو (home screen) | `RAMYAR POS` |
| Workspace | `ios/Runner.xcworkspace` |
| Scheme | `Runner` |
| کەمترین وەشان (deployment target) | **iOS 15.0** (خواستی Flutter 3.47) |
| ئامێرەکان | iPhone + iPad، تەنها **landscape** |
| وەشانی ئەپ | لە `pubspec.yaml` ـەوە (`version: 1.0.0+1`) |
| بەڕێوەبردنی پلاگینەکان | **Swift Package Manager** (Flutter 3.35+) — Podfile نییە |
| Flutter ـی سی‌ئای | `3.47.7` (Dart 3.13.5) — Flutter 3.38.5 تەنها Dart 3.10.4 ـی هەیە و `pubspec.yaml` (`^3.12.1`) ڕەتی دەکاتەوە |

> ⚠️ **Podfile زیاد مەکە.** ئەم پرۆژەکە پلاگینەکانی بە Swift Package Manager
> (SPM) بەڕێوەدەبات، کە ڕێکخستنی بنەڕەتی Flutter ـی نوێیە. زیادکردنی `Podfile`
> لەگەڵ SPM ڕووبەڕوو دەبێتەوە و build ـەکە دەشکێنێت.

## 2. ئەو کلیلانەی لە `ios/Runner/Info.plist` زیادکراون و بۆچی

| کلیل | بۆچی |
|---|---|
| `NSLocalNetworkUsageDescription` | **گرنگترین.** لە iOS 14+ هەر ئەپێک کە دەیەوێت لەگەڵ ئامێرەکانی تۆڕی ناوخۆیی بدۆزێتەوە یان پەیوەندی پێوە بکات (سێرڤەری کاشێر، چاپکەر) پێویستی بە مۆڵەتی **Local Network** هەیە. بەبێ ئەم کلیلە ئایفۆن هیچ پرسیارێک نیشان نادات و هەموو ترافیکی تۆڕەکە بێدەنگ ڕەت دەکرێتەوە — واتە دۆزینەوەی ئۆتۆماتیکی و چاپکردن کار ناکەن. |
| `NSAppTransportSecurity` → `NSAllowsLocalNetworking` | بۆ دڵنیایی: ڕێگە بە HTTP ی ناوخۆیی دەدات بێ ئەوەی بۆ ئینتەرنێت سنوورەکە بشکێت. |
| `ITSAppUsesNonExemptEncryption` = `false` | ئەپ هیچ شێفرێکی تایبەت بەکارناهێنێت؛ ئەم کلیلە پرسیاری هەموو جارەکەی App Store Connect لادەبات. |
| `UIRequiresFullScreen` = `true` | ئەپ تەنها landscape ـە، و ئەم کلیلە ڕێگری دەکات لە هەڵەی `iPad Multitasking` لە کاتی داگرتن بۆ App Store. |
| `CFBundleLocalizations` | زمانەکانی ئەپ (ku, ckb, ar, fa, tr, en) بۆ سیستەم و پرۆمپتەکانی iOS. |

## 3. دۆزینەوەی سێرڤەر لەسەر iOS (خاڵی گرنگ)

* ئایفۆن/ئایپاد **دەتوانێت** بیکۆنەکانی ئامێرەکانی تر (Windows/Android) وەربگرێت،
  بە مەرجێک مۆڵەتی Local Network درابێت. واتە وەک **کڵاینت** کار دەکات.
* بەڵام لە iOS 14+ **ناردنی broadcast/multicast قەدەغەیە** بەبێ ئینتایتڵمەنتی
  `com.apple.developer.networking.multicast` کە تەنها Apple دەیدات.
  کەواتە ئەگەر ئایفۆنەکە **hub** بێت، بیکۆنەکەی ناچێتە دەرەوە.
* چارەسەری ئێمە: لە `lib/services/network_discovery_service.dart` لەسەر iOS
  جگە لە broadcast، بە **unicast** هەمان بیکۆن بۆ هەموو ناونیشانەکانی
  `/24` ـی خۆی دەنێردرێت (هەر ٥ چرکە). ئەمە تەنها مۆڵەتی Local Network
  پێویستە و هەموو ئامێرەکانی تر (کە وا بەسترابن بە پۆرتی `9877`) وەری دەگرن.
* ئەگەر دەتەوێت broadcast ـی ڕاستەقینە بەکاربهێنیت لەسەر iOS، دەبێت
  ئینتایتڵمەنتی Multicast Networking لە Apple داوا بکەیت.

**بەکارهێنەر چۆن مۆڵەتەکە دەدات:** یەکەم جار کە ئەپ دەکرێتەوە، پرۆمپتێک
دێت «RAMYAR POS دەتەوێت...» → **Allow** دابگرە. ئەگەر ڕەتی کردۆتەوە،
لە `Settings → Privacy & Security → Local Network` دەتوانرێت دووبارە هەڵکرێت.

## 4. سنووری سیستەمی iOS کە ناگۆڕدرێت

لە iOS ئەپ ناتوانێت لە پاڵەوە (background) سێرڤەر بەردەوام بێت. کەواتە:

* ئەم ئامێرەی کە **hub/سێرڤەری کاشێر**ـە دەبێت وەشانی ئەپ کراوە بێت و
  شاشەکە نەکەوێت. لە `Settings → Display & Brightness → Auto-Lock → Never`
  دایبنێ.
* کڵاینتەکان (سەرنشین/کاپتن) کێشەیەکیان نییە، لە هەر کاتێک ئەپ دەکرێتەوە
  دووبارە پەیوەندی دەکەن.

## 5. بەبڕین (build) بەبێ Mac

* لە ڕێگەی `codemagic.yaml` یان `.github/workflows/ios_build.yml`،
  `flutter build ios --release --no-codesign` ئەنجام دەدرێت و
  `Runner.app` دەکرێتە `Payload/` و دەکرێتە `RamyarPOS-unsigned.ipa`.
* **وەشانی Flutter لە سی‌ئای:** `3.47.7`. هۆکار: `pubspec.yaml` داوای
  `sdk: ^3.12.1` دەکات، بەڵام Flutter 3.38.5 (وەشانی ڕەسمی) تەنها
  Dart 3.10.4 ـی پێیە و `flutter pub get` دەشکێت. Flutter 3.47.7 Dart
  3.13.5 ـی پێیە، هەروەها پشتگیری Xcode 26/27 دەکات. ئەمەش وایکردووە
  `IPHONEOS_DEPLOYMENT_TARGET = 15.0` بێت (کەمترینی Flutter 3.47).
  هەردوو فایلی سی‌ئای پێش `pub get` پشکنینێکی خێرا دەکەن و ئەگەر Dart
  کەمتر بێت بە پەیامێکی ڕوون build دەوەستێنن.
* دەتوانرێت بە **Sideloadly** یان **AltStore** لەگەڵ Apple ID ـی خۆڕایی
  دابنرێت (هەر ٧ ڕۆژ دووبارە ئیمزاکردن پێویستە).
* بۆ `.ipa` ـی ئیمزاکراو (`ios-release`) دەبێت هەژماری
  Apple Developer Program ($99/ساڵ) هەبێت.

## 6. پێکهاتەی فایلەکان

```
ios/
├── Flutter/
│   ├── AppFrameworkInfo.plist      # کەمترین وەشانی ئەپ فرەیموۆرک
│   ├── Debug.xcconfig / Release.xcconfig
│   └── Generated.xcconfig          # خۆکار دروست دەکرێت (لە git نییە)
├── Runner/
│   ├── Info.plist                  # ڕێکخستنەکان + مۆڵەتەکانی iOS
│   ├── PrivacyInfo.xcprivacy       # مانیفێستی تایبەتمەندی (Apple 2024+)
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── Assets.xcassets/            # ئایکۆن و شاشەی دەستپێکردن
├── Runner.xcodeproj/               # پرۆژەی Xcode (bundle id، target، signing)
└── RunnerTests/                    # تێستەکانی نەیڤیڤ (xctest)
```
