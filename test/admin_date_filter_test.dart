import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/widgets/admin_date_filter_bar.dart';

/// Guards the day-by-day reading the admin pages share: ئەمڕۆ (today) →
/// دوێنی (yesterday) → پێری (the day before yesterday). «پێری» used to be
/// wired to a whole-week range, which silently answered a different question
/// than its label asked.
void main() {
  DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  group('day presets step back one day at a time', () {
    test('today covers only today', () {
      final now = DateTime.now();
      final r = resolveAdminDatePeriod(AdminDatePeriod.today);
      expect(r.from, dayStart(now));
      expect(r.to, dayEnd(now));
      expect(r.isAll, isFalse);
      final yesterday = now.subtract(const Duration(days: 1));
      expect(r.contains(yesterday), isFalse, reason: 'yesterday is its own chip');
    });

    test('yesterday covers only yesterday', () {
      final now = DateTime.now();
      final y = now.subtract(const Duration(days: 1));
      final r = resolveAdminDatePeriod(AdminDatePeriod.yesterday);
      expect(r.from, dayStart(y));
      expect(r.to, dayEnd(y));
      expect(r.contains(now), isFalse);
    });

    test('پێری (dayBeforeYesterday) is two days back - not the whole week', () {
      final now = DateTime.now();
      final p = now.subtract(const Duration(days: 2));
      final r = resolveAdminDatePeriod(AdminDatePeriod.dayBeforeYesterday);
      expect(r.from, dayStart(p));
      expect(r.to, dayEnd(p));
      // The defect this test exists for: yesterday and today must NOT fall in.
      expect(r.contains(now.subtract(const Duration(days: 1))), isFalse);
      expect(r.contains(now), isFalse);
      expect(r.contains(now.subtract(const Duration(days: 3))), isFalse);
    });

    test('week still resolves to Monday through today', () {
      final now = DateTime.now();
      final monday = dayStart(now.subtract(Duration(days: now.weekday - 1)));
      final r = resolveAdminDatePeriod(AdminDatePeriod.week);
      expect(r.from, monday);
      expect(r.to, dayEnd(now));
    });
  });

  group('month and all', () {
    test('month spans the first to the last day of the current month', () {
      final now = DateTime.now();
      final r = resolveAdminDatePeriod(AdminDatePeriod.month);
      expect(r.from, DateTime(now.year, now.month, 1));
      // Day 0 of next month is the last day of this one; 00:00 → 23:59:59.
      expect(r.to, DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    });

    test('all is flagged and reaches both extremes', () {
      final r = resolveAdminDatePeriod(AdminDatePeriod.all);
      expect(r.isAll, isTrue);
      expect(r.contains(DateTime(2001)), isTrue);
      expect(r.contains(DateTime.now()), isTrue);
    });
  });

  group('custom', () {
    test('uses the picked bounds and normalises the day ends', () {
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 30);
      final r = resolveAdminDatePeriod(
        AdminDatePeriod.custom,
        customFrom: from,
        customTo: to,
      );
      expect(r.from, DateTime(2026, 10, 1));
      expect(r.to, DateTime(2026, 10, 30, 23, 59, 59));
      expect(r.contains(DateTime(2026, 10, 15, 12)), isTrue);
      expect(r.contains(DateTime(2026, 9, 30, 23, 59)), isFalse);
    });

    test('swapped bounds are corrected rather than yielding an empty range', () {
      final r = resolveAdminDatePeriod(
        AdminDatePeriod.custom,
        customFrom: DateTime(2026, 10, 20),
        customTo: DateTime(2026, 10, 5),
      );
      expect(r.from, DateTime(2026, 10, 5));
      expect(r.to, DateTime(2026, 10, 20, 23, 59, 59));
    });
  });
}
