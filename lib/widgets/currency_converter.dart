import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../services/app_localizations.dart';
import 'amount_input_formatter.dart';

class CurrencyConverter extends StatefulWidget {
  const CurrencyConverter({super.key});

  @override
  State<CurrencyConverter> createState() => _CurrencyConverterState();
}

class _CurrencyConverterState extends State<CurrencyConverter> {
  final _rateController = TextEditingController(text: '150,000');
  final _usdController = TextEditingController();
  final _iqdController = TextEditingController();

  @override
  void dispose() {
    _rateController.dispose();
    _usdController.dispose();
    _iqdController.dispose();
    super.dispose();
  }

  double _parseAmount(String text) => double.tryParse(text.replaceAll(',', '')) ?? 0;

  String _formatIqd(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }

  String _formatUsd(double value) => value.toStringAsFixed(2);

  void _onUsdChanged(String value) {
    final rate = _parseAmount(_rateController.text);
    final usd = _parseAmount(value);
    if (rate > 0 && usd > 0) {
      _iqdController.text = _formatIqd(usd * rate / 100);
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

  @override
  Widget build(BuildContext context) {
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
