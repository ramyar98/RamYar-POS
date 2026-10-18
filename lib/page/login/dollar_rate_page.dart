import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/digits.dart';
import '../../models/dollar_rate_model.dart';
import '../../providers/dollar_rate_provider.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';

/// The admin's dollar-rate editor, reached from the "$" button on the login
/// screen.
///
/// The admin types the two numbers exactly as they see them quoted - "100$" and
/// "150,000 د.ع" - and presses Save. Nothing is converted and nothing is
/// recomputed behind their back: the figure the shop quotes is the figure the
/// cashiers are shown, so a rate the admin recognises is a rate they can trust.
/// Accepting a comma-grouped "150,000" is the whole point of the field, since
/// that is how the number gets read off a screen and typed back in.
///
/// Reachable only from the admin/owner login screen, but the role is checked
/// again here before saving. The button being hidden is a convenience; this is
/// the check that actually matters, because a route can be pushed from anywhere
/// inside the app.
class DollarRatePage extends ConsumerStatefulWidget {
  const DollarRatePage({super.key});

  @override
  ConsumerState<DollarRatePage> createState() => _DollarRatePageState();
}

class _DollarRatePageState extends ConsumerState<DollarRatePage> {
  final _dollarsController = TextEditingController();
  final _iqdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loaded = false;
  bool _saving = false;
  bool _justSaved = false;

  /// True while the page is rewriting its own fields (after a save, or when
  /// pre-filling). Those writes are the page tidying up after itself, not the
  /// admin changing their mind, so they must not be mistaken for an edit.
  bool _writingBack = false;

  @override
  void initState() {
    super.initState();
    // The live preview reads the two controllers directly, so the widget has to
    // be told when they change. Editing the text also means the admin is no
    // longer looking at what they last saved, so the "saved" note is dropped.
    _dollarsController.addListener(_onTyped);
    _iqdController.addListener(_onTyped);
  }

  void _onTyped() {
    if (_writingBack) return;
    if (!mounted) return;
    setState(() => _justSaved = false);
  }

  @override
  void dispose() {
    _dollarsController.removeListener(_onTyped);
    _iqdController.removeListener(_onTyped);
    _dollarsController.dispose();
    _iqdController.dispose();
    super.dispose();
  }

  /// Fills the two fields once, from whatever is stored. Guarded by [_loaded] so
  /// a live update arriving from another device does not overwrite a number the
  /// admin is halfway through typing.
  void _prefill(DollarRate rate) {
    if (_loaded) return;
    _loaded = true;
    _writeBack(rate.dollarsLabel, rate.iqdLabel);
  }

  /// Replaces the two fields with [dollars] / [iqd] without it reading as an
  /// edit. Wrapped in [_writingBack] because the listeners fire synchronously.
  void _writeBack(String dollars, String iqd) {
    _writingBack = true;
    _dollarsController.text = dollars;
    _iqdController.text = iqd;
    _writingBack = false;
  }

  /// Accepts what a person actually types: Latin or Arabic-Indic digits, commas
  /// or spaces as thousands separators, and a stray decimal point. Returns null
  /// for anything that is not a positive number, so the form can say so rather
  /// than saving a zero.
  double? _parse(String raw) {
    final cleaned = raw
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('٬', '')
        .trim();
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(toLatinDigits(cleaned));
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final dollars = _parse(_dollarsController.text);
    final iqd = _parse(_iqdController.text);
    if (dollars == null || iqd == null) return;

    setState(() => _saving = true);
    await ref.read(localDbProvider).setDollarRate(
          DollarRate(dollars: dollars, iqd: iqd),
        );
    if (!mounted) return;
    // Re-read and re-show the stored, formatted numbers, so what stays on
    // screen after saving is exactly what the cashiers will see - "150000",
    // "150 000" and "150,000" all come back as the one way the app writes it.
    final stored = await ref.read(localDbProvider).getDollarRate();
    if (!mounted) return;
    _writeBack(stored.dollarsLabel, stored.iqdLabel);
    setState(() {
      _saving = false;
      _justSaved = true;
    });
    ref.invalidate(dollarRateProvider);
  }

  String? _validateDollars(String? value) {
    if (_parse(value ?? '') == null) {
      return context.tr('ژمارەیەکی دروست بنووسە (بۆ نموونە 100)');
    }
    return null;
  }

  String? _validateIqd(String? value) {
    if (_parse(value ?? '') == null) {
      return context.tr('ژمارەیەکی دروست بنووسە (بۆ نموونە 150,000)');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rateAsync = ref.watch(dollarRateProvider);
    // Pre-fill from the stored rate as soon as it is known, and keep following
    // the live value so a rate the admin just changed on another device shows
    // up here without a reload.
    rateAsync.whenData(_prefill);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('نرخی دۆلار')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildIntro(),
                    const SizedBox(height: 18),
                    _buildField(
                      controller: _dollarsController,
                      label: context.tr('چەند دۆلار'),
                      suffix: '\$',
                      validator: _validateDollars,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _iqdController,
                      label: context.tr('چەند دیناری عیراقی'),
                      suffix: context.tr('د.ع'),
                      validator: _validateIqd,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                    _buildPreview(),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(context.tr('پاشەکەوتکردن')),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_justSaved) ...[
                      const SizedBox(height: 14),
                      _buildSavedNote(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                  'نرخەکە بنووسە بەو شێوەیە کە دەتەوێت پیشان بدرێت - هەموو کاشێرەکان ئەم ژمارەیە دەبینن'),
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.darkText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required String? Function(String?) validator,
    required TextInputType keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      // A rate the admin quotes is a whole-dollar and whole-dinar figure; the
      // field still accepts a decimal so a market rate with cents can be typed,
      // but the numbers are stored and shown as whole dinars.
      textInputAction: TextInputAction.next,
      textDirection: TextDirection.ltr,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Shows the sentence the cashiers will read, live, as the admin types. If it
  /// does not look right here, it will not look right on their screen either.
  Widget _buildPreview() {
    // The controllers are plain text fields, so typing does not rebuild this
    // widget on its own - the listeners below do it, and nothing else needs to.
    final dollars = _parse(_dollarsController.text);
    final iqd = _parse(_iqdController.text);
    final ready = dollars != null && iqd != null;
    final preview = ready
        ? context.trp('{dollars}\$ بەرامبەر بە دیناری عیراقی {iqd}', {
            'dollars': DollarRate(dollars: dollars, iqd: iqd).dollarsLabel,
            'iqd': DollarRate(dollars: dollars, iqd: iqd).iqdLabel,
          })
        : context.tr('ژمارەکان بنووسە تا پێشبینی دەربکەوێت');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('ئەوەی دەبینرێت'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.softText),
          ),
          const SizedBox(height: 4),
          Text(
            preview,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: ready ? AppColors.success : AppColors.softText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
        const SizedBox(width: 6),
        Text(
          context.tr('پاشەکەوتکرا'),
          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
