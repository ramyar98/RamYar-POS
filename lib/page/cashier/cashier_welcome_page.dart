import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/language.dart';
import '../../core/app.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/user_model.dart';
import '../../models/settlement_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../widgets/language_flag.dart';
import 'cashier_home_page.dart';
import '../../widgets/close_shift_dialog.dart';
import '../login/login_page.dart';

class CashierWelcomePage extends ConsumerStatefulWidget {
  const CashierWelcomePage({super.key});

  @override
  ConsumerState<CashierWelcomePage> createState() => _CashierWelcomePageState();
}

class _CashierWelcomePageState extends ConsumerState<CashierWelcomePage> {
  CashierShift? _activeShift;
  String _timeString = '';
  String _dateString = '';
  Timer? _timer;

  /// True while a start/end-shift write is in flight.
  ///
  /// The buttons stay tappable during the `await`, so without this a fast
  /// double-tap would insert two `cashier_shifts` rows (or open two
  /// close-shift dialogs) for a single press.
  bool _shiftBusy = false;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    Future.microtask(_loadShift);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// «08:34» for a stored ISO timestamp.
  ///
  /// Parsed rather than sliced: `substring(11, 19)` throws a RangeError on any
  /// stored value shorter than 19 chars.
  String _hhmm(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      _dateString = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    });
  }

  /// Grows the layout on tablets / desktop / Windows and gently shrinks it on
  /// very narrow phones so nothing overlaps or overflows at any screen size.
  double _widthScale(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= Responsive.desktopBreakpoint) return 1.25;
    if (w >= 600) return 1.15;
    if (w >= 360) return 1.0;
    return (w / 360).clamp(0.9, 1.0);
  }

  Future<void> _loadShift() async {
    final user = ref.read(authProvider);
    if (user != null && user.role == UserRole.cashier) {
      _activeShift = await ref.read(localDbProvider).getActiveShift(user.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _startShift() async {
    if (_shiftBusy) return;
    final user = ref.read(authProvider);
    if (user == null) return;
    setState(() => _shiftBusy = true);
    final db = ref.read(localDbProvider);
    try {
      await db.startShift(CashierShift(
        cashierId: user.id,
        cashierName: user.name,
        startedAt: DateTime.now().toIso8601String(),
      ));
      if (!mounted) return;
      await ref.read(waiterProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CashierHomePage()),
      );
    } finally {
      if (mounted) setState(() => _shiftBusy = false);
    }
  }

  Future<void> _endShift() async {
    if (_shiftBusy || _activeShift == null) return;
    final db = ref.read(localDbProvider);
    final shiftExpenses = await db.getShiftExpensesTotal(_activeShift!.id);
    if (!mounted) return;
    setState(() => _shiftBusy = true);
    try {
      final result = await showDialog<CloseShiftResult>(
        context: context,
        builder: (_) => CloseShiftDialog(
          startedAt: _activeShift!.startedAt,
          shiftExpenses: shiftExpenses,
        ),
      );
      if (result != null && mounted) {
        await db.endShift(_activeShift!.id, DateTime.now().toIso8601String(), result.collected);
        await _loadShift();
      }
    } finally {
      if (mounted) setState(() => _shiftBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isActive = _activeShift != null;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E252B),
              Color(0xFF2C3539),
              Color(0xFF3D1F0C),
              AppColors.primary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 440 * _widthScale(context)),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final ws = _widthScale(context);
                    final useCompact = h < 700;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    _buildLanguageSelector(),
                    SizedBox(height: useCompact ? 12 : 20),
                    Container(
                      padding: EdgeInsets.all(useCompact ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.receipt_long_rounded, size: useCompact ? 40 : 48, color: Colors.white),
                    ),
                    SizedBox(height: useCompact ? 8 : 12),
                    Text('RAMYAR POS',
                        style: TextStyle(fontSize: (useCompact ? 28 : 32) * ws, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
                    SizedBox(height: useCompact ? 2 : 4),
                    Text(context.tr('کاشێر'),
                        style: TextStyle(fontSize: (useCompact ? 13 : 14) * ws, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 4 * ws)),
                    SizedBox(height: useCompact ? 12 : 16),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_timeString,
                          style: TextStyle(fontSize: (useCompact ? 36 : 42) * ws, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 4 * ws)),
                    ),
                    const SizedBox(height: 2),
                    Text(_dateString,
                        style: TextStyle(fontSize: (useCompact ? 14 : 16) * ws, color: Colors.white.withValues(alpha: 0.6))),
                    SizedBox(height: useCompact ? 12 : 16),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 300 * ws.clamp(1.0, 1.15)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isActive ? AppColors.success.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isActive ? Icons.person_rounded : Icons.person_outline_rounded,
                                  color: isActive ? AppColors.success : Colors.white,
                                  size: 22 * ws.clamp(1.0, 1.15),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('بەخێربێیت'),
                                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                                    Text(user?.name ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 18 * ws.clamp(1.0, 1.15), fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: useCompact ? 12 : 20),
                    if (isActive) ...[
                      _buildShiftActiveCard(),
                    ] else ...[
                    _buildGradientButton(
                      height: 48,
                      icon: Icons.play_arrow_rounded,
                      label: context.tr('دەستپێکردنی شەفت'),
                      onPressed: _startShift,
                      enabled: !_shiftBusy,
                    ),
                    ],
                    const SizedBox(height: 10),
                    _buildOutlinedButton(
                      icon: Icons.logout_rounded,
                      label: context.tr('چوونە دەرەوە'),
                      onPressed: () async {
                        await ref.read(authProvider.notifier).logout();
                        if (!context.mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false,
                        );
                      },
                    ),
                  ],
                );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftActiveCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timeline_rounded, color: AppColors.success, size: 24),
          ),
          const SizedBox(height: 10),
          Text(context.tr('شەفت چالاکە'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(context.trp('دەستی پێکردووە لە {time}',
              {'time': _hhmm(_activeShift!.startedAt)}),
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildGradientButton(
                  height: 44,
                  icon: Icons.play_arrow_rounded,
                  label: context.tr('بەردەوامبوون'),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const CashierHomePage()),
                    );
                  },
                  enabled: !_shiftBusy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _shiftBusy ? null : _endShift,
                    icon: const Icon(Icons.stop_rounded, color: AppColors.danger, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.tr('داخستنی شەفت'),
                          maxLines: 1,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradientButton({required IconData icon, required String label, required VoidCallback onPressed, double? height, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFFFF7A3F)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: height != null ? 0 : 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildOutlinedButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 18),
        label: Text(label,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final appState = AppState.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: appState.currentLanguage,
          icon: const Icon(Icons.language_rounded, color: Colors.white70, size: 20),
          dropdownColor: const Color(0xFF2C3539),
          borderRadius: BorderRadius.circular(14),
          onChanged: (AppLanguage? newLang) {
            if (newLang != null) appState.onLanguageChanged(newLang);
          },
          items: AppLanguage.values.map((AppLanguage lang) {
            return DropdownMenuItem<AppLanguage>(
              value: lang,
              child: LanguageLabel(
                language: lang,
                flagWidth: 20,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
