import 'package:flutter/material.dart';

import '../core/app_prefs.dart';
import '../core/colors.dart';
import '../services/app_localizations.dart';

/// The period presets shared by the admin pages that filter rows by date.
enum AdminDatePeriod { all, today, yesterday, week, month, custom }

/// The resolved, inclusive bounds a period stands for.
class AdminDatePeriodRange {
  const AdminDatePeriodRange({required this.from, required this.to, this.isAll = false});

  /// First covered day at 00:00:00.
  final DateTime from;

  /// Last covered day at 23:59:59.
  final DateTime to;

  /// True when the period is "every day" - used by pages that also keep
  /// rows whose date is unknown (e.g. table notes written before the
  /// note's edit time was recorded).
  final bool isAll;

  String get fromIso => '${_ymd(from)}T00:00:00';
  String get toIso => '${_ymd(to)}T23:59:59';

  bool contains(DateTime dt) => !dt.isBefore(from) && !dt.isAfter(to);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Turns [period] into concrete bounds. `customFrom`/`customTo` only matter
/// for [AdminDatePeriod.custom]; they fall back to the previous seven days.
AdminDatePeriodRange resolveAdminDatePeriod(
  AdminDatePeriod period, {
  DateTime? customFrom,
  DateTime? customTo,
}) {
  final now = DateTime.now();
  DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  switch (period) {
    case AdminDatePeriod.all:
      return AdminDatePeriodRange(
        from: DateTime(2000, 1, 1),
        to: DateTime(2100, 12, 31, 23, 59, 59),
        isAll: true,
      );
    case AdminDatePeriod.today:
      final today = DateTime(now.year, now.month, now.day);
      return AdminDatePeriodRange(from: today, to: endOfDay(today));
    case AdminDatePeriod.yesterday:
      final y = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      return AdminDatePeriodRange(from: y, to: endOfDay(y));
    case AdminDatePeriod.week:
      // The week runs Monday through today, mirroring the history page.
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return AdminDatePeriodRange(from: monday, to: endOfDay(now));
    case AdminDatePeriod.month:
      final first = DateTime(now.year, now.month, 1);
      // Day 0 of the next month is the last day of this one.
      final last = DateTime(now.year, now.month + 1, 0);
      return AdminDatePeriodRange(from: first, to: endOfDay(last));
    case AdminDatePeriod.custom:
      final from = DateTime(
        (customFrom ?? now.subtract(const Duration(days: 7))).year,
        (customFrom ?? now.subtract(const Duration(days: 7))).month,
        (customFrom ?? now.subtract(const Duration(days: 7))).day,
      );
      final rawTo = customTo ?? now;
      final to = DateTime(rawTo.year, rawTo.month, rawTo.day);
      if (from.isAfter(to)) {
        return AdminDatePeriodRange(from: to, to: endOfDay(from));
      }
      return AdminDatePeriodRange(from: from, to: endOfDay(to));
  }
}

/// The chip row (plus the custom range summary) shared by the admin pages
/// that filter by period.
///
/// The bar owns the selected period - including the sticky copy persisted
/// under `prefKey` - and reports every change through [onChanged]. The first
/// notification is sent after the first frame, so a page is free to call
/// `setState` from its handler.
class AdminDateFilterBar extends StatefulWidget {
  const AdminDateFilterBar({
    super.key,
    required this.options,
    this.initial = AdminDatePeriod.all,
    this.labels = const {},
    this.onChanged,
    this.prefKey,
    this.persist = false,
  });

  /// Periods offered as chips, in display order.
  final List<AdminDatePeriod> options;

  /// Period selected when nothing was persisted yet.
  final AdminDatePeriod initial;

  /// Per-period label overrides (e.g. `today` reads ڕۆژانە on the accounts
  /// page instead of ئەمڕۆ).
  final Map<AdminDatePeriod, String> labels;

  final void Function(AdminDatePeriod period, AdminDatePeriodRange range)?
      onChanged;

  /// Pref key used when [persist] is true. The selection (and the custom
  /// range) survives an app restart.
  final String? prefKey;
  final bool persist;

  @override
  State<AdminDateFilterBar> createState() => _AdminDateFilterBarState();
}

class _AdminDateFilterBarState extends State<AdminDateFilterBar> {
  late AdminDatePeriod _period;
  late AdminDatePeriodRange _range;
  late DateTime _customFrom;
  late DateTime _customTo;

  @override
  void initState() {
    super.initState();
    _period = widget.initial;
    _customFrom = DateTime.now().subtract(const Duration(days: 7));
    _customTo = DateTime.now();
    _range = resolveAdminDatePeriod(
      _period,
      customFrom: _customFrom,
      customTo: _customTo,
    );
    if (widget.persist && widget.prefKey != null) {
      _restore();
    }
    // The first notification waits for the frame: pages setState from the
    // handler, and setState during the build that mounts this bar throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notify();
    });
  }

  Future<void> _restore() async {
    final raw = await AppPrefs.instance.getString(widget.prefKey!);
    if (raw == null || !mounted) return;
    final parts = raw.split('|');
    final restored = AdminDatePeriod.values.cast<AdminDatePeriod?>().firstWhere(
          (p) => p!.name == parts[0],
          orElse: () => null,
        );
    if (restored == null || !widget.options.contains(restored)) return;
    setState(() {
      _period = restored;
      if (restored == AdminDatePeriod.custom && parts.length >= 3) {
        final from = DateTime.tryParse(parts[1]);
        final to = DateTime.tryParse(parts[2]);
        if (from != null) _customFrom = from;
        if (to != null) _customTo = to;
      }
      _range = resolveAdminDatePeriod(
        _period,
        customFrom: _customFrom,
        customTo: _customTo,
      );
    });
    _notify();
  }

  Future<void> _save() async {
    if (!widget.persist || widget.prefKey == null) return;
    final value = _period == AdminDatePeriod.custom
        ? '${_period.name}|${_customFrom.toIso8601String()}|${_customTo.toIso8601String()}'
        : _period.name;
    await AppPrefs.instance.setString(widget.prefKey!, value);
  }

  void _notify() => widget.onChanged?.call(_period, _range);

  void _select(AdminDatePeriod period) {
    setState(() {
      _period = period;
      _range = resolveAdminDatePeriod(
        _period,
        customFrom: _customFrom,
        customTo: _customTo,
      );
    });
    _save();
    _notify();
  }

  String _labelFor(BuildContext context, AdminDatePeriod p) {
    if (widget.labels.containsKey(p)) return widget.labels[p]!;
    switch (p) {
      case AdminDatePeriod.all:
        return context.tr('هەموو');
      case AdminDatePeriod.today:
        return context.tr('ئەمڕۆ');
      case AdminDatePeriod.yesterday:
        return context.tr('دوێنی');
      case AdminDatePeriod.week:
        return context.tr('پێری');
      case AdminDatePeriod.month:
        return context.tr('مانگانە');
      case AdminDatePeriod.custom:
        return context.tr('تایبەت');
    }
  }

  Future<void> _pickCustom() async {
    final fromPicker = await showDatePicker(
      context: context,
      initialDate: _customFrom.isAfter(DateTime.now())
          ? DateTime.now()
          : _customFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (fromPicker == null || !mounted) return;
    final toPicker = await showDatePicker(
      context: context,
      initialDate: _customTo.isBefore(fromPicker)
          ? fromPicker
          : (_customTo.isAfter(DateTime(2030)) ? DateTime(2030) : _customTo),
      firstDate: fromPicker,
      lastDate: DateTime(2030),
    );
    if (toPicker == null || !mounted) return;
    setState(() {
      _customFrom = fromPicker;
      _customTo = toPicker;
      _period = AdminDatePeriod.custom;
      _range = resolveAdminDatePeriod(
        AdminDatePeriod.custom,
        customFrom: _customFrom,
        customTo: _customTo,
      );
    });
    _save();
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in widget.options) ...[
                if (p != widget.options.first) const SizedBox(width: 6),
                FilterChip(
                  label: Text(
                    _labelFor(context, p),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _period == p ? Colors.white : AppColors.darkText,
                    ),
                  ),
                  selected: _period == p,
                  onSelected: (_) {
                    if (p == AdminDatePeriod.custom) {
                      _pickCustom();
                    } else {
                      _select(p);
                    }
                  },
                  selectedColor: AppColors.primary,
                  checkmarkColor: Colors.white,
                  backgroundColor: AppColors.background,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  side: BorderSide.none,
                ),
              ],
            ],
          ),
        ),
        if (_period == AdminDatePeriod.custom)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickCustom,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.date_range_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_ymd(_customFrom)} - ${_ymd(_customTo)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
