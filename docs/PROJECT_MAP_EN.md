# RAMYAR POS — Complete Project Map in English

> This file is a complete, non-technical map of the **RAMYAR POS** restaurant app:
> what it does, the roles, every screen, every button on every screen, the file
> names and locations, the number of pages, the database, and the tests.
> Written so anyone — no programming background needed — can understand the
> whole system. Screen labels are quoted in the app's default language
> **Kurdish (Sorani)** with an English translation in brackets.

---

## 1. What is RAMYAR POS?

**RAMYAR POS** (app id: `com.kalakchi.ramyar.pos`) is a **Flutter** app for running a
restaurant. It is an **offline-first, real-time sync** system:

- The **laptop/desktop** (usually the **cashier** terminal) acts as the **central
  server**.
- The **waiters' phones** (Android) connect to it over the restaurant's Wi-Fi.
- Every device works on its own copy of the data, so nothing stops working when
  the Wi-Fi is briefly lost — orders wait in a queue and sync automatically when
  the connection returns.

### How a normal day works (main flow)

1. Every device has its own copy of the database (a local SQLite file).
2. The laptop opens a **server** on **port 9876** and announces itself on the
   Wi-Fi (**UDP broadcast on port 9877**).
3. Waiter phones **automatically discover** the server and connect.
4. Any change in the database (table occupied, order, payment, transfer…) becomes
   a **sync message** sent to the server; the server **forwards it to all other
   devices** and confirms it.
5. When the connection is lost, changes go into a **pending-sync queue**
   (`pending_sync`) and are **sent automatically** when the connection returns.
6. Printing goes to **thermal printers** (ESC/POS) in four roles:
   **Kitchen / Bar / Hookah / Cashier**.

---

## 2. Roles (who uses the app)

| Role | What they do |
|---|---|
| **Waiter (وەیتەر / کاپتن – Captain)** | Sees the tables, takes food orders, prints kitchen tickets, sends the bill request, watches delivery status of every order they sent. |
| **Cashier (کاشێر)** | Starts/closes shifts, settles (closes) tables by cash or card, issues debts, transfers and manages table bills, records expenses. |
| **Admin (ئادمێن)** | Manages users, the menu, financial reports, shifts, purchases, refunds, debts, backups, printers, food-demand statistics. Also hosts the sync server on the laptop. |
| **Owner (خاوەن سیستەم – System Owner)** | Special role that can always log in (even before any IP is registered). Manages staff accounts and the central server IP address. |

### How staff log in (login + Connect-IP flow)

- Every staff account is created with a **personal 5-digit PIN** and a **personal
  IP access code** (e.g. `192.168.10.7`).
- The device must first **bind to that account's IP** using the **“Connect to IP”
  (بەستنەوە بە IP)** screen — otherwise only the owner can log in.
- One device can hold **many IPs** (up to 100), so e.g. one tablet can serve both
  the Admin and the Captain accounts. Each account then unlocks with its own PIN.
- After a successful PIN entry the app opens the correct home screen for the role.

---

## 3. The app in numbers

- **Screens (pages): 31** — 2 login screens, 2 owner screens, 5 waiter screens,
  7 cashier screens, 15 admin screens (one of which is the printer-setup screen),
  plus 2 name aliases (`LoginPage`, `AdminUsersPage`) that simply point to
  existing screens.
- **Roles: 4** (Waiter, Cashier, Admin, Owner).
- **Database: version 30**, 22 tables.
- **Languages: 5** (Kurdish Sorani, Arabic, Persian, English, Turkish).
- **Tests: 11 test files, 115 tests — all passing**, and `flutter analyze` is
  clean (0 warnings).
- **File tree** with sizes is in section 4.

---

## 4. Project structure — file names and locations

Everything lives inside the project folder. The two main folders are **`lib`**
(the app) and **`test`** (the tests).

### 4.1 `lib` — the app code (by folder)

```
lib/
├── main.dart                          (39 lines)  — app starting point
├── core/
│   ├── app.dart                       (211)  — the app shell; picks home page by role
│   ├── colors.dart                    (21)   — the colour palette
│   ├── constants.dart                 (28)   — shared constants (padding etc.)
│   ├── language.dart                  (51)   — the 5 app languages
│   ├── responsive.dart                (227)  — phone / tablet / desktop layouts
│   └── theme.dart                     (96)   — overall look & feel
├── models/       (data shapes used everywhere)
│   ├── user_model.dart                (38)   — a user account + role + IP code
│   ├── table_model.dart               (117)  — a restaurant table
│   ├── order_model.dart               (69)   — an order / order item
│   ├── menu_model.dart                (52)   — menu section + food item
│   ├── settlement_model.dart          (224)  — a settled (paid) order
│   ├── debt_model.dart                (45)   — a table debt
│   ├── cashier… models                – shift, purchase, refund, cancelled item,
│   │                                    table lock, notification, delivery status
│   └── printer_model.dart             (109)  — a printer + its type
├── providers/     (state / "memory" of the running app)
│   ├── auth_provider.dart             (133)  — who is logged in, login notice
│   ├── waiter_provider.dart           (209)  — waiter's tables & orders
│   └── printer_provider.dart          (67)   — configured printers
├── services/      (the "engine room")
│   ├── app_localizations.dart         (2276) — all 5 languages' texts
│   ├── sync_provider.dart             (840)  — sync control, connect, server start
│   ├── pos_socket_server.dart         (396)  — the WebSocket server (port 9876)
│   ├── pos_socket_client.dart         (238)  — the WebSocket client
│   ├── network_discovery_service.dart (262)  — finds the server on the Wi-Fi
│   ├── network_guard_service.dart     (205)  — checks restaurant Wi-Fi is on
│   ├── printer_service.dart           (125)  — sends text to a thermal printer
│   ├── printer_discovery_service.dart (259)  — finds printers on the network
│   ├── esc_pos_builder.dart           (244)  — builds printer receipt commands
│   ├── print_router.dart              (166)  — decides which printer gets what
│   ├── order_conflict_resolver.dart   (42)   — solves order clashes on sync
│   ├── menu_helper.dart               (27)   — menu icons
│   ├── food_localization.dart         (26)   — food names in several languages
│   ├── owner_credentials.dart         (52)   — the owner's fixed PIN
│   └── sync_types.dart                (99)   — message types used in syncing
├── database/
│   └── local_db.dart                  (2385) — the SQLite database (all tables)
├── widgets/       (reusable building blocks shown inside pages)
│   ├── role_users_tab.dart            (590)  — add/edit/delete staff accounts
│   ├── table_card.dart                (192)  — one coloured table on a grid
│   ├── profile_icon.dart              (151)  — avatar + language menu
│   ├── currency_converter.dart        (170)  — USD ⇄ IQD converter
│   ├── print_preview_dialog.dart      (284)  — preview before printing
│   ├── close_shift_dialog.dart        (99)   — close cashier shift
│   └── cash_calculator_dialog.dart    (435)  — cash payment calculator
└── page/          (the 31 screens — see section 5 for every button)
    ├── login/     LoginPage (alias), pin_login_page, connect_ip_page
    ├── owner/     owner_home_page, ip_settings_page
    ├── waiter/    waiter_home_page, table_page, order_page, order_delivery_page,
    │              waiter_settings_page
    ├── cashier/   cashier_welcome_page, cashier_home_page,
    │              cashier_unified_table_page,
    │              cashier_cancelled_items_page, transfer_page, merge_page
    └── admin/     admin_home_page, admin_user_management_page (alias admin_users_page),
                   admin_menu_page, admin_accounts_page, admin_orders_page,
                   admin_shifts_page, admin_shift_detail_page, admin_purchases_page,
                   admin_refunds_page, admin_debts_page, admin_backup_page,
                   admin_captain_intelligence_page, admin_food_demand_page,
                   admin_food_filter_page, admin_printer_screen
```

### 4.2 `test` — the test files (11 files, 116 tests)

```
test/
├── app_smoke_test.dart        – app starts on the login screen when no one is logged in
├── connect_flow_test.dart     – Connect-IP + PIN login; multi-IP device binding (7 tests)
├── login_flow_test.dart       – Admin / Captain / Cashier reach their home screens by PIN
├── local_db_test.dart         – every database operation (users, orders, debts, …)
├── ip_settings_test.dart      – owner IP settings page
├── offline_sync_test.dart     – orders are queued offline and sync back later
├── order_conflict_resolver_test.dart – order clash fixing
├── owner_credentials_test.dart – the owner can always log in
├── responsive_test.dart       – screens look right on phone / tablet / desktop
├── sync_integration_test.dart – real server + client sync over sockets
└── table_bill_color_test.dart – table colours (occupied/bill/overdue)
```

---

## 5. Every screen and every button

> Legend: each line lists the control, the **Kurdish label** *[English]* and what
> it does. “Role” says who sees that screen.

---

### 5.1 LOGIN & CONNECT (everyone, before logging in)

#### A. PIN Login screen — `lib/page/login/pin_login_page.dart` (alias `login_page.dart`)

**What it is:** The 5-digit-PIN sign-in screen for all staff. Verifies the device
is on the restaurant Wi-Fi, then opens the right home screen for the role.

**Role:** everyone (it is the lock screen).

- **Language dropdown** — *globe icon* — switches the whole app between Kurdish,
  Arabic, Persian, English, Turkish — top of screen.
- **5 PIN dots** — show how many digits were typed — top of PIN card (display only).
- **Number keys 1–9, 0** — type the PIN — keypad grid.
- **Backspace key** — deletes the last digit — keypad bottom-left.
- **Confirm key** *[log in]* — check-circle icon; turns into a spinner while
  checking — checks the PIN and opens the role's home screen; disabled until 5
  digits are typed or when offline — keypad bottom-right.
- **“بەستنەوە بە IP”** *[Connect to IP]* — button with a white “!” badge — opens
  the Connect-to-IP screen — below the PIN card.
- **Offline banner** — red box “Wi-Fi Disconnected. Connect to the restaurant
  network to log in.” — shown only when the Wi-Fi is lost; the keypad greys out.
- **“تۆڕ لە دەست چوو” dialog** *[Network Lost]* — appears automatically after
  the network drops; button **OK (باشە)** closes it.
- **Snackbars:** “وشەی نهێنی هەڵەیە” *[Wrong PIN]* (~1 s) and any server login
  notice (~3 s); the keypad resets after each.

#### B. Connect to IP screen — `lib/page/login/connect_ip_page.dart`

**What it is:** Here a device binds to the owner-issued account IPs (up to 100),
so each listed account can log in with its own PIN. Until at least one IP is
entered, only the owner can log in on this device.

**Role:** everyone (pre-login).

- **Back arrow** — returns to the PIN login screen — top-left.
- **“سڕینەوەی هەموو”** *[Delete all]* — clear the whole saved IP list — top-right
  (only when IPs exist).
- **IP input field** — hint `192.168.1.10`, digits + dots only — type an IP.
- **“زیادکردن”** *[Add]* — plus icon — checks the IP format, rejects duplicates,
  enforces the 100-IP limit, adds the IP — next to the field.
- **IP chips** — one chip per saved IP, each with a red **×** — remove just that
  IP — center of screen.
- **“کۆنێکت”** *[Connect]* — saves all listed IPs as this device's access codes,
  connects, and after success pops back to the PIN screen with a green message.
- **“گەڕانەوە بۆ چوونە ژوورەوە”** *[Go back to login]* — return to the PIN screen.
- **Server hint** — shows the currently known server IP.
- **Snackbars:** invalid IP, “reached 100 IPs”, “already added”, “IP added”,
  “add at least one IP first”, “Connected — now log in with your PIN” (green),
  “Connection failed…” (red).

---

### 5.2 OWNER SCREENS

#### A. Owner home — `lib/page/owner/owner_home_page.dart`

**What it is:** The owner's dashboard: one tab per role showing every staff
account with its live 5-digit PIN. List refreshes instantly when a user is added,
edited or deleted anywhere (local or synced).

**Role:** owner only.

- **“خاوەن سیستەم”** *[System Owner]* — app-bar title with a premium badge.
- **Owner avatar menu** — opens the 5-language menu (no settings/logout here).
- **“ڕێخستنی IP”** *[IP settings]* — router icon — opens the IP settings screen — app bar.
- **“دەرچوون”** *[Log out]* — confirmation dialog **Cancel (ڕەتکردنەوە)** /
  **Log out (دەرچوون)**.
- **Tab “کاپتن”** *[Captain]* — staff accounts of waiters — pinned tab bar.
- **Tab “کاشێر”** *[Cashier]* — cashier accounts — same tab bar.
- **Tab “ئادمێن”** *[Admin]* — admin accounts — same tab bar.
- (Inside each tab, the **account list** with all its IP/PIN/delete buttons is the
  shared **Role Users Tab** — see section 6.)

#### B. IP settings (owner) — `lib/page/owner/ip_settings_page.dart`

**What it is:** The owner types the IP of the central server device; every device
on the network then uses that one address.

**Role:** owner only.

- **Back arrow** — back to owner home.
- **IP field** — label “ئای-پی سێرڤەر” *[Server IP]*, hint `192.168.X.Y` — prefilled.
- **“پاشەکەوتکردن”** *[Save]* — save icon — validates the IP, saves it, reconnects
  to the new address immediately — red snackbar if the format is wrong, green on
  success.
- **Device IP note** — “ئای-پی ئەم ئامێرە: <ip>” *[This device's IP]* — for
  comparison — shown below, hidden when offline.

---

### 5.3 WAITER SCREENS

#### A. Waiter home (tables grid) — `lib/page/waiter/waiter_home_page.dart`

**What it is:** The waiter's dashboard — a live grid of all tables with colour
codes, plus add-table, connection, delivery-inbox and account controls.

**Role:** waiter only.

- **“زیادکردنی مێز”** *[Add table]* — a **slim orange pill** (32 px tall, kept
  long sideways, a top→bottom orange-only gradient — no second hue) that opens
  the **Add-table dialog** (table number/name field; **Cancel (ڕەتکردنەوە)** /
  **Add (زیادکردن)**; duplicate names show “sorry, this table already exists”).
- **Connection pill** — shows Disconnected (red), Connected (amber), Sent (blue),
  Printed (green), Rejected (red block) — tap to connect/disconnect.
- **Delivery inbox** — envelope icon with a badge (number of waiting/rejected
  deliveries) — opens the **Order delivery status** screen.
- **Captain avatar menu** — the role label reads **کاپتن** *[Captain]* (not
  “وەیتەر”); **Settings (ڕێخستن)** opens **Waiter settings**; **Log out
  (دەرچوون)** with confirmation (Cancel / Log out).
- **Table cards** (tappable) — statuses: **Empty (بەتاڵ)**, **Customer seated
  (موشتەری دانیشتووە)**, **Account requested (داوای حیسابی کردووە)**, **Overdue
  (دواکەوتوو)** (red after 10 minutes). Each card shows the table name, seated
  time and total in IQD.
  - **Tap an empty table** → guest-count dialog **“چەند کەسن؟”** *[How many
    people?]* with number tiles 1–7 → opens the table's order screen.
  - **Tap an occupied table** → if another user has locked it, a red snackbar
    “sorry, this table is open by {role} {user}" blocks it; otherwise opens the
    table's order screen.
- **Retry button “هەوڵدنەوە”** *[Retry]* — shown on load error — reloads the grid.
- **Live:** refresh + overdue check every 2 seconds; auto-connect to server on open.

#### B. Table order screen (waiter) — `lib/page/waiter/table_page.dart`

**What it is:** Build a table's order: pick items from the menu, adjust
quantities, choose whether to print kitchen tickets, send the order to the
cashier. Locks the table while open so nobody else can open it.

**Role:** waiter only.

- **“مێزی {number}”** *[Table {number}]* — app-bar title.
- **Transfer table** — swap icon — opens the **Transfer** screen.
- **Notify cashier** — notification icon (or “ئاگەدارکردنەوە” *[Notify]* button on
  tablets) — pings the cashier.
- **Category sidebar/chips** — “All (هەموو)” + one per menu category — filter the menu.
- **Menu item tiles** — icon, name, IQD price — tap to add to the pending order.
- **Pending-order rows** — **− / + / delete** buttons adjust or remove each item.
- **“چاپ” checkbox** *[Print]* — whether kitchen tickets print when sending (on by default).
- **“کۆی گشتی”** *[Grand total]* — total displayed at the bottom.
- **Send button “ناردن”** *[Send]* — sends the order (flags table as occupied);
  prints kitchen tickets via the **Print preview** dialog when printing is on
  (**Cancel / Print (چاپکردن)**). Empty cart shows disabled **“خواردن هەڵبژێرە”**
  *[Choose food]*.
- **Sent-order rows** are listed read-only above (name, waiter, price, time, ×qty).

#### C. Order delivery status (waiter) — `lib/page/waiter/order_delivery_page.dart`

**What it is:** A live “postbox” showing, **per dish**, two truths: did this dish
reach the cashier system, and did this dish's ticket come out of *every* printer
it is assigned to (kitchen, bar, cashier printer, hookah room)?

**Role:** captain / waiter only.

- **Refresh button** — reloads the list — app bar.
- **Connection banner** — yellow “{n} orders waiting for connection” when
  disconnected; green “Sync is active (سینک چالاکە)” when connected.
- **Item-level filters** — “All (هەموو)”, “Arrived (گەیشت)”, “Not arrived
  (نەگەیشت)”, “Printed (پرێنت)”, “Reprint (دوبارە پرێنت)”, each showing a
  **dish count**. Arrived/Not-arrived = per-dish confirmation from the till;
  Printed/Reprint = per-dish ticket state. Any dish that still owes a ticket
  appears under “Reprint”.
- **Legend chips** — Waiting (yellow) / Arrived (blue) / Reprint (yellow) /
  Printed (green) / Rejected (red) (colour key only).
- **Order cards** — “Table {n}, Sent - time”, a status badge, a per-dish
  `arrived/total` and `printed/total` summary, and one row per dish with its
  printer label, arrival icon and print icon. A dish still owing a ticket has a
  one-tap **reprint** button. A card-level button reprints the unprinted dishes
  (or re-sends the whole order when nothing arrived). **Tap** the card to open
  that table's order screen.
- **Live:** updates every 5 seconds.

#### D. Waiter settings — `lib/page/waiter/waiter_settings_page.dart`

**What it is:** Personal device settings: the app language and the personal IP /
access code that the admin issued for this waiter.

**Role:** waiter only.

- **Language section** *(“زمان” [Language])* — one row per language; tap to switch;
  the active one has a check.
- **IP section** *(“نیشانەی IP” [IP address])* — field prefilled with the current
  code (partially masked); **Save (پاشەکەوتکردن)** saves and reconnects —
  green snackbar; empty field shows a red “enter an IP or ask the admin” message.

#### E. Order detail / bill page (waiter) — `lib/page/waiter/order_page.dart`

**What it is:** Review sent items, change quantities, reprint kitchen tickets,
request the bill, print the receipt.
**Note:** this screen is currently **not linked** in the production navigation
(it is kept for tests/compatibility) — the cashier's unified table screen covers
the same functions today.

**Role:** waiter only (by design).

- **Print kitchen tickets** — printer icon — prints via preview dialog.
- **− / + buttons** on each order row — change quantity.
- **“ناردن بۆ کاشێر”** *[Send to cashier]* — flags the table as bill-requested.
- **“چاپی ڕەسید”** *[Print receipt]* — receipt icon — prints a cashier receipt;
  red snackbar “no cashier printer found” if none exists.

---

### 5.4 CASHIER SCREENS

#### A. Cashier welcome / shift gate — `lib/page/cashier/cashier_welcome_page.dart`

**What it is:** A waiting screen for a cashier who has **no active shift**: shows
a live clock, lets the cashier start a shift, continue an existing one, or log out.

**Role:** cashier only.

- **Language dropdown** — switches the app language.
- **“دەستپێکردنی شەفت”** *[Start shift]* — play icon — creates the shift and
  opens the cashier console — shown only when no shift is active.
- **“بەردەوامبوون”** *[Continue]* — opens the cashier console — shown only when a
  shift is already active.
- **“داخستنی شەفت”** *[Close shift]* — stop icon — opens the **Close-shift
  dialog**: shows total expenses, a “total collected (IQD)” field, a live
  net row (collected − expenses), buttons **Cancel (ڕەتکردنەوە)** /
  **Close (داخستن)**.
- **“چوونە دەرەوە”** *[Log out]* — logs out to the PIN screen.
- **Live:** digital clock + date, refreshed every second.

#### B. Cashier console (home) — `lib/page/cashier/cashier_home_page.dart`

**What it is:** The cashier's main workbench: live table grid with filters, an
orders/notifications panel, a debts panel, a USD⇄IQD converter, shift & expense
management, and quick access to cancelled items and previous orders. This is also
where the **sync server** starts on the laptop device.

**Role:** cashier only.

**Top bar (left to right):**
- **Language dropdown** — switches language.
- **“دەستپێکردنی شەفت”** *[Start shift]* (when no shift) — with confirmation —
  or **“داخستن و چوونە دەرەوە”** *[Close and log out]* (when a shift is active)
  — closes the shift via the **Close-shift dialog**, then logs out (the only
  logout path on this page).
- **“خەرجیەکان”** *[Expenses]* — red wallet icon, shown only while a shift is
  open — pushes the **Expense ledger page** (see below).
- **“زیادکردنی مێز”** *[Add table]* — opens the add-table dialog.
- **Sync indicator** — Wi-Fi icon + client count (display only).
- **Refresh** — re-checks overdue tables and reloads the grid.
- **Bell** — count of unread table notifications — jumps to the orders panel.
- **“داواکاری پێشوو”** *[Previous orders]* — bottom sheet of the last 30 settled
  orders; each row can **reprint** the receipt.
- **“ڕەتکراوەکان”** *[Cancelled]* — opens the **Cancelled items** screen.
- **Profile avatar** — language menu only (no settings/logout here).

**Expense ledger page — `lib/page/cashier/cashier_expenses_page.dart`:**
The cashier's money-out/money-in ledger for the open shift, pushed from
«خەرجیەکان». One table (`cashier_expenses`) backs both halves: an expense is
stored with a **positive** price, a return with a **negative** one, and the shift
report and «حسابەکان» read the net.
- **App bar** — title «خەرجیەکان», a **search** button (turns the title into a
  filter over names and amounts; carry-on digits like `20000` match `20,000`),
  and a **refresh** button.
- **Two sections under the app bar** — **«خەرجی»** *[Expenses]* and
  **«گەڕانەوەی خەرجی»** *[Expense Return]*, each a scrollable list with a count
  + total card at the top (empty state per section).
- **FAB** — follows the selected section: **Record (تۆمارکردنی خەرجی)** or
  **Return (گەڕانەوەی خەرجی)**; the dialog takes a name (ناوی خەرجی, *why*) and
  an amount (نرخ), Cancel / Record (تۆمارکردن) or Return (گەڕاندنەوەی خەرجی).
- **Replay (گەڕاندنەوەی ئەم خەرجییە)** — every expense row carries a blue replay
  button that reopens the return form **pre-filled** with that row's name and
  amount, so a 20,000 set put in earlier goes straight back as the same 20,000.
- Every write goes through `addCashierExpense` (shift key + sync mutation), so
  the admin sees the same money in «حسابەکان» and the shift report.

**Bottom navigation (3 tabs):**
- **“سەرەکی”** *[Main]* — table grid.
- **“داواکاری”** *[Requests]* — notifications + converter (badge = tables asking for the bill).
- **“قەرزەکان”** *[Debts]* — debts panel.

**Main tab — filter bar:**
- **“هەموو مێزەکان”** *[All tables]*, **“مێزە گیراوەکان”** *[Occupied]*,
  **“مێزە بەتاڵەکان”** *[Empty]* — each with a live count.

**Main tab — table cards (colour-coded like the waiter grid):**
- **Tap occupied table** → opens the **Unified table screen** (Food tab).
- **Tap empty table** → guest-count dialog (‑/+ steppers, Cancel / Start (دەستپێکردن))
  → opens the Unified table screen.
- **Long-press table** → **Table management dialog** with **Delete table
  (سڕینەوەی مێز)**; deleting an occupied table warns that all its data is lost.

**Orders tab (tab 1):**
- **Notification rows** — “View (بینین)” — open the table on its **Bill** tab.
- **Currency converter** — “rate per 100$”, USD field, IQD field — converts live
  both ways as you type (no button).

**Debts tab (tab 2):**
- **Debt rows** — tap to see the items; **“کۆکردنەوەی قەرز”** *[Collect]* per row —
  **Collect-debt dialog**: original debt, amount received, live total; full
  payment deletes the debt, partial payment records a settled “(debt)” order.
- **Debt summary card** — total amount + count.
- **Live:** refresh + overdue check every 2 seconds; badges update live.

#### C. Unified table screen (bill + food) — `lib/page/cashier/cashier_unified_table_page.dart`

**What it is:** One screen for everything at a single table: the **Bill** tab
reviews items and collects payment (cash with a change calculator, card, debt,
discount, print, clear); the **Food** tab adds menu items and sends them to the
kitchen/bar/hookah printers. Locks the table while open.

**Role:** cashier only.

**App bar:**
- **“مێزی {number}”** *[Table {number}]* — title; tabs **“حیساب”** *[Bill]* and
  **“خواردن”** *[Food]*.
- **“زانیاری مێز”** *[Table info]* — table status, seated time, dates, who holds
  the lock — Close (داخستن) dialog.
- **“گۆڕینی ناوی مێز”** *[Change table name]* — edit dialog (Cancel / Change (گۆڕین)).
- **“تبینی”** *[Note]* — leave a note for the admin (Cancel / Save (پاشەکەوتکردن)).
- **Transfer table** — swap icon — opens the Transfer screen.
- **“بەتاڵ کردنەوەی مێز”** *[Empty the table]* — confirmation (Cancel / Empty)
  — deletes all items and frees the table.

**Bill tab:**
- **Item rows** — **transfer** button moves one item to another table
  (Choose target from Empty/Occupied chip groups; Cancel / Transfer (گواستنەوە));
  **delete** button records a refund and removes the item.
- **Discount** — %, -, field with quick preset chips **5/10/15/20/25/50%** and a
  clear button; the totals update live.
- **“چاپکردن”** *[Print]* — prints the receipt to the cashier printer (no preview).
- **“قەرز”** *[Debt]* — confirmation — moves the whole table to the debts section.
- **“واسڵ کردن”** *[Settle]* (cash, green) — opens the **Cash-calculator dialog**:
  bill amount, cash input, live status (less than bill / exact / change to give
  back), quick-fill chips **1000/5000/10000/25000/50000/100000**,
  buttons **Cancel / Settle (واسڵ کردن)** — then settles as cash, prints the
  receipt, pops back.
- **“کارت”** *[Card]* (blue) — pick card type from a list (**FIB / SWITCH /
  SUPERQI / NASS**), confirm (Cancel / Settle) — settles as that card.
- **“پاکردنەوەی مێز”** *[Clear the table]* — confirm (Cancel / Clear) — frees the
  table without charging.

**Food tab:**
- **Category sidebar/chips** — “All (هەموو)” + one per category.
- **Menu item tiles** — tap to add to the pending order.
- **Pending/sent cart** (desktop panel or phone bottom-sheet):
  - **“سڕینەوەی هەموو”** *[Delete all]* — refunds everything (with confirmation).
  - **− / +** on pending rows; **delete** on sent rows (records refund).
  - **“چاپ” checkbox** — print kitchen tickets when sending.
  - **“ناردن”** *[Send]* — sends the order (occupies the table, prints per the
    print setting via preview dialog).

#### D. Cancelled items (cashier) — `lib/page/cashier/cashier_cancelled_items_page.dart`

**What it is:** Lists food items that waiters cancelled, so the cashier can
review and move them to another table.

**Role:** cashier only.

- **Pull-to-refresh** — reloads the list.
- Summary banner: “{count} cancelled items” + IQD total.
- **“گواستنەوە بۆ مێز”** *[Move to table]* on each card — dialog with a grid of
  colour-coded tables (blue = bill requested, red = overdue, green = occupied,
  grey = empty); picking a table moves the item there (creates the table with 1
  guest if empty) and shows a green snackbar; with no tables, a red “no table to
  move to” snackbar.

#### E. Transfer tables (cashier + waiter) — `lib/page/cashier/transfer_page.dart`

**What it is:** Move a table's **entire** order onto another table (empty or
occupied). Used by both cashiers and waiters.

**Role:** cashier and waiter.

- **Filter row** — **All (هەموو)** / **Empty tables (مێزی بەتاڵ)** / **Occupied
  tables (مێزەگیراوەکان)**.
- **Section lists** with counts; empty states “no empty/occupied tables”.
- **Table tiles** — tap to pick source then target: with a fixed source, tapping
  any other table performs the transfer instantly (green snackbar + pop); in free
  mode, first tap selects an occupied source (highlighted), next taps move it.
- (When opened without a source, a **remove** button clears the selection.)

#### F. Merge tables (legacy) — `lib/page/cashier/merge_page.dart`

**What it is:** Combine two tables' items into one, in a 3-step guided flow
(Source → Target → Confirm) with a combined-total preview.
**Note:** currently **not linked** in navigation.
**Role:** cashier only (intended).

- Step indicator (display).
- **Step 1** — tap an occupied source table (empty ones are not selectable).
- **Step 2** — tap a target table (empty allowed); a **“گۆڕین”** *[Change]* button
  goes back to step 1.
- **Step 3** — combined total preview + **“تێکەڵکردن”** *[Merge]* button — merges
  and shows a green snackbar.

---

### 5.5 ADMIN SCREENS

#### A. Admin dashboard (home) — `lib/page/admin/admin_home_page.dart`

**What it is:** The central hub for the admin; also starts the sync server on the
laptop. A grid of 13 tiles opens every admin function.

**Role:** admin only.

- **Logout (دەرچوون)** — red icon — confirmation (Cancel / Log out).
- **Admin avatar menu** — the 5-language menu (no settings/logout here).
- **Dashboard tiles** (tap to open):
  | Tile (Kurdish) | English | Opens |
  |---|---|---|
  | حسابەکان | Accounts | Accounts (money summaries) |
  | مێنیو | Menu | Menu management |
  | زیادکردنی بەکارهێنەر | Add user | User management |
  | ئۆردەرەکان | Orders | Order history |
  | شەفتی کاشێر | Cashier shift | Shifts list |
  | کڕینی ئەشیاکان | Purchases of supplies | Purchases |
  | قەرزەکان | Debts | Debts |
  | ڕەفزەکان | Refunds | Refunds |
  | چاپکەر | Printer | Printer setup |
  | فلتەری خواردن | Food filter | Food-by-printer filter |
  | زیرەکی کاپتن | Captain intelligence | Waiter performance |
  | داواکاری خواردن | Food demand | Sales per food item |
  | بەکاپ | Backup | Backup & restore |

#### B. User management (admin) — `lib/page/admin/admin_user_management_page.dart` (alias `admin_users_page.dart`)

**What it is:** Creates all staff accounts (waiters, cashiers, admins) with a
strict 5-digit PIN and an assigned IP access code, grouped in three role tabs.

**Role:** admin only (the owner uses the same account widget on their screen).

- **Tab “وەیتەر”** *[Waiter]* — waiters' accounts.
- **Tab “کاشێر”** *[Cashier]* — cashiers' accounts.
- **Tab “ئادمێن”** *[Admin]* — admins' accounts.
- (The add-user form and every per-user button live in the shared **Role Users Tab**
  — section 6.)

#### C. Menu management — `lib/page/admin/admin_menu_page.dart`

**What it is:** Create/edit/delete menu sections and items (names in 5 languages,
IQD price, icon), and choose which printers receive each item.

**Role:** admin only.

- **“شوێنی چاپ”** *[Print location]* — printer icon — toggles the printer-assignment
  mode where each item card can be tapped to assign printers (**Bar / Kitchen /
  Hookah / Cashier** checkboxes via long-press; **Apply (جێبەجێکردن)** saves to
  all selected items; **Remove (لابردن)** clears the selection).
- **“زیادکردنی خواردن”** *[Add food]* — plus icon — dialog with name in 5
  languages, price, section, icon; Cancel / Add (زیادکردن).
- **“زیادکردنی بەش”** *[Add section]* — folder icon — dialog: section name, main
  section (**Hot / Cold / Dessert / Cake**), icon; Cancel / Add.
- **Sections sidebar** — tap to filter items; small **edit** and **delete** icons
  per section (delete warns that its foods are deleted too).
- **Item cards** — small **edit** (name in 5 languages, price, section, icon;
  Cancel / Change (گۆڕین)) and **delete** (Confirm / Delete) buttons; in printer
  mode, cards show colour dots of their assigned printers.

#### D. Accounts — `lib/page/admin/admin_accounts_page.dart`

**What it is:** Financial summary for a chosen period: net takings, electronic,
cash+electronic and expenses.

**Role:** admin only.

- **Period chips** — **“مانگانە”** *[Monthly, the default]*,
  **“ڕۆژانە”** *[Daily = today]*, **“دوێنی”** *[Yesterday]*,
  **“پێری”** *[Day before yesterday]* — one day at a time, then
  **“تایبەت”** *[Custom]* opens two date pickers (e.g. the 1st to the 30th).
  The choice is remembered across restarts.
- **Four cards** — **Total money (کۆی گشتی پارەکان)** = cash+electronic −
  expenses, **Electronic (پارەی ئەلیکترۆنی)**, **Cash + electronic
  (کاش + ئەلیکترۆنی)**, **Expenses (خەرجیەکان)** = purchases + shift
  expenses + refunds — all in IQD.

#### E. Order history — `lib/page/admin/admin_orders_page.dart`

**What it is:** Browse settled orders, filter by date, search by table/cashier,
and reprint any bill.

**Role:** admin only.

- **Filter chips — All (هەموو) / Today (ئەمڕۆ) / This week / This month /
  Custom (تایبەت)** — custom opens two date pickers.
- **Search field** — “search by table or cashier name”.
- **Order rows** — tap to open the detail dialog: cashier, time, item lines,
  total, discount; **“چاپکردنەوەی حیساب”** *[Re-print bill]* — receipt preview
  (Cancel / Print); **Close (داخستن)**.

#### F. Cashier shifts — `lib/page/admin/admin_shifts_page.dart`

**What it is:** Lists all cashier shifts and compares **declared** cash vs the
**system** total on closed shifts.

**Role:** admin only.

- **Shift cards** — cashier name, start/end times, **Active (چالاکە)** badge;
  tap to open the shift report.
- **Comparison strip (closed shifts)** — Cashier (declared) ⇄ System (computed)
  with +/− difference and a status icon.

#### G. Shift report — `lib/page/admin/admin_shift_detail_page.dart`

**What it is:** Full financial report for one shift: payments by method, refunds
& expenses, settled orders (expandable), pending cancelled items.

**Role:** admin only.

- **Pull-to-refresh**.
- **Payment-method rows** — Cash (وەسڵ نەقد), Debt (قەرز), FIB, SWITCH,
  SUPERQI, NASS — tap to see that method's orders.
- **Financial summary cards** — Cash+debts, Cashier-declared, equal/more/less
  comparison, and (closed) **Net (خاو)** = system − refunds − expenses.
- **Refunds & expenses cards** with lists.
- **Previous-orders** section with expandable cards.
- **Rejected (cancelled)** list for open shifts with total.

#### H. Expenses — `lib/page/admin/admin_purchases_page.dart`

**What it is:** The money ledger for a period: what came in, what was drawn out
and what was handed back — plus the form to book a purchase.

**Role:** admin only.

- **Period chips** — هەموو *[All]* / ئەمڕۆ *[Today]* / دوێنی *[Yesterday]* /
  پێری *[Day before yesterday]* / تایبەت *[Custom]*; remembered across restarts.
- **Three stat cards** — **لە دەخیلە** *[Money in]* (cash + electronic + debt),
  **ڕاکێشراوە** *[Money out]* (purchases + shift expenses),
  **گەڕاوەتەوە** *[Returned]* (refunds) — in IQD.
- **Add form** — **Item-name field** + **Price (نرخ (د.ع))** + **“زیادکردن”**
  *[Add]* — validates, saves, feeds the ledger.
- **Ledger rows** — purchase (red) or shift expense (primary) tag, date, amount,
  plus a **Total (کۆی گشتی)** footer.

#### I. Rejected (ڕەتکراوەکان) — `lib/page/admin/admin_refunds_page.dart`

**What it is:** View refunded money for cancelled items (ڕەتکراوەکان) over a
period.

**Role:** admin only.

- **Period chips** — هەموو *[All]* (the default) / ئەمڕۆ *[Today]* / دوێنی
  *[Yesterday]* / پێری *[Day before yesterday]* / تایبەت *[Custom]*; remembered
  across restarts.
- **Rejected rows** — item, ×qty, table, who rejected it, date/time, red amount +
  **Total (کۆی گشتی)** footer.

#### J. Debts (admin) — `lib/page/admin/admin_debts_page.dart`

**What it is:** Track table debts over a period; settle them as paid orders or
delete them.

**Role:** admin only.

- **Period chips** — same five presets as above; the choice is remembered across
  restarts, so the admin keeps the same day window for every table.
- **Settle button** (green check) — confirmation (Cancel / Settle (واسڵکردن)) —
  turns the debt into a settled order.
- **Delete button** (red trash) — confirmation (Cancel / Delete).
- **Total (کۆی گشتی)** footer.

#### K. Backup & restore — `lib/page/admin/admin_backup_page.dart`

**What it is:** Create database backups, restore an old backup (wipes current
data), or reset everything to factory state.

**Role:** admin only.

- **“دروستکردنی بەکاپ”** *[Create backup]* — export icon — saves a `.db` backup
  and reloads the list.
- **Backup tiles** — name, modified time, size; tap → **Restore (گەڕاندنەوە)**
  confirmation (Cancel / Restore) — restores the file.
- **“سڕینەوە”** *[Delete]* (red, footer) — **Delete-all-data** confirmation
  (Cancel / Delete) — resets everything to factory state.

#### L. Captain intelligence — `lib/page/admin/admin_captain_intelligence_page.dart`

**What it is:** Read-only waiter performance over the last 30 days: orders and
sales per waiter.

**Role:** admin only. (No buttons — per-waiter cards: name, `Orders | Total IQD`.)

#### M. Food demand — `lib/page/admin/admin_food_demand_page.dart`

**What it is:** How many units of each food sold over a period (cancelled items
subtracted), most-demanded first.

**Role:** admin only.

- **Period chips** — هەموو *[All]* / ئەمڕۆ *[Today, the default]* / دوێنی
  *[Yesterday]* / پێری *[Day before yesterday]* / تایبەت *[Custom]*; remembered
  across restarts.
- **Rows** — food name + “{quantity} دانە” *[pieces]* badge.

#### N. Food filter by printer — `lib/page/admin/admin_food_filter_page.dart`

**What it is:** See which printers each menu item routes to, and reassign per
item in one tap.

**Role:** admin only.

- **Refresh (تازەکردنەوە)** — reloads categories/items/assignments.
- **Category sidebar** — “Sections (بەشەکان)”.
- **Item cards** — tap → **“شوێنی چاپ”** *[Print location]* dialog with
  **Kitchen / Bar / Hookah / Cashier** checkboxes (coloured dots; helper text
  “if not linked to any printer it goes to the kitchen”); Cancel / Save (پاشەکەوت).

#### O. Printer setup — `lib/page/admin/admin_printer_screen.dart`

**What it is:** Discover thermal printers on the network, configure one printer
per role (kitchen/bar/hookah/cashier), and map categories or items to printers.

**Role:** admin only.

- **“گەڕان”** *[Search]* — scans the network; shows “{n} printers found”.
- **Configured-printer list** — each row shows type + port; **delete** button with
  confirmation (Cancel / Remove (لابردن)).
- **Assignment panel** — four sections (Kitchen printer / Bar printer / Hookah
  printer / Cashier printer), each with an **Assign (دەستنیشانکردن)** dropdown of
  discovered printers and a confirm dialog (Cancel / Assign).
- **“نەخشەکێشانی پۆل”** *[Map categories]* — per-category dropdown choosing the
  printer (or “select a printer…” to clear) — Close (داخستن).
- **“نەخشەکێشانی خواردن”** *[Map items]* — per-item dropdown (default “by
  category”) — Close (داخستن).

#### P. Table notes — `lib/page/admin/admin_table_notes_page.dart`

**What it is:** Read the notes the captains leave on tables, newest first, with the
note's last edit time shown on each card.

**Role:** admin only.

- **Period chips** — هەموو *[All, the default]* / ئەمڕۆ *[Today]* / دوێنی
  *[Yesterday]* / پێری *[Day before yesterday]* / تایبەت *[Custom]*; remembered
  across restarts. Notes written before edit times were recorded stay visible
  under هەموو only.

---

## 6. Shared building blocks (widgets)

These small pieces appear inside many screens:

- **Role Users Tab (`role_users_tab.dart`)** — the staff-account widget used by
  both the admin and the owner:
  - **Add-user form**: Name field, **PIN (5 digits)** field, **Add (زیادکردن)**
    button — auto-generates a unique IP `192.168.x.y`; snackbars on success/failure.
  - **Per-user buttons**: **IP (نیشانەی IP)** — see/copy the account IP /
    generate a new one; **Set table range (دیاریکردنی مەودای مێز)** — waiters
    only, from-table/to-table (Cancel / Save); **Assign tables (دیاریکردنی مێز)**
    — waiters only, tap tiles to assign (Cancel / Save); **Change PIN
    (گۆڕینی وشەی نهێنی)** — new 5-digit PIN (Cancel / Change); **Delete** —
    confirmation (Cancel / Delete).
- **Table card (`table_card.dart`)** — the coloured grid tile (empty / seated /
  bill-requested / overdue) showing name, guests, IQD total.
- **Profile icon (`profile_icon.dart`)** — avatar + language menu (and optional
  Settings / Logout).
- **Admin date filter bar (`admin_date_filter_bar.dart`)** — the period chip row
  shared by accounts, expenses, rejected, debts, food demand and table notes:
  هەموو *[All]* / ئەمڕۆ *[Today]* / دوێنی *[Yesterday]* / پێری *[Day before
  yesterday]* / مانگانە *[Monthly]* / ئەم هەفتەیە *[This week]* / تایبەت *[Custom,
  two date pickers]*. Each page picks the subset it needs; the choice can be
  persisted across restarts.
- **Currency converter (`currency_converter.dart`)** — live USD⇄IQD.
- **Print preview dialog (`print_preview_dialog.dart`)** — **Cancel / Print**
  before any printing.
- **Close-shift dialog (`close_shift_dialog.dart`)** — expenses, collected amount,
  net — **Cancel / Close**.
- **Cash calculator dialog (`cash_calculator_dialog.dart`)** — quick-fill chips,
  live change calculation — **Cancel / Settle**.

---

## 7. The database (local storage)

- **Engine:** SQLite (via the `sqflite` package), file **version 46**.
- **22 tables** (the stored data):

| Table | Stores |
|---|---|
| `users` | staff accounts: name, 5-digit PIN, role, IP access code, table range/assignment |
| `tables` | restaurant tables: number/name, status, guests, seated time, totals |
| `order_items` | items on a table's open order, each with its own arrival (`syncedAt`) and print (`printedAt`, `failedPrinters`) stamps |
| `settled_orders` / `settled_order_items` | paid bills (by table/cashier) |
| `cashier_shifts` | cashier shifts: start/end time, declared cash |
| `debts` | table debts |
| `purchases` | supply purchases |
| `refunds` | refunded amounts |
| `cashier_expenses` | shift expenses |
| `cancelled_items` | items cancelled by waiters, waiting to be re-assigned |
| `food_categories` / `food_items` | the menu (names in 5 languages, price, icon) |
| `waiter_tables` | per-waiter assigned tables |
| `table_notifications` | messages a waiter sends to the cashier |
| `printer_configs` | the configured printers |
| `category_printer_mappings` / `item_printer_overrides` / `item_printer_assignments` | which printer gets which category/item |
| `pending_sync` | the offline queue of changes waiting to sync |
| `order_delivery` | delivery status of every sent order |
| `table_locks` | locks that stop two people opening the same table |

---

## 8. The sync engine (how devices stay in step)

- The **server** device runs a WebSocket server on **port 9876** and announces
  itself via **UDP broadcast on port 9877**.
- Client devices **auto-discover** the server, or use the **known server IP**
  saved by the owner.
- Every database change becomes a **SyncMessage** broadcast to all devices; a
  **pending-sync queue** holds changes while offline and flushes them on
  reconnect.
- An **order-conflict resolver** keeps copies in step when the same order is
  edited on different devices.
- A **network guard** watches the Wi-Fi; when the restaurant network is lost the
  app locks the login and (once logged in) can force a clean logout, while the
  server device keeps serving.

---

## 9. Built and tested status

- **`flutter analyze`**: 0 issues (clean).
- **`flutter test`**: **115 tests passing** across 11 files, covering login
  gating, the Connect-IP + multi-IP binding flow, owner login, offline sync,
  order conflicts, database CRUD, responsive layouts, table colours, printer/IP
  settings and real socket sync.

---

## 10. Where to run it

- **Waiter devices:** Android phones (the `run_windows.bat` / `run_windows_dev.bat`
  scripts launch the Windows build on the cashier laptop).
- The first-time setup path for a new device: open the app → **Connect to IP
  (بەستنەوە بە IP)** → add the account IP the owner created for you → Connect →
  log in with your 5-digit PIN.