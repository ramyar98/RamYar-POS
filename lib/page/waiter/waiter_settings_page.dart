import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/digits.dart';
import '../../core/language.dart';
import '../../core/app.dart';
import '../../widgets/language_flag.dart';
import '../../services/app_localizations.dart';
import '../../services/sync_provider.dart';

class WaiterSettingsPage extends ConsumerStatefulWidget {
  const WaiterSettingsPage({super.key});

  @override
  ConsumerState<WaiterSettingsPage> createState() => _WaiterSettingsPageState();
}

class _WaiterSettingsPageState extends ConsumerState<WaiterSettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await getDeviceAccessCode();
    if (!mounted) return;
    setState(() {
      _ipController.text = code ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _saveIp() async {
    final code = _ipController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('کۆدی تایبەت بنووسە یان لە ئادمێن داوا بکە')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    await applyAccessCode(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('پاشەکەوت کرا - بەستەرەکە نوێ کرایەوە')),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Widget _buildLanguageSection() {
    final appState = AppState.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.language_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(context.tr('زمان'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkText)),
            ],
          ),
          const SizedBox(height: 8),
          for (final lang in AppLanguage.values)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (appState.currentLanguage != lang) {
                  appState.onLanguageChanged(lang);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    FlagIcon(language: lang, width: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        LanguageHelper.getLanguageName(lang),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: appState.currentLanguage == lang ? FontWeight.bold : FontWeight.w500,
                          color: appState.currentLanguage == lang ? AppColors.primary : AppColors.darkText,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: appState.currentLanguage == lang ? AppColors.primary : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIpSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.router_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tr('کۆدی تایبەت'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkText)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ipController,
            enabled: !_loading,
            // The access code is an IP (`192.168.X.Y`). A URL keyboard shows
            // digits AND the dot on mobile (the numeric keypad has no "."), and
            // stays fully usable with the laptop's physical keyboard. Arabic/
            // Persian layouts are normalized to Latin digits on the fly.
            keyboardType: TextInputType.url,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp('[0-9\\u0660-\\u0669\\u06F0-\\u06F9.]'),
              ),
            ],
            onChanged: (value) {
              final latin = toLatinDigits(value);
              if (latin != value) {
                _ipController.value = TextEditingValue(
                  text: latin,
                  selection: TextSelection.collapsed(offset: latin.length),
                );
              }
            },
            decoration: InputDecoration(
              labelText: context.tr('کۆدی تایبەت'),
              hintText: '192.168.X.Y',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.lan_rounded, color: AppColors.primary),
            ),
            onSubmitted: (_) => _saveIp(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _saveIp,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(context.tr('پاشەکەوتکردن')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.tr('ڕێخستن'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  _buildLanguageSection(),
                  _buildIpSection(),
                ],
              ),
            ),
    );
  }
}