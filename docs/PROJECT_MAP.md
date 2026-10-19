# نەخشەی پڕۆژەی RAMYAR POS — وەسفی تەواو بۆ Gemini

> ئەم فایلە وەسفی تەواوی پڕۆژەکەیە: نەخشەی فایلەکان، دیزاین و دوگمەکان، داتابەیس، پرۆتۆکۆلی سینک، سیستەمی چاپ، هەموو ڕۆڵەکان (وەیتەر/کاشێر/ئادمێن) و هەموو سۆرس کۆدەکە. دەتوانیت هەمووی کۆپی بکەیت و بۆ Gemini بنێریت بۆ ئەوەی بە تەواوی لە پڕۆژەکە تێبگات. تێخستەی تەکنیکی بە ئینگلیزی ماوەتەوە، ئەوانەی تر بە کوردی (سۆرانی)ن.

---

## ١. کورتە (Overview)

**RAMYAR POS** (پاشکۆ: `com.kalakchi.ramyar.pos`) ئەپێکی **Flutter**ـە بۆ بەڕێوەبردنی چێشتخانەیەک، بە سیستەمی **offline-first real-time sync**. دەبژێردرێت لەسەر **لابتۆپ ویکەکە کاشێر/سێرڤێرە** و لەسەر **مۆبایلەکانی وەیتەرەکان** (Android).

### چۆن کار دەکات (flowی سەرەکی)
1. هەر دەستگە داتابەیسێکی **SQFlite**ی تایبەت بە خۆی هەیە — هەر کەس پێویستی نەبێت بە سێرڤێر، کار دەکات.
2. لابتۆپەکە **WebSocket سێرڤێر** لەسەر **پۆرت ٩٨٧٦** دروست دەکات و لە ڕێگەی **UDP broadcast (پۆرت ٩٨٧٧)** خۆی ناساندووە.
3. مۆبایلەکانی وەیتەر بە شێوەی خۆکار سێرڤێرەکە دەدۆزنەوە و پەیوەندی **WebSocket** دروست دەکەن.
4. هەر گۆڕانکارییەک لە داتابەیس (occupy, order, settle, transfer...) **SyncMessage**ـێک دەبێت و ڕەوانەی سێرڤێر دەکرێت؛ سێرڤێرەکە بۆ **هەموو دەستگەکانی تر** بڵاوی دەکاتەوە و **ack** دەگەڕێنێتەوە.
5. کاتێک پەیوەندی نەما، کردەوەکە دەکەوێتە ناو **`pending_sync`** (وەرگر/ڕدیف) و کاتێک پەیوەندی گەڕایەوە **خۆکار دەچێتەوە بۆ سێرڤێر**.
6. چاپکردن لە **چاپکەری گەرم (thermal ESC/POS)** دەکرێت بۆ ٤ جۆر: **mەتبەخ (kitchen) / باڕ (bar) / نێرگیلە (hookah) / کاشێر (cashier) چشم**.

### ڕۆڵەکان (Roles)
- **وەیتەر (Waiter)**: ناوە، ئۆردەر دەکات بۆ مێز، چاپی kitchen ticket، دەوێت کۆتایی.
- **کاشێر (Cashier)**: شەفت دەستپێدەکات، حیساب جێگیر دەکات (settlement)، پارە وەردەگرێت، گواستنەوە و تێکەڵکردنی مێز.
- **ئادمێن (Admin)**: بەکارهێنەر، مێنیو، حسابە داراییەکان، شەفتەکان، بەکاپ، ستاتیسی، چاپکەر.

### زمانەکان
کوردی (سۆرانی) بناغەیە + عەرەبی، فارسی، ئینگلیزی، تورکی. `context.tr(key)` — کاتێک زمان کوردییە، **key خۆی** دەگەڕێتەوە (واتە ئەو دەقانەی کوردین لە کۆدەکەدا). وەرگێڕان بۆ زمانەکانی تر لە `app_localizations.dart`ـدایە.

---

## ٢. تەکنەلۆجیاکان (Tech Stack)

| لایەن | تەکنەلۆجیا |
|---|---|
| Framework | Flutter (Dart, Material 3) |
| State management | flutter_riverpod (StateNotifier / Provider / StateNotifierProvider) |
| Local database | sqflite + `sqflite_common_ffi` (Windows) + `sqflite_common_ffi_web` (Web) |
| Settings/token/auth session | shared_preferences |
| Real-time sync | WebSocket (`dart:io` HttpServer + WebSocketTransformer) + UDP broadcast (`RawDatagramSocket`) |
| Printing | ESC/POS raw bytes → Windows spool (ffi) یان raw TCP socket بۆ چاپکەری network |
| Platform | Android (mۆبایل)، Windows (desktop کاشێر/سێرڤێر)، Web |
| پاشکۆ | `com.kalakchi.ramyar.pos` |
| ناوەندی دیزاین | Material 3، light theme، ڕەنگی سەرەکی نارنجی |

---

## ٣. نەخشەی فایلەکان (File Tree) بە ژمارەی ڕیزی هەر فایلێک

```
lib/                                          (٦٢ فایل dart)
├── main.dart                                  (٤٠) نوکتەی دەستپێک
├── core/                                      (کۆر)
│   ├── app.dart                               (١٦٢) AppState + RamyarPosApp (root)
│   ├── colors.dart                            (٢١) AppColors
│   ├── constants.dart                         (٢٨) AppConstants
│   ├── language.dart                          (٥١) AppLanguage enum (٥ زمان)
│   ├── responsive.dart                        (٢٢٧) isPhone/Tablet/Desktop + ResponsiveGridView/Row
│   └── theme.dart                             (٩٦) ThemeData
├── database/
│   └── local_db.dart                          (٢٢١٩) ✳️ داتابەیس هەمووی: schema/migrate/CRUD/seed/sync
├── models/                                    (١٢ فایل)
│   ├── user_model.dart                        (٣٨) UserModel + UserRole
│   ├── table_model.dart                       (١١٧) TableModel + TableStatus
│   ├── order_model.dart                       (٦٩) OrderItem + SeatedOrder
│   ├── settlement_model.dart                  (٢٢٤) SettledOrder/Item + Refund + Purchase + CashierShift
│   ├── debt_model.dart                        (٤٥) DebtModel
│   ├── cancelled_item_model.dart              (٧٨) CancelledItem
│   ├── printer_model.dart                     (١٠٩) PrinterConfig + PrinterType
│   ├── menu_model.dart                        (٥٢) FoodCategory + FoodItem
│   ├── order_delivery_model.dart              (٢٣) OrderDeliveryModel
│   ├── table_notification_model.dart          (٣٤) TableNotification
│   ├── table_lock_model.dart                  (٦٥) TableLock
│   └── (printer_model بەشێکە لە ناوەوە: PrintJob/PrintJobItem)
├── providers/
│   ├── auth_provider.dart                     (٣٥) AuthNotifier (login/logout/session)
│   ├── waiter_provider.dart                   (٢٠٣) allTables + tableDetail/Orders families
│   └── printer_provider.dart                  (٦٧) PrinterProviderState (printers+mappings)
├── services/
│   ├── sync_provider.dart                     (٦٠٢) ✳️ SyncStateNotifier + server/client/flush/apply
│   ├── sync_types.dart                        (٩٢) SyncMessage + AckMessage + SyncConnectionQuality
│   ├── pos_socket_server.dart                 (٣٧٢) WebSocket سێرڤێر (پۆرت ٩٨٧٦) + auth + heartbeat
│   ├── pos_socket_client.dart                 (٢٢٤) کڵاینت + reconnect + auto-discovery
│   ├── network_discovery_service.dart         (٢٥٧) UDP discovery (پۆرت ٩٨٧٧) + virtual-adapter filter
│   ├── order_conflict_resolver.dart           (٤٢) apply/replace/rejectDuplicate
│   ├── printer_service.dart                   (١٢٠) printOrder/printReceipt
│   ├── print_router.dart                      (١٥٩) routeOrder → PrintJob بەپێی mapping
│   ├── printer_discovery_service.dart         (٢٤٩) دۆزینەوەی چاپکەر (Windows + network)
│   ├── esc_pos_builder.dart                   (٢٤١) دروستکردنی ESC/POS commands
│   ├── menu_helper.dart                       (٢٧) iconFromString...
│   ├── food_localization.dart                 (٢٦) localizedName()
│   └── app_localizations.dart                 (٢١٠٦) ✳️ tr()/trp() + _allTranslations (٥ زمان)
├── page/
│   ├── login/
│   │   └── login_page.dart                    (٢٤٩) PIN keypad login
│   ├── waiter/
│   │   ├── waiter_home_page.dart              (٦٨٥) ✳️ gridی مێزەکان + auto-connect + refresh
│   │   ├── table_page.dart                    (٧٣٥) ✳️ دیتەیلی مێز + ئۆردەرکردن + چاپ
│   │   ├── order_page.dart                    (٢٥٧) لیستی ئۆردەری مێز + چاپی kitchen ticket
│   │   └── waiter_settings_page.dart          (٢١٠) access code + IP سێرڤێر
│   ├── cashier/
│   │   ├── cashier_welcome_page.dart          (٣٥٠) دەستپێکی شەفت (shift)
│   │   ├── cashier_home_page.dart             (١٥٠٨) ✳️ هەموو مێزەکان + tabs + حیسابەکان
│   │   ├── cashier_unified_table_page.dart    (١٩٦٧) ✳️ پەڕەی سەرەکی مێز (حیساب+discount+گواستنەوە+settle)
│   │   ├── cashier_cancelled_items_page.dart  (٢٩٦) ڕەتکراوەکان + گەڕاندنەوە بۆ مێز
│   │   ├── transfer_page.dart                 (٢٩٦) گواستنەوەی تەواوی مێز
│   │   └── merge_page.dart                    (٣٨١) تێکەڵکردنی ٢ مێز (٣ هەنگاو)
│   └── admin/                                 (١٥ فایل)
│       ├── admin_home_page.dart               (١٨٩) داشبۆرد + logout
│       ├── admin_users_page.dart              (٥٥٢) بەکارهێنەرەکان + IP access code
│       ├── admin_menu_page.dart               (٩٠٥) مێنیو + printer-mode
│       ├── admin_accounts_page.dart           (٢٢٣) حسابە داراییەکان
│       ├── admin_orders_page.dart             (٤١٠) مێژووی ئۆردەرەکان
│       ├── admin_shifts_page.dart             (٢٣٢) شەفتەکان
│       ├── admin_shift_detail_page.dart       (٨٧٤) ڕاپۆرتی شەفت
│       ├── admin_purchases_page.dart          (٢٠٥) کڕینەکان
│       ├── admin_refunds_page.dart            (٢٠٤) ڕەفزەکان
│       ├── admin_debts_page.dart              (٢٢٩) قەرزەکان
│       ├── admin_backup_page.dart             (٣٣٠) بەکاپ/restore/reset
│       ├── admin_captain_intelligence_page.dart (٩٥) ستاتیسی وەیتەر
│       ├── admin_food_demand_page.dart        (١٦٥) داواکاری خواردن
│       ├── admin_food_filter_page.dart        (٣٨٢) فلتری چاپکەر بۆ خواردن
│       └── admin_printer_screen.dart          (٥٠٥) ڕێکخستنی چاپکەر + mapping
└── widgets/
    ├── table_card.dart                        (١٩٢) کارتی مێز لە grid
    ├── profile_icon.dart                      (١٥٠) ئایکۆنی پرۆفایل + language + settings
    ├── print_preview_dialog.dart              (٢٨٣) پێشبینینی چاپ
    ├── currency_converter.dart                (١٧٠) گۆڕینەوەی USD⇄IQD
    ├── close_shift_dialog.dart                (٩٩) دیالۆگی داخستنی شەفت
    └── cash_calculator_dialog.dart            (٤٣٥) حیسابی کاش (IQD/USD)

test/                                          (٨ فایل — وەسفی تەواو لە بەشی ١٠)
    ├── app_smoke_test.dart                    (٣٩)
    ├── login_flow_test.dart                   (٩٦)
    ├── local_db_test.dart                     (٣٢٠)
    ├── table_bill_color_test.dart             (١٠٤)
    ├── responsive_test.dart                   (٢٣٢) (٤٨ تێست)
    ├── offline_sync_test.dart                 (١٠١)
    ├── sync_integration_test.dart             (١٥٨)
    └── order_conflict_resolver_test.dart      (٨٣)

integration_test/
    └── close_shift_test.dart                  (١٠٥) تێستی ڕاستەقینە لەسەر Windows

pubspec.yaml (٦٩)  |  analysis_options.yaml (٢٥)  |  README.md (١١)
```

---

## ٤. ئارکیتێکتەر (Architecture — چۆن هەموو بەشەکان بە یەکەوە بەستراوە)

### ٤.١ نوکتەی دەستپێک `main.dart`
1. `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` بۆ Windows؛ `databaseFactoryFfiWebNoWebWorker` بۆ Web.
2. ڕیتشکردنەوەی ڕووکار بۆ **landscape**، شوون بوونی navigation/status bar (کۆدی Android).
3. `LocalDatabase().init()` پێش `runApp`.
4. `ProviderScope(overrides: [localDbProvider.overrideWithValue(db)])` — هەمان شێواز لە تێستەکاندا بەکاردێت.
5. `RamyarPosApp` (root) → `MaterialApp` → `LoginPage` ئەگەر session نەبێت، بەپێی ڕۆڵ دەچێت بۆ پەڕەی گشتی.

### ٤.٢ Core (کۆر)
- **`core/app.dart`**: `AppState` (زمان + تێم) — `AppState.of(context)`. `RamyarPosApp`: `MaterialApp`، `home` بەپێی isLoggedIn/role، `localizationsDelegates`، system navigator orientation، `themeMode`.
- **`core/language.dart`**: `AppLanguage` enum (kurdish/arabic/persian/english/turkish) + `languageIndex`.
- **`core/colors.dart`**: `AppColors`: `background` (زەرد-کلک-light)، `primary` (نارنجی)، `success` (سەوز)، `danger` (سوور)، `blue`، `softText` (ڕەنگی هێمن)، `darkText`، `borderSide`. هەموو پەڕەکان `AppColors` بەکاردێنن.
- **`core/constants.dart`**: `AppConstants`: spacing (٨/١٢/١٦)، padding، radius (٢٠). `Sizes` بۆ چەند responding.
- **`core/responsive.dart`**: `Responsive.isPhone/Tablet/Desktop` (بەپێی `LayoutBuilder`+width؛ بەرهەڵستی ٨ framework لە responsive_test):
  - `isPhone < 600`، `isTablet < 1100`، `isDesktop ≥ 1100`.
  - `ResponsiveGridView`: `crossAxisCount` بەپێی width (mobile=1/2، tablet=3/4، desktop=5/6) + childAspectRatio.
  - `ResponsiveRow`: چەند بەش (left/right) لە desktop، وەک stacked لە phone.
- **`core/theme.dart`**: `ThemeData` گشتی: Material 3، `colorScheme.primary = AppColors.primary`، `cardTheme` (radius ٢٠)، `chipTheme`، `appBarTheme`، `dividerTheme`، `useMaterial3: true`.

### ٤.٣ Providers (بدە state)
- **`auth_provider.dart`** — `authProvider` (StateNotifierProvider<AuthNotifier>):
  - `AuthNotifier`: `login(String pin)` → `LocalDatabase.getUserByPin`؛ `UserRole` و `loggedUserId` لە `SharedPreferences` پاشەکەوت دەکات (`loggedUserIdKey`)؛ `tryAutoLogin()` لە `init`ـدا؛ `logout()` لادەبات. `isLoggedIn`/`currentUser`.
- **`waiter_provider.dart`**:
  - `allTablesProvider` — `StateNotifier<List<TableModel>>`؛ `refresh()` (ناوبەمان)، `refreshSilent()` (loading نیشان نادات).
  - `tableDetailProvider(tableId)` — family `StateNotifierProvider<TableDetailNotifier, TableModel>`؛ `refresh()`.
  - `tableOrdersProvider(tableId)` — family بۆ لیستی `OrderItem` (حال).
  - `deliveryStatusProvider(tableId)`، `tableNotificationsProvider`، `waiterNamesProvider` (لیستی وەیتەرەکان بۆ filter).
  - `generateId()` — UUID بۆ OrderItem (کە `dart:math` Random باکاردێنێت، نەک uuid package).
- **`printer_provider.dart`** — `PrinterProviderState`:
  - fields: `printers: List<PrinterConfig>`، `categoryMappings: Map<String, int>`، `itemOverrides: Map<String, int>`، `itemPrinterAssignments: Map<String, List<PrinterType>>`.
  - `load()`، `addPrinter`، `deletePrinter`، `setCategoryMapping/removeCategoryMapping`، `setItemOverride/removeItemOverride`، `setItemPrinterTypes`، `setDefaultPrinter`.
  - `localDbProvider` (to LocalDatabase).

### ٤.٤ Models (هەموو ڕووگە/structەکان)
- **`user_model.dart`**: `UserModel` (id, name, pin, role, rangeStart, rangeEnd, accessCode) + `UserRole` enum: `waiter(0)/cashier(1)/admin(2)`.
- **`table_model.dart`**: `TableModel` (id, name, status, guestCount, seatedTime, waiterId, totalAmount, sentToCashier, printedAt, note, createdBy) + `TableStatus` enum: `empty/occupied/billRequested/overdue`.
- **`order_model.dart`**: `OrderItem` (id (uuid), tableId, name, price, quantity, category, createdAt, waiterName, notes) + `SeatedOrder` (وەک OrderItem+seatedAt).
- **`settlement_model.dart`**: `SettledOrder` (id, tableId, tableName, totalAmount, discountPercent, discountAmount, settledAt, settledBy, shiftId, seatedAt, paymentMethod, waiterId)، `SettledOrderItem`، `Refund`، `Purchase`، `CashierShift`.
- **`debt_model.dart`**: `DebtModel` (id, tableId, tableName, amount, reason, createdAt, createdBy).
- **`cancelled_item_model.dart`**: `CancelledItem` (id, shiftId, tableId, tableName, itemName, itemPrice, quantity, category, cancelledAt, cancelledBy, cancelledByName, status, servedAt).
- **`printer_model.dart`**: `PrinterConfig` (id, name, portName, printerType, isDefault) + `PrinterType` enum `kitchen/bar/hookah/cashier` + `PrintJob`/`PrintJobItem` + `DiscoveredPrinter`.
- **`menu_model.dart`**: `FoodCategory` + `FoodItem` (هەردووکیان ٥ زمان: name/name_ar/name_fa/name_en/name_tr).
- **`order_delivery_model.dart`**: `OrderDeliveryModel` (tableId, sentAt, arrivedAt, printedAt, rejected) + `DeliveryItemStatus` (id, name, quantity, category, syncedAt, printedAt, failedPrinters). پەڕەی گەیشتن بە ئاستی **ئایتم** کار دەکات: گەیشت/نەگەیشت = ئایا ئەم خواردنە گەیشتووەتە سیستەمی کاشێر؟ پرێنت/دوبارە پرێنت = ئایا تیکەتی ئەم خواردنە لە **هەموو** پرێنتەرە تەرخانکراوەکانی دەرچووە؟ `OrderDeliveryModel` یاریدەدەری وەک `items/arrivedItemCount/printedItemCount/pendingItems/unprintedItems/allItemsArrived/allItemsPrinted/anyItemPrintFailed/itemStatusLabel` هەیە.
- **`table_notification_model.dart`**: `TableNotification` (id, tableId, openedAt).
- **`table_lock_model.dart`**: `TableLock` (tableId, deviceId, userId, userName, role, lockedAt, heartbeat).

---

## ٥. داتابەیس (Database) — `local_db.dart` (٢٢١٩ ڕیزی)

نوێترین وەشانی schema: **v46**. هەر مایگریشنێک لە `_onCreate` + `_onUpgrade`ـدا. `resetForTesting()` بۆ تێست داتابەیسەکە دادەخات.

### ٥.١ هەموو تابلێکەکان (TableSchema) — ستوونەکان بە وردی

**١. `tables`** — (١٠٠ مێز لە سەرەتادا: «مێز ١..مێز ١٠٠»)
`id INTEGER PK`, `name TEXT NOT NULL`, `status INTEGER DEFAULT 0 (TableStatus)`, `seatedTime TEXT DEFAULT ''`, `waiterId TEXT DEFAULT ''`, `totalAmount REAL DEFAULT 0.0`, `guestCount INTEGER DEFAULT 0`, `sentToCashier INTEGER DEFAULT 0`, `printedAt TEXT DEFAULT ''`, `note TEXT DEFAULT ''`, `createdBy INTEGER DEFAULT 0 (دەسەڵاتی خاوەنی مێز یان ٠=گشتی)`.
Migrations: v2 guestCount، v3 sentToCashier، v5/v7 printedAt، v17 note، v20 createdBy.

**٢. `order_items`** — ئیتەمەکانی مێز (PK = `(id, tableId)` واتە id خودى UUIDیە):
`id TEXT NOT NULL`, `tableId INTEGER NOT NULL`, `name TEXT NOT NULL`, `price REAL NOT NULL`, `quantity INTEGER DEFAULT 1`, `category TEXT DEFAULT ''`, `createdAt TEXT NOT NULL`, `waiterName TEXT DEFAULT '' (v17)`, `waiterRole INTEGER DEFAULT -1`, `syncedAt TEXT DEFAULT '' (v46 – گەیشتنە لای کاشێر)`, `printedAt TEXT DEFAULT '' (v46 – یەکەم تیکەتی سەرکەوتوو)`, `failedPrinters TEXT DEFAULT '' (v46 – CSV ی ئیندێکسی پرێنتەرەکان کە هێشتا تیکەتیان دەوێت؛ تەنها کاتێک ئایتم «پرێنت کراوە» ژمێردرێت کە هەموو پرێنتەرە تەرخانکراوەکان تیکەتیان دابێت)`.

**٣. `users`** — بەکارهێنەران:
`id INTEGER PK AUTOINCREMENT`, `name TEXT NOT NULL`, `pin TEXT NOT NULL UNIQUE`, `role INTEGER NOT NULL (UserRole)`, `rangeStart INTEGER (v24)`, `rangeEnd INTEGER (v24)`, `accessCode TEXT DEFAULT '' (v29)`.
Seed (ئامادەی): Admin 3344 (admin، id=1)، وەیتەر 1 1122 (range 1-50، id=2)، وەیتەر 2 1123 (range 51-100، id=3)، کاشێر 1 2233 (cashier، id=4).

**٤. `debts`** — قەرز:
`id INTEGER PK AUTOINCREMENT`, `tableId`, `tableName TEXT NOT NULL`, `amount REAL NOT NULL`, `reason TEXT DEFAULT ''`, `createdAt TEXT NOT NULL`, `createdBy INTEGER NOT NULL`.

**٥. `printer_configs`** — ڕێکخستنەکانی چاپکەر:
`id INTEGER PK AUTOINCREMENT`, `name TEXT NOT NULL`, `portName TEXT NOT NULL`, `printerType INTEGER NOT NULL`, `isDefault INTEGER DEFAULT 0`.

**٦. `category_printer_mappings`** — باکتری categor برای چاپکەر:
`category TEXT NOT NULL PRIMARY KEY`, `printerConfigId INTEGER NOT NULL`.

**٧. `item_printer_overrides`** — وەرگرتن بۆ خواردنی تایبەت:
`itemName TEXT NOT NULL PRIMARY KEY`, `printerConfigId INTEGER NOT NULL`.

**٨. `item_printer_assignments`** — چەند چاپکەر بۆ ئیتەمێک (لە admin_menu printer-mode):
`itemName TEXT NOT NULL`, `printerType INTEGER NOT NULL`, `PRIMARY KEY (itemName, printerType)`.

**٩. `settled_orders`** — حیسابە جێگیرکراوەکان:
`id INTEGER PK AUTOINCREMENT`, `tableId`, `tableName TEXT NOT NULL`, `totalAmount REAL NOT NULL`, `discountPercent REAL DEFAULT 0`, `discountAmount REAL DEFAULT 0`, `settledAt TEXT NOT NULL`, `settledBy INTEGER NOT NULL`, `shiftId INTEGER DEFAULT 0 (v13)`, `seatedAt TEXT DEFAULT '' (v15/v22)`, `paymentMethod TEXT DEFAULT 'cash' (v16/v22 — cash/fib/switch/superqi/nass/debt)`, `waiterId TEXT DEFAULT '' (v28)`.

**١٠. `settled_order_items`**:
`id INTEGER PK AUTOINCREMENT`, `settledOrderId INTEGER NOT NULL`, `itemName TEXT NOT NULL`, `itemPrice REAL NOT NULL`, `quantity INTEGER NOT NULL`, `category TEXT DEFAULT ''`.

**١١. `cashier_shifts`** — شەفتەکان:
`id INTEGER PK AUTOINCREMENT`, `cashierId INTEGER NOT NULL`, `cashierName TEXT NOT NULL`, `startedAt TEXT NOT NULL`, `endedAt TEXT DEFAULT ''`, `totalCollected REAL DEFAULT 0`.

**١٢. `purchases`** — کڕین:
`id INTEGER PK AUTOINCREMENT`, `itemName TEXT NOT NULL`, `price REAL NOT NULL`, `purchasedAt TEXT NOT NULL`, `purchasedBy INTEGER NOT NULL`.

**١٣. `refunds`** — ڕەفز:
`id INTEGER PK AUTOINCREMENT`, `tableId`, `itemName`, `quantity INTEGER`, `price REAL`, `refundedAt TEXT`, `refundedBy INTEGER`, `shiftId INTEGER DEFAULT 0 (v13)`.

**١٤. `cashier_expenses`** — خەرجیەکانی کاشێر (لە ڕاپۆرتی شەفت):
`id INTEGER PK AUTOINCREMENT`, `shiftId INTEGER NOT NULL`, `itemName TEXT NOT NULL`, `price REAL NOT NULL`, `createdAt TEXT NOT NULL`.

**١٥. `cancelled_items`** — ئەو خواردنانەی ڕەتکراونەتەوە:
`id INTEGER PK AUTOINCREMENT`, `shiftId INTEGER DEFAULT 0`, `tableId`, `tableName`, `itemName`, `itemPrice REAL`, `quantity INTEGER DEFAULT 1`, `category TEXT DEFAULT ''`, `cancelledAt TEXT`, `cancelledBy INTEGER DEFAULT 0`, `cancelledByName TEXT DEFAULT ''`, `status TEXT DEFAULT 'pending'`, `servedAt TEXT DEFAULT ''`. Status: pending/served (لە کاشێر: “گواستنەوە بۆ مێز” => served).

**١٦. `table_notifications`** — داواکاری/ئاگەدارکردنەوە بۆ مێز:
`id INTEGER PK AUTOINCREMENT`, `tableId INTEGER NOT NULL`, `openedAt TEXT NOT NULL`.

**١٧. `food_categories`** — بەشەکانی مێنیو:
`id INTEGER PK AUTOINCREMENT`, `name TEXT NOT NULL`, `icon TEXT DEFAULT 'restaurant'`, `section TEXT DEFAULT '' (گەرمی/ساردی/شیرینی/کێک)`, `sortOrder INTEGER DEFAULT 0`, `name_ar/fa/en/tr TEXT DEFAULT '' (v19)`.
Seed: ٨ کەتگۆری — بەرگەر، پیتزا، مریشک، برنج، کەباب، ماسی، شیرینی، خواردنەوە.

**١٨. `food_items`** — خواردنەکانی مێنیو:
`id INTEGER PK AUTOINCREMENT`, `name TEXT NOT NULL`, `price REAL NOT NULL`, `category TEXT NOT NULL`, `imageUrl TEXT DEFAULT '' (v12)`, `sortOrder INTEGER DEFAULT 0`, `name_ar/fa/en/tr (v19)`.
Seed: ٤١ خواردن بە نرخەکانیان (بەرگەری گۆشتی ٥٠٠٠، پیتزای مۆزاریلا ٨٠٠٠، کۆکاکۆلا ٥٠٠٠...) — هەر یەکە `imageUrl` لە سەرچاوەی `_foodIcons` (١٦ ئایکۆنی Material) بەپێی `(name.length + price) % length`.

**١٩. `waiter_tables`** — مێزە تەرخانکراوەکان بۆ وەیتەر:
`waiterId INTEGER NOT NULL`, `tableId INTEGER NOT NULL`, `PRIMARY KEY (waiterId, tableId)`. Seed: وەیتەر ٢ → مێز ١-٥٠، وەیتەر ٣ → مێز ٥١-١٠٠.

**٢٠. `pending_sync`** — وەرگری (ڕدیف)ی ئۆفلاین:
`id INTEGER PK AUTOINCREMENT`, `action TEXT NOT NULL`, `data TEXT NOT NULL (JSON)`, `createdAt TEXT NOT NULL`, `status INTEGER DEFAULT 0`. `markSynced(id)` status=1؛ `getPendingSyncAll()` پێش بۆ flush.

**٢١. `order_delivery`** — بەدواداچوونی گەیشتنی ئۆردەر بۆ چاپکەر:
`tableId INTEGER PRIMARY KEY`, `sentAt TEXT NOT NULL`, `arrivedAt TEXT DEFAULT ''`, `printedAt TEXT DEFAULT ''`, `rejected INTEGER DEFAULT 0`.

**٢٢. `table_locks`** — قووفلی مێز لەکاتی sync:
`tableId INTEGER PRIMARY KEY`, `deviceId TEXT NOT NULL`, `userId INTEGER NOT NULL`, `userName TEXT NOT NULL`, `role TEXT NOT NULL`, `lockedAt TEXT NOT NULL`, `heartbeat TEXT NOT NULL`.

### ٥.٢ Methodە گرنگەکانی `LocalDatabase`
- **Tables**: `getAllTables/getTable/occupyTable/freeTable/requestBill/deleteTable/markAsPrinted/markOverdue/renameTable/updateTableNote/setTablePaid/updateTableStatus/isTableIdTaken/isTableNameTaken/addTable`.
- **Orders**: `getOrderItems/addOrderItem/batchSendAndOccupy/batchSendAndOccupyPending/addItemToOrder/removeOrderItem/updateOrderItemQuantity/transferItems/transferSingleItem/mergeTables/replaceTableItems/clearOrderItems/markOrderArrived/markOrderItemsArrived/markOrderPrinted/markOrderPrintFailed/markOrderRejected/clearSyncedOrders/getPendingOrders`.
- **چاپی ئاستی ئایتم (v46)**: `stampItemPrintResult(tableId, itemIds, printerType, success)` — مۆری گەیشتن/پرێنتی هەر ئایتمێک دەنووسێت (سەرکەوتوو ئەندامێکی `failedPrinters` لادەبەرێت و `printedAt` دادەنێت؛ شکستهێنان ئەندامەکە زیاد دەکات)، پاشان `refreshDeliveryPrintState(tableId)` دۆخی ئاستی مێز نوێ دەکاتەوە. `supersedePrintJobs(tableId)` تەنها دوای **سەرکەوتن** تیکەتە کۆنەکان دەکوژێنێتەوە. `getOrderDeliveries()` هەر ئۆردەرێک بە ئایتمەکانییەوە دەگەڕێنێت.
- **Settle**: `settleTable(tableId, total, discountPercent, discountAmount, userId, shiftId, paymentMethod)` — مێزەکە empty دەکات، لیستی ئیتەمەکان بۆ `settled_orders` + `settled_order_items` تۆمار دەکات، `totalCollected`ی شەفت زیاد دەکات.
- **Shift**: `startShift/closeShift/getActiveShift/getAllShifts/getSettledOrdersByShiftId/getShiftExpenses/getShiftTotals`.
- **Cashier**: `addCashierExpense/getCashierExpenses`.
- **Debts**: `addDebt/getDebts/deleteDebt`.
- **Purchases**: `addPurchase/getAllPurchases`؛ **Refunds**: `addRefund/getRefunds/getRefundsByShiftId`.
- **Cancelled**: `addCancelledItem/getCancelledItems/markCancelledItemServed`.
- **Users**: `addUser/updateUserPin/deleteUser/getUserById/getUserByPin/getUsersByRole/assignTablesToWaiter/getWaiterTableIds/updateUserRange`.
- **Access Code (نوێ)**: `setUserAccessCode/getAllAccessCodes/hasAnyAccessCode`.
- **Menu**: `getFoodCategories/getFoodItems/add/update/delete` + `setItemPrinterTypes/getItemPrinterTypes`.
- **Printer**: `getPrinterConfigs/addPrinterConfig/deletePrinterConfig/setCategoryPrinterMapping/removeCategoryPrinterMapping/setItemPrinterOverride/removeItemPrinterOverride`.
- **Notifications**: `getTableNotifications/addNotification/clearNotifications`.
- **Delivery**: `getOrderDelivery/updateOrderDelivery`.
- **Locks**: `getTableLocks/lockTable/unlockTable/updateLockHeartbeat`.
- **Sync**: `addPendingSync/getPendingSyncAll/getPendingSync/pageMarkSynced/markSynced/markSyncedMatching` + `applySnapshot(Map)` (وەرگرتنی snapshot لە سێرڤێر بۆ stateی تەواو).
- **Backup**: `exportBackup (ramyar_pos_backup_<ts>.db)/listBackups/restoreBackup/resetAllData`.
- **`_emitMutation(action, data)`** — ئەو فونکشنە بناغەییەکەیە: هەموو کردەوە لە ڕێگەی ئەوە دەڕوانێت:
  - ئەگەر `onMutation == null` (offline/چالاک نەبوو) → **خۆکار** `addPendingSync`.
  - ئەگەر `remoteMutationDepth > 0` (ئەم گۆڕانکارییە لە سێرڤێرەوە هاتووە) → ناچێتە pending (دووبارە نەکرێتەوە).
  - ئەگەر `onMutation != null` → ڕەوانەی `sync_provider` دەکرێت (بۆ ناردن بە WebSocket).
- `db.onMutation` لەلایەن sync_provider ئەم callbackە دەبەستێتەوە (لە server یان client).

---

## ٦. سیستەمی سینک (Real-time Sync) — بە وردی

### ٦.١ پۆرتەکان
| ئامێر | پۆرت | شێواز |
|---|---|---|
| سێرڤێر (لابتۆپی کاشێر) | 9876 | WebSocket HTTP upgrade لە `/ws` |
| UDP discovery | 9877 | Broadcast هەر ٢ چرکە `255.255.255.255`، timeout ٦ چرکە |
| Heartbeat | — | هەر ٥ چرکە ping؛ کڵاینت دوای بێ-pong (٣ چرکە) جیا دەبێتەوە |

### ٦.٢ Messageەکان (`sync_types.dart`)
- **`SyncMessage`**: `{ type, action, data (Map), userId, role, timestamp (ISO8601) }` — بە JSON دەنێردرێت.
- **`Type`ەکان**: `client_info`، `ping`، `pong`، `snapshot`، `mutation`، `ack`، `auth_reject`، `print_status`.
- **`AckMessage`**: `{ originalAction, success, printed, tableId, rejected, error, timestamp, itemIds }` — server بۆ کڵاینتی سەرچاوە دەنێرێتەوە دوای apply. `itemIds` = ئەو ئایتمانەی ئەم ackە دەیگرێتەوە (بۆ مۆری `syncedAt`ی هەر خواردنێک).
- `SyncConnectionQuality`: excellent/good/poor/disconnected.

### ٦.٣ کۆرس/flowی پەیوەندی
1. **سێرڤێر** (`startSyncServer`): `PosSocketServer(userId, role)` دروست دەکات، `HttpServer.bind(0.0.0.0:9876)`، دەست پێدەکات به heartbeat + health-check (لادانی clinaynt وقتی `lastSeen > ٢٠ چرکە`). دوای `server.isRunning`، `db.onMutation` بە `_broadcastFromServer` بەستراوەتەوە (هەر گۆڕانکاری زەردەکاتە سەر هەموو کڵاینتەکان).
2. **کڵاینت** (`connectToServer` یان `startAutoDiscovery`):
   - `startAutoDiscovery` → `PosSocketClient` + `db.onMutation` دەبەستێتەوە **دەستبەجێ** (تا ئۆفلاین pending بکات)، پاشان UDP listener دەست پێ دەکات.
   - کاتێک server دۆزرایەوە (`onServerDiscovered`) → `connect(ip, 9876)` → `sendClientInfo()` (لەگەڵ accessCode).
   - ئەگەر `knownServerIp` هەبێت → دوای ٥٠٠ms هەوڵی ڕاستەوخۆ.
3. **client_info** لە سێرڤێر:
   - `onValidateClient(userId, accessCode)`: ئەگەر `hasAnyAccessCode() == true`، کڵاینت پێویستە `accessCode`ی هەمان user بێنێت؛ ئەگەر نا → `auth_reject` + close.
   - سەرکەوتوو → sessionـەکە بە userId/role نوێ دەکرێتەوە + **snapshot** (stateی تەواو) بۆ ئەو کڵاینته دەنێردرێت (`onSnapshotRequest = db.buildSnapshot`).
4. **mutation لە کڵاینت → سێرڤێر**:
   - سێرڤێر بۆ **هەموو ئەوانی تر** بڵاوی دەکاتەوە (`_broadcastToOthers`).
   - بۆ سەرچاوە: `onMutationProcessed` → `_handleServerMutation` → `_applyMutation` (لە داتابەیس). **چاپ خۆکار نییە** — چاپ تەنها بە دەستی لە پەڕەکانەوە بە `dispatchOrderPrintJobs(db, jobs, tableId:)` دەکرێت (claim → dispatch → complete → stamp → broadcast).
   - `sendAckToOrigin` بۆ کڵاینتەکە (success/printed/rejected + `itemIds` ئەگەر ئۆردەرەکە ئایتمی هەبوو).
5. **مۆحاش ← کڵاینت**: `snapshot` → `db.applySnapshot` + `onSyncDataApplied?.call()` (UI تازە دەکاتەوە). `ack` → `markOrderArrived/rejected` + `markOrderItemsArrived(tableId, ack.itemIds)` (مۆری `syncedAt`ی ئایتمەکان؛ بەتاڵ = fallback دروست بۆ هەموو ئایتمەکان)، `markSyncedMatching`، `clearSyncedOrders`، `state.setAck`. `print_status` (نوێ) هەردوو ئاراستەدا دەگوازرێتەوە و `_applyPrintStatusMessage` دەیخوێنێتەوە (printerType + itemIds).
6. **TABLE_LOCK_***: mutationی قوفل بۆ هەمووان بڵاودەکرێتەوە (نە مێژوو apply ناکرێت)، `lockTable/unlockTable/updateLockHeartbeat`.

### ٦.٤ هەموو actionەکانی mutation
`occupyTable`، `freeTable`، `requestBill`، `markAsPrinted`، `markOverdue`، `renameTable`، `updateTableNote`، `markCancelledItemServed`، `notifyTable`، `batchSendAndOccupy`، `addOrderItem`، `batchAddOrderItems`، `removeOrderItem`، `cancelledOrderItem`، `updateItemQuantity`، `addTable`، `deleteTable`، `transferItems`، `transferSingleItem`، `mergeTables`، `settleTable` + `TABLE_LOCK_ACQUIRED/REQUEST/RELEASED/HEARTBEAT`.

### ٦.٥ ئۆفلاین (Pending Sync) — `_flushPendingSync`
- `db.onMutation` کاتێک `client.isConnected == false` → `addPendingSync(action, data)`.
- لە **هەر reconnectـەوە `connected=true` و `firstTime`** (لە `connectToServer` و `startAutoDiscovery` هەردووکی) → `_flushPendingSync`: هەموو pendingەکان بەپێی createdAt (زووترین یەکەم) بۆ ناردن؛ بۆ هەر دانەیەک: ١٠ هەوڵ (هەر هەوڵێک ١٠٠ms چاوەڕوانی + ٣٠٠ms لەگەڵ disconnect)؛ دوای `sendMutation` سەرکەوتوو → `markSynced(localId)`.
- Module-level `_flushingPending` guard: دوو flush لە یەک کاتدا نەبێت.

### ٦.٦ Channel ئەگەر گفتوگۆی ناکۆکی (Conflict) — `order_conflict_resolver.dart`
`resolveOrderConflict(db, tableId, incoming)` → `OrderConflictOutcome`:
- **apply**: مێزەکە ئیتەمی نەبوو.
- **replace**: ئۆردەری نوێ زووتر دروست بووە (`earliestCreatedAt < existingEarliest`) → `replaceTableItems`.
- **rejectDuplicate**: ئۆردەری نوێ دڵنیایی duplicateـە (هەمان name/price/quantity) و لە ئەوەی پێشوو زووتر نا → `applied = false` (reject).

### ٦.٧ Network Discovery — `network_discovery_service.dart`
- سێرڤێر: `startBroadcaster(serverPort)` — بە UDP هەر ٢ چرکە JSONـی `ramyar_pos_beacon` (version 1، ip، port، role='cashier'، hostname) دەنێرێت بۆ `255.255.255.255:9877`.
- کڵاینت: `startListener()` — ئەو beaconانە وەردەگرێت و listـی `DiscoveredServer` نوێ دەکات؛ کە نوێ بێت → `onServerDiscovered`. کە `lastSeen > ٦ چرکە` → لادان (stale cleanup هەر ٣ چرکە).
- **Virtual adapters** (vmware، virtualbox، hyper-v، docker، vpn، tailscale، wireguard، ...) `InterfaceVerdict.reject` دەکرێن؛ `_rankAndSort` ئیفایسەکان هەڵدەستێنێت (ethernet 100 > wifi 90 > virtual -200). `_isPreferredPrivateRange`: 192.168./10./172.16-31.

### ٦.٨ Reconnect (کڵاینت) — `pos_socket_client.dart`
- لە `connect` شکستی → `_scheduleReconnect`: دوای ٢ چرکە (پاش ٥ هەوڵ ٣ چرکە)، زۆرترین ٥٠ هەوڵ؛ پاشان `_restartDiscovery` (stop + start listener).
- Heartbeat: هەر ٥ چرکە ping؛ ئەگەر ٣ چرکە pong نەهات → `onConnectionHealthLost` + `_onDisconnected` → reconnect.
- `_intentionalDisconnect` بۆ logout گرنگە (reconnect نەکات).

---

## ٧. سیستەمی چاپ (Printing)

### ٧.١ جوورەکانی چاپکەر
`PrinterType`: **kitchen** (مەتبەخ) / **bar** (باڕ) / **hookah** (نێرگیلە/قەلیان) / **cashier** (کاشێر).

### ٧.٢ Routing — `print_router.dart`
`routeOrder(items)` → بۆ هەر ئیتەمێک `_resolvePrintersForItem` بە ئەولەویەتی:
1. **`itemPrinterAssignments[item.name]`** (multi) — ئەگەر لە admin_menu printer-mode دیاری کرابێت.
2. **`itemOverrides[item.name]`** (single override).
3. **`categoryMappings[item.category]`**.
4. **Default: kitchen**.
ژماردنی گروپ → بۆ هەر گروپێک `_printerForType(type)`: default یان یەکەم چاپکەری هەوڵدەر لە config.
- `dispatchPrintJob` → `EscPosBuilder.buildKitchenTicket` → `PrinterDiscoveryService.printRaw`.
- `dispatchPrintJobWithFallback` — ئەگەر یەکەمی شکست، چاپکەری fallback (یەکەم چاپکەری تر).
- `dispatchReceipt` (وەسڵی کاشێر) — `EscPosBuilder.buildCashierReceipt`.
- `dispatchRawCommand` بۆ پرۆتۆکۆلەکانی تر.

### ٧.٣ ESC/POS — `esc_pos_builder.dart`
- Commands: `_init` (ESC @)، alignment (ESC a)، bold (ESC E)، double-height (ESC ! 0x10)، cut (GS V b)، feed، encoding (ESC t 0xFF = UTF-8)، char set.
- **`buildKitchenTicket`**: سەرەوە «B I A B L O» + ناونیشانی جۆر («داواکاری مەتبەخ/باڕ/نێرگیلە») + «مێز: X کاپتن: Y» + کات + لیستی ئیتەمەکان (name + xqty + notes) + «کۆی خواردنەکان: N» + قڕکەرەکە.
- **`buildCashierReceipt`**: «وەسڵی کاشێر»، مێز/میوان، کاتی دانیشتن/ڕۆیشتن، بەروار، کاپتن/کاشێر، لیستی ئیتەمەکان (name + xqty + بڕ بە دینار ~IQD)، کۆی یەکەم، داشکاندن (ئەگەر بێت)، کۆی گشتی ، «سوپاس بۆ بەکارهێنانی خزمەتگوزاری ئێمە».
- Formatting: `_fmtP` نرخ بە «١٢,٠٠٠» (هەزارکۆما)، `_fmtTime` بە «٢٠٢٦/٠٩/٢٢ ١٤:٣٠»، width ٤٠ کاراکتر.

### ٧.٤ ناردن — `printer_discovery_service.dart` + `printer_service.dart`
- `PrinterDiscoveryService`:
  - **Windows spool** — `flutter_thermal_printer` یان ffi: `printRaw(String printerName, List<int> data)` (لە ڕێگەی Windows spooler).
  - **Network/TCP** — `printRawTcp(ip, port, data)` بۆ چاپکەری IP/تۆڕی.
  - `discoverPrinters()` — لیستی چاپکەرەکانی Windows (`DiscoveredPrinter{name, portName}`).
- `PrinterService`:
  - `printOrder(tableNumber, items, waiterName)` → `PrintJobSummary{total, successful, failed, errors}`؛ ئەگەر هیچ چاپکەرێک نەبوو → error list.
  - `printReceipt(...)` → dispatchReceipt لە **cashier printer** (default یان یەکەم) + fallback.

### ٧.٥ کۆپی/نیشانەکانی چاپ لە UI
- **`print_preview_dialog.dart`**: دیالۆگ – پێشبینینی (نمونەیەک بە `ListView`)، دوگمەی «چاپ» / «پاشەکشە». دوگمەکان: `FilledButton` (بۆ چاپ) + `OutlinedButton` (بۆ داخستن).
- `admin_printer_screen.dart` — بە شیوازی بەش.

---

## ٨. دیزاین و دوگمەکان (Design & Buttons) — پەڕە بە پەڕە

> هەموو پەڕەکان لە **AppColors** (نارنجی primary)، Material 3، cards radius ٢٠، و layoutـی Responsive بەکاردێنن. لە سەرووی زۆربەی پەڕەکان **ProfileIcon** هەیە (login/logout + زبان + settings).

### ٨.١ Login (`login_page.dart`)
- دیزاین: پسەرەوەیەکی شینی وەک هێمای ئەپ (RAMYAR POS)، سەرەوە `Column`: logo گەورە، دوگمەکانی keypad.
- دوگمەکان: **keypad 0-9 + پاککردنەوە** (backspace). لەگەڵ ٤ ژمارە → login خۆکار.
- `PIN` نیشان نادرێت، سکرین `Stack`ی keypad + لیستی ئاماژەکان.
- ڕۆڵەکان: `admin → AdminHomePage`، `waiter → WaiterHomePage`، `cashier → CashierHomePage (Welcome)`.

### ٨.٢ وەیتەر (Waiter) — ٤ پەڕە
**`waiter_home_page.dart`** (٦٨٥):
- سەرەوە: AppBar بە ناو + **ProfileIcon** + **dropdownی وەیتەرەکان** (waiterNamesProvider) بۆ بینینی مێزەکانی وەیتەری تر.
- Gridی مێزەکان (`ResponsiveGridView`؛ مێزەکانی ئەم وەیتەرە — بە `rangeStart..rangeEnd` یان `waiter_tables`). هەر کارتێک `TableCard`. ئەگەر مێز بەتاڵ بێت → stateی guestCount initial ١.
- دوگمەکان لە AppBar: **٢ چرکە داشکردنی refresh** (بۆسەری نیشان وەک `Icons.refresh`)، بۆی notification badge (ژمارەی `table_notifications`)، **settings gear (وەک ProfileIcon onOpenSettings)**, **logout (ProfileIcon)**.
- `initState`: `startAutoDiscovery` + `connectToServer` بە `knownServerIp`؛ `Timer.periodic(٢ چرکە)` → `refreshSilent` (لەگەڵ نین فلیکەر).
- بۆی `waiterNamesProvider` بۆ dropdown: لیستی وەیتەرەکان (`getUsersByRole(waiter)`).

**`table_page.dart`** (٧٣٥) — دیتەیلی مێز:
- دیتەیل: ناوی مێز + ستاتەست (بە رەنگ)، ڕێژەی guest count (زیادکردن/کەمکردن)، note، یۆکۆن.
- **Category chips** (لە مێنیو) لە سەرەوە بۆ فلترکردنی مەنوو؛ `food_items` دەخوێندرێنەوە (لە ٥ زمانەکان سیان). بۆی کەس لەسەر خواردن → زیادکردن بۆ ئۆردەر.
- **Panels**: ئۆردەرەکان (`OrderItem` list بە +qty/ -qty/+quantity، سڕینەوە)، ئەوانەی info.
- دوگمە گرنگەکان: **«بڕیارەکان بە مێژووی»** (چەنە دانەی purchase پێشتر)، **«چاپکردنی گێردی»** (`es pos ticket`)، **«ڕەوانەکردن بۆ چاپکەر/مەتبەخ»** (send order) — `batchSendAndOccupy`، **«چای کۆکردنەوە»** (markAsPrinted)، **back**، **تەنانەت مێز** (profile icon).
- لەکاتی send: `batchSendAndOccupy` بڵاودەکاتەوە + ack بۆ چاپ.
- Guest count: `occupied` دەبێتە؛ `شۆفەر` بۆ settle نشین.

**`order_page.dart`** (٢٥٧): لیستی ئۆردەری مێژوو — بۆ هەر مێزێک: ناوی مێز + کۆی بڕ + کات + دوگمەی **چاپکردنەوەی kitchen ticket** (دووبارە چاپ) + نیشاندانی «سەرسنانی چاپ» (sent/arrived/printed/rejected). «کۆی گشتی ئۆردەر».

**`waiter_settings_page.dart`** (٢١٠):
- سەرەوە: AppBar ناو + back.
- فیلدەکان: **IP سێرڤێر** (`TextField` ئینگلیزی)، **Access Code** (`TextField` بۆ mask کۆد) — هەردووکیان پاشەکەوت دەکرێن (SharedPreferences: `knownServerIp`، `device_access_code`).
- دوگمەکان: **«پاشەکەوت»** (save + `applyAccessCode(code)` + ناردنی `client_info` نوێ بۆ سێرڤێر بەبێ restart)، **«دووبارە هەوڵدان»/«پەیوەندی»**، **«پاشەکشە»**.
- ئاگاداری دۆخی sync: `Consumer`ـی `syncConnectionProvider` — stateی connection (green/red + client count).

### ٨.٣ کاشێر (Cashier) — ٧ پەڕە

**`cashier_welcome_page.dart`** (٣٥٠):
- سەرەوە: ناوی کاشێر + **ProfileIcon**.
- دوگمە سەرەکییە «**دەستپێکی شەفت**» (startShift) — ئەگەر شەفتی چالاک نەبێت. کاتی ئێستا (بۆ کاتژمێر بە `Timer`).
- ئەگەر شەفت چالاک بێت → کاتی دەستپێک + دوگمەی «**بەردەوام بە**» بۆ `CashierHomePage`. دوگمەی «**داخستنی شەفت**» (closeShiftDialog).
- **پستی ئەڵقەی UI**: دەغڵی خۆشحاڵیی داتای ٣ خولەک لە کۆتایی.

**`cashier_home_page.dart`** (١٥٠٨) ✳️ سەرەکی:
- سەرەوە: ناو کاشێر + tabەکان (**هەموو مێزەکان / مامناوەند / ئەوانەی دروست**) + **ProfileIcon** (لەگەڵ logout).
- **Gridی مێزەکان** بە کارتی `TableCard` (هەموو مێزەکان ١-١٠٠) — کلیل بۆ دیتەیلی مێز (`CashierUnifiedTablePage`).
- دوگمەکانی AppBar: **refresh ٢ چرکە**، **+ Sfilter** (بینینی حیسابەکانی تایبەت یان هەموو)، **NotificationBell**.
- **تەبەل «حیسابەکان»**: Coordinator ئەو حیسابانەی بێ discount/گەیشتوون (settled) — بە `expanded`؛ سەربەرەوەخلو = لیستی مێزەکانی settlement لە shiftی ئەو.
- **بارەکانی کاشێر**: نمایشی کۆی گشتی حیسابەکانی shift (لە `getSettledOrdersTotalByShiftId`)، وە **نووسینی خەرجی** (`+ cashier expense` bottom sheet).
- **کاتژمێر**: دەتوانێت ببینێت کەم/زۆر.

**`cashier_unified_table_page.dart`** (١٩٦٧) ✳️ سەرەکیترین پەڕە بۆ مێزەکان:
- AppBar: ناوی مێز + ستاتەست + guest count + **خۆی گشتی** («سەربەرەوە: X»).
- Tabەکان: **«ئۆردەر»** و **«دیتەیل/ئەنجام»**.
- لە tab ئۆردەر:
  - Category chips + gridی مەنوو (بە ٥ زمان) + note.
  - لیستی ئۆردەرەکان: هەر ڕۆ، دوگمەی **+/-qty**، **سڕینەوە**، تێبینی، وە **trade/بار**.
- لە tab دیتەیل (ئەنجام):
  - **«سەربەرەوەی ئۆردەرەکان»** (subtotal)، فیلتەری **discount %** (`Slider` + `TextField`)، بڕی discount، وە **کۆی گشتی final**.
  - دوگمەی **«بڕیارەکان»/«داشکاندن»**? ن، دوگمە گرنگ: **«داخستن و سەرەکی حیساب»** (`settleTable`) کۆ دیالۆگـی پارەدان (cash/fib/switch/superqi/nass)، **«چارەسەری کێشەی پارە»**، **«بە پارە دابوون»**, **«گواستنەوە بۆ قەرز»** (`debt`)، **«سەربەرەوەی چاپ کردن»** (print receipt)، **«بەقایمانەوە بۆ هەموو خواردنەکان»** (`sentToCashier`).
  - **گواستنەوە**: `transfer_page` بۆ گواستنەوەی تەواو، `merge_page` بۆ تێکەڵکردن.
  - نووسینی **ئەنتەر وەکقەرز**، وە **میوانльное.
- هاوکات هۆک وەک: `bottom_sheet`ی کاش ایەر یان card pay (بۆ payment).

**`cashier_cancelled_items_page.dart`** (٢٩٦): لیستی ڕەتکراوەکان (tab مێژوو) — هەر ڕۆ: «**گواستنەوە بۆ مێز**» (گەڕاندنەوە بۆ ئۆردەر)، نمایشی `shiftId`/cancelledBy/status. کۆی گشتی ڕەتکراوەکان.

**`transfer_page.dart`** (٢٩٦): هەڵبژاردنی سەرچاوە (`fromTableId`) + هەڵبژاردنی ئامانج (`toTableId`) بە `DropdownButton` یا لیست — دوگمەی **«گواستنەوە»** (`transferItems` mutation) + «پاشەکشە».

**`merge_page.dart`** (٣٨١): wizardی ٣ هەنگاوی:
١) هەڵبژاردنی سەرچاوە، ٢) هەڵبژاردنی ئامانج، ٣) **پشتڕاستکردنەوە** (preview: سەرجەم سەرچاوە → ئامانج بە `transferItems` + حیسابی ئامانج بە کۆی ئەو دووانە) + دوگمەی «ئەنجام» (mergeTables) و «پاشەکشە».

### ٨.٤ ئادمێن (Admin) — ١٥ پەڕە

**`admin_home_page.dart`** (١٨٩):
- داشبۆرد: **GridViewـی ١٣ دوگمە** (کارتی گەورە) بە ئایکۆن:
  بەکارهێنەرەکان، مێنیو، حیسابە داراییەکان، داواکارییەکان، شەفتەکان، کڕینەکان، ڕەفزەکان، قەرزەکان، بەکاپ، ستاتیسیی وەیتەر، داواکاریی خواردن، فلتری چاپکەر، چاپکەرەکان.
- AppBar: **logout** (دوگمەی «`_confirmAndLogout`» + دیالۆگ بۆ پشتڕاستکردنەوە) — داواکاری ٢، لەگەڵ **ProfileIcon** (زمان/تنظیم).

**`admin_users_page.dart`** (٥٥٢):
- ٣ tab: **وەیتەرەکان / کاشێرەکان / ئادمێن**.
- هەر tab: ListView بۆ بەکارهێنەرەکان (ناو + PIN + range). دوگمەکان: **«+ زیادکردن»** (bottom sheet: ناو + PIN + role + range)، **سڕینەوە**، **گۆڕینی PIN**، **مێزە تەرخانکراوەکان** (کیبۆردی مێژوو، بۆ range یان assignTablesToWaiter).
- **IP/Access Code (نوێ، داواکاری ٣)**: بۆ هەر بەکارهێنەر: دوگمەی **«IP/کۆد»** — كۆدی تایبەت بۆ ئەو user (`_generateUniqueCode`) نمایش دەکرێت + دوگمەی «دروستکردنەوە» (`setUserAccessCode`) + کۆپی (ینgin).

**`admin_menu_page.dart`** (٩٠٥):
- ListViewی بەشەکان (`FoodCategory`): بە **icon** + ناو لە ٥ زمان + دۆتەکانی printer mapping.
- دوگمە: **«+ زیادکردنی بەش»**، **Edit/Delete** بۆ بەش، بۆ هەر بەشەکە: **«+ زیادکردنی خواردن»** (sidebar/bottom sheet).
- بۆ هەر خواردن: ناو/نرخ/بۆشەکە + **5-language names** لە `name_ar/fa/en/tr`.
- **Printer-mode** (toggle): هەڵبژەریاردنی ئیتەمەکان → بۆ هەر ئیتەم: `checkbox`ی kitchen/bar/hookah/cashier → پاشەکەوتی `itemPrinterAssignments`.

**`admin_accounts_page.dart`** (٢٢٣):
- سەرەوە: AppBar + **Filter**: date range (default ٧ ڕۆژ) + Quick chips (ئەمڕۆ/دوێنی/٧ ڕۆژ/٣٠ ڕۆژ/هەموو).
- لیست/پانێڵ: **کۆی گشتی** (هەموو settled) + **کڕینەکان (purchases)** + **خەرجییەکان** + **سوود (net)** = earnings - purchases - expenses. بۆ هەر ڕۆژ/ژمێرە: دانەی فرۆش/بڕ.

**`admin_orders_page.dart`** (٤١٠):
- فلتر (هەموو / ئەمڕۆ / ئەم هەفتەیە / ئەم مانگە / تایبەت بە بەروار) + **search** بە ناوی مێز یا کاشێر.
- لیست: هەر ئۆردەرێک (settled): ناوی مێز، کات، بڕ، کاشێر، **دیتەیل** (لیستی خواردنەکان) + دوگمەی **«چاپکردنەوە»** (وەسڵ).

**`admin_shifts_page.dart`** (٢٣٢):
- ListViewی شەفتەکان (`CashierShift`): ناو، کاتی دەستپێک/کۆتایی، `totalCollected`، بەراورد لەگەڵ **system total** (`getSettledOrdersTotalByShiftId`): یەکسان ✅ / زیاتر/کەمتر⚠️ — بۆ دۆزینەوەی ناهاوتێیی.

**`admin_shift_detail_page.dart`** (٨٧٤): ڕاپۆرتی تەواوی شەفت:
- پوختە: کۆی گشتی، کاشێر، کاتەکان.
- **ڕێگاکانی وەرگرتن**: cash/fib/switch/superqi/nass/debt sum per method.
- **ڕەفز + خەرجی + ئەو حیسابانەی بە قەرز**.
- **لیستی settled orders** (expandable بۆ دیتەیلی items) + **ڕەتکراوەکان**.

**`admin_purchases_page.dart`** (٢٠٥): فۆرمی «ناو + نرخ + زیادکردن» => لیست (بە بەروار) => کۆی گشتی + **سڕینەوە**.

**`admin_refunds_page.dart`** (٢٠٤): لیستی ڕەفز (فلتری بەروار) + کۆی گشتی + سڕینەوە.

**`admin_debts_page.dart`** (٢٢٩): لیستی قەرز + ناوی مێز + بڕ + هۆکار + **واسڵکردن (سڕینەوە)** + **سڕینەوە** + کۆی گشتی.

**`admin_backup_page.dart`** (٣٣٠):
- دوگمەکان: **«Export»** (کۆپی `ramyar_pos_backup_<ts>.db`)، **«Restore»** (هەڵبژاردنی فایل + پشتڕاستکردنەوە + رستۆر)، لیستی backups + **«Reset All»** (`resetAllData` بە دیالۆگی پشتڕاستکردنەوە) + سڕینەوە.

**`admin_captain_intelligence_page.dart`** (٩٥): ستاتیسی هەر وەیتەر لە ٣٠ ڕۆژی کۆتایی: ژمارەی ئۆردەر + کۆی بڕ (لە settled orders بە `waiterId`).

**`admin_food_demand_page.dart`** (١٦٥): داواکاری خواردن: کۆی quantity فرۆشراو - cancelled، بە فلتری بەروار.

**`admin_food_filter_page.dart`** (٣٨٢): فلتری چاپکەر:
- بۆ هەر خواردن: **dropdown یان چوار چوارچێوەی پرۆگ (kitchen/bar/hookah/cashier)** بۆ mappingی چاپکەر. دۆتی ڕەنگی نمایشی assignment لێدەدرێت. دوگمەی **«بە هیچ چاپکەرێک پەیوەست نەبێت»** بۆ لادان. پاشەکەوت → `setItemPrinterOverride`.

**`admin_printer_screen.dart`** (٥٠٥):
- **«سکان/دۆزینەوەی چاپکەر»** (`discoverPrinters`) → لیست.
- هەڵبژاردنی جوور (kitchen/bar/hookah/cashier) بۆ هەر چاپکەر --> save `printer_configs`.
- **Category mapping**: بۆ هەر کەتگۆری، چاپکەرێک.
- **Item override**: بۆ هەر خواردن، چاپکەری تایبەت.
- **Set default** بۆ چاپکەری cashier. سڕینەوە.

---

## ٩. Widgets هاوبەش

- **`table_card.dart` (١٩٢)**: کارتی مێز لە grid. `status` → رنگ:
  - `empty` → ڕەنگی خاڵ/نور؛ `occupied` → سەوز؛ `billRequested` → شین؛ `overdue` → سوور (پاش ١٠ خولەک).
  - نمایش: ناوی مێز + guest count + total amount (بە دینار)، `sentToCashier` badge، notification badge. کلیل → callback.
- **`profile_icon.dart` (١٥٠)**: ئایکۆنی پرۆفایل لە AppBar: menu (logout + language picker) + `onOpenSettings`. Language picker (٥ زمان).
- **`print_preview_dialog.dart` (٢٨٣)**: پێشبینینی چاپ پێش ناردن.
- **`currency_converter.dart` (١٧٠)**: گۆڕینەوەی نرخ USD⇄IQD (نرخ: ١٤٥٠ بۆ ئێستا یان `_rate` لە وەشانی کۆد). ڕاژە بۆ cashier_table.
- **`close_shift_dialog.dart` (٩٩)**: دیالۆگی تأکیدی داخستنی شەفت: پیشاندانی «بڕی چاوەروان» (system total لە shift) + دوگمەی **«داخستن»** (closeShift) و **«پاشەکشە»**.
- **`cash_calculator_dialog.dart` (٤٣٥)**: حیسابی ک轰轰: دەخوێنێتەوە IQD/USD، دوگمەی **«گۆڕینەوەی ئاڕاستە» (USD⇄IQD toggle)**، دوگمەکانی عدد، پۆست، summary + **«پەسەند کردن»** (کۆی ڕەسەن دەکات) — بۆ کاشێر ئهوانه.

---

## ١٠. تێستەکان (Tests) — ٨ فایل + ١ integration

**هەموو تێستەکان پاس دەبن (94/94) + `flutter analyze` 0 هەڵە.**

| فایل | چی تاقی دەکاتەوە |
|---|---|
| `app_smoke_test.dart` | ئەپ لە سەرەتا دەچێتە LoginPage کاتێک هیچ session نەبێت (بە `ProviderScope` + fake db). |
| `login_flow_test.dart` | سێ ڕۆڵ (Admin 3344 / Waiter 1122 / Cashier 2233) لە PINـەوە دەچنەوە پەڕە گشتییەکانیان. |
| `local_db_test.dart` (320) | تمام CRUD + order_delivery transitions (sent→arrived→printed/rejected) + مێژوو settle + قەرز/کڕین/ڕەفز. |
| `table_bill_color_test.dart` | ڕەنگی مێز: occupied=sەوز، billRequested=شین (تەنها بۆ ئەو مێزەی داواکراو)، overdue=سوور دوای ١٠ خولەک. |
| `responsive_test.dart` (48) | هەموو پەڕە سەرەکییەکان لە ٨ وێنەی (320→1920px) — هیچ overflow/هەڵەی layout نییە. |
| `offline_sync_test.dart` | ئۆردەری ئۆفلاین → `pending_sync` → reconnect → `_flushPendingSync` → ack → `order_delivery`. |
| `sync_integration_test.dart` | وەیتەر + server: mutationناردن + ack. |
| `order_conflict_resolver_test.dart` | apply / rejectDuplicate / replace بەپێی `earliestCreatedAt`. |
| `integration_test/close_shift_test.dart` (Windows) | شەفت دە٪ـە + بەبێ هیچ بڕ، `closeShift` → `totalCollected` دەبێتە ٠. |

**چۆن لێی وادەکەین**: `flutter test` (بۆ ٨ فایلەکە). بۆ integration: هەر فایلێک بە ناوی خۆی ڕەن بکە، بۆ نموونە `flutter test integration_test/admin_shift_report_flow_test.dart -d windows` یان `flutter test integration_test/captain_cashier_order_flow_test.dart -d windows`. تێستەکانی integration بە کۆمەڵ مەخە کار (`flutter test integration_test`)، چونکە `close_shift_test.dart` **داتابەیسە ڕاستەقینەکە دەگۆڕێت** (شەفتی چالاک دەداتەوە)؛ ئەوە تەنها بە `$env:RAMYAR_REAL_DB_TEST='1'` کاردەکات (پێویستیە سینک نەبوو/ RAMYAR POS ڕاگیراوە).

---

## ١١. بنیادنان و جێگیرکردن (Build & Deploy)

- **Windows (کاشێر/سێرڤێر)**: `flutter build windows` → `build\windows\x64\runner\ramyar_pos.exe`.
  - > **ئاگاداربە** بۆ sync تست/بێلد: پێشەوە `Get-Process -Name "ramyar_pos" | Stop-Process -Force` بکە چونکە پۆرتەکانی 9876/9877 بە کار دەگرێت.
- **Android (مۆبایلەکانی وەیتەر)**: `flutter build apk --debug` → `build\app\outputs\flutter-apk\app-debug.apk` (پاشکۆ `com.kalakchi.ramyar.pos`).
- **دامەزراندن بە adb**: `adb install -r <apk>` + `adb shell pm clear com.kalakchi.ramyar.pos` + `adb shell am start -n com.kalakchi.ramyar.pos/.MainActivity`.
- **پێوانەی ڕاستەقینە**: لابتۆپی کاشێر IP لە `waiter_home_page`ـا `192.168.8.97:9876` (وەک known-server)؛ مۆبایلەکان لە ڕێگەی UDP 9877 خۆکار سێرڤێرەکە دەدۆزنەوە.

---

## ١٢. داواکارییەکانی نوێ (Verified)

- **داواکاری ١ — FlushPendingOnReconnect**: لە `sync_provider.dart`: لە هەر disconnected→connected (بە `wasConnected`/`firstTime`)، `_flushPendingSync` بانگ دەکرێت؛ هەنگاوەکە لە هەردوو `connectToServer` و `startAutoDiscovery` دا هەیە؛ `_flushingPending` guard ماکی. ✅
- **داواکاری ٢ — Admin logout**: `admin_home_page.dart` AppBar actions: ئایکۆنی logout + `_confirmAndLogout()` (دیالۆگ) + `authProvider.logout()` => گەڕانەوە بۆ Login. ✅
- **داواکاری ٣ — IP/Access-code enforcement**: ڕەهەندەکانی ٣ دانەی: clients نابێت گوێنەرەوە بۆ server یان cross‑connect بکەن بەبێ access code تایبەتی user:
  - DB v29 `users.accessCode`
  - `setUserAccessCode/getAllAccessCodes/hasAnyAccessCode`
  - Client: `sendClientInfo` (لەگەڵ accessCode) + `updateAccessCode`
  - Server: `onValidateClient` — ئەگەر هیچ code نەبێت، هەمووان پەسەندن؛ ئەگەر بێت، server هەر کڵاینتی بەبێ کۆدی ڕاست بۆ userی ئەو رد دەکات (`auth_reject` + close).
  - UI: `admin_users_page` (دوگمەی IP/کۆپێ/دروستکردنەوە) + `waiter_settings_page` (fields بۆ کۆد + IP). ✅
- **پێشنیار**: نووسینی ئەم `PROJECT_MAP.md` وەک کۆنتێکستی تەواو بۆ Gemini. ✅

> **چی ماوە بۆ دڵنیایی**: تەلەفونی Android بە adb ببەسترێت و داواکارییەکان لەسەر مۆبایل ڕاستەوخۆ پشتڕاست بکرێنەوە (عەقلی — فلۆوی pending لە reconnect، logoutی ئادمێن، سینکی کۆدی access).