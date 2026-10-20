import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/colors.dart';
import '../core/digits.dart';
import '../core/fmt.dart';
import '../models/dollar_rate_model.dart';
import '../providers/dollar_rate_provider.dart';
import '../services/app_localizations.dart';
import 'amount_input_formatter.dart';

class CurrencyConverter extends ConsumerStatefulWidget {
  const CurrencyConverter({super.key});

  @override
  ConsumerState<CurrencyConverter> createState() => _CurrencyConverterState();
}

class _CurrencyConverterState extends ConsumerState<CurrencyConverter> {
  final _rateController = TextEditingController();
  final _usdController = TextEditingController();
  final _iqdController = TextEditingController();

  /// Set once the cashier types a rate of their own. From then on the saved
  /// shop rate no longer overwrites the box, so a "what if" entry survives.
  bool _manualRate = false;

  /// The last rate this widget pushed into [_rateController].
  String? _syncedRateLabel;

  @override
  void dispose() {
    _rateController.dispose();
    _usdController.dispose();
    _iqdController.dispose();
    super.dispose();
  }

  /// Reads a typed amount, accepting localized digits and comma grouping.
  ///
  /// `double.tryParse` alone returns 0 for "١٢٣٤" or "۱٬۲۰۰", so a cashier on an
  /// Arabic keyboard silently got an empty conversion box.
  double _parseAmount(String text) {
    final normalized = toLatinDigits(text)
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .trim();
    return double.tryParse(normalized) ?? 0;
  }

  String _formatUsd(double value) => value.toStringAsFixed(2);

  void _onUsdChanged(String value) {
    final rate = _parseAmount(_rateController.text);
    final usd = _parseAmount(value);
    if (rate > 0 && usd > 0) {
      _iqdController.text = money(usd * rate / 100);
    } else {
      _iqdController.text = '';
    }
  }

  void _onIqdChanged(String value) {
    final rate = _parseAmount(_rateController.text);
    final iqd = _parseAmount(value);
    if (rate > 0 && iqd > 0) {
      _usdController.text = _formatUsd(iqd * 100 / rate);
    } else {
      _usdController.text = '';
    }
  }

  /// Recomputes whichever side the cashier filled in.
  void _recompute() {
    if (_usdController.text.trim().isNotEmpty) {
      _onUsdChanged(_usdController.text);
    } else if (_iqdController.text.trim().isNotEmpty) {
      _onIqdChanged(_iqdController.text);
    }
  }

  /// Seeds the "rate for 100$" box from the rate the admin saved.
  ///
  /// The old widget hard-coded 150,000, so after the admin changed the rate the
  /// converter kept converting at the stale figure while the banner beside it
  /// showed the new one.
  void _syncSavedRate(DollarRate rate) {
    if (_manualRate) return;
    final perDollar = rate.iqdPerDollar;
    if (perDollar == null) return;
    final label = money((perDollar * 100).round());
    if (label == _syncedRateLabel) return;
    _syncedRateLabel = label;
    // Controllers cannot be written during build; do it once the frame lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _manualRate) return;
      _rateController.text = label;
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Follow the admin's saved rate, so the converter and the rate banner next
    // to it can never disagree.
    _syncSavedRate(ref.watch(dollarRateProvider).valueOrNull ?? DollarRate.fallback);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(child: Icon(Icons.currency_exchange_rounded, color: AppColors.primary, size: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(context.tr('گۆڕینەوەی نرخ'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(context.tr('نرخی 100\$:'), style: const TextStyle(fontSize: 14, color: AppColors.darkText)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rateController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [AmountInputFormatter()],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  onChanged: (_) {
                    // The cashier overrode the shop rate; keep their figure.
                    _manualRate = true;
                    _recompute();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(context.tr('د.ع'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('USD \$'),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  onChanged: _onUsdChanged,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                // `arrow_forward_rounded` carries `matchTextDirection: true`, so
                // it already points from the USD field to the IQD field in both
                // RTL and LTR.
                child: const Center(child: Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _iqdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('IQD د.ع'),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  onChanged: _onIqdChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
