import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../database/local_db.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/network_guard_service.dart';
import '../../services/sync_provider.dart';

/// IP settings page (ڕێخستنی IP) for the owner (خاوەن سیستەم).
///
/// The owner types the IP of the device that hosts the central sync server
/// and presses Save - the button sits right below the IP box as requested.
/// This address is stored on the device and used by every client (owner,
/// waiter, cashier, admin) so that all machines on the restaurant LAN can
/// recognize each other and connect through one known server IP.
class IpSettingsPage extends ConsumerStatefulWidget {
  const IpSettingsPage({super.key});

  @override
  ConsumerState<IpSettingsPage> createState() => _IpSettingsPageState();
}

class _IpSettingsPageState extends ConsumerState<IpSettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _deviceIp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await getSavedServerIp();
    // Best-effort: show this device's own LAN IP so the owner can compare it
    // with the server address (fails open in tests / when no network).
    String? deviceIp;
    try {
      final verdict = await NetworkGuardService.instance.evaluateNow();
      if (verdict != RestaurantNetworkStatus.offline) {
        deviceIp = NetworkGuardService.instance.lastLocalIp;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _ipController.text = saved ?? '';
      _deviceIp = deviceIp;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  bool _isValidIp4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _save() async {
    final ip = _ipController.text.trim();
    if (!_isValidIp4(ip)) {
      _showSnack(
        context.tr('نیشانەی IP هەڵەیە - دڵنیابە شێوەکەی وەک (مثال: 192.168.1.10) بێت'),
        AppColors.danger,
      );
      return;
    }
    setState(() => _saving = true);
    await saveServerIp(ip);
    // Anchor the network guard to the confirmed restaurant subnet the moment
    // the owner saves it - no need to wait for a server round-trip.
    NetworkGuardService.instance.setExpectedServerIp(ip);
    // Restart this device's client towards the newly saved server IP so the
    // new address is used immediately, with no app restart needed.
    if (!isRunningInTest) {
      final user = ref.read(authProvider);
      if (user != null) {
        final db = ref.read(localDbProvider);
        final accessCode = user.accessCode?.trim();
        startAutoDiscovery(
          db,
          user.id,
          user.role.name,
          ref.read(syncConnectionProvider.notifier),
          knownServerIp: ip,
          knownPort: 9876,
          accessCode: accessCode,
          // The owner page runs a hub alongside this client so a sibling owner
          // device can dial in; re-dialling must not tear that hub down.
          peerLink: true,
        );
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _showSnack(
      context.tr('پاشەکەوت کرا - بەستەرەکە بە ئای-پی نوێیەوە دەبەسترێتەوە'),
      AppColors.success,
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.router_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('نیشانەی IP'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('بۆ ئەوەی هەموو ئامێرەکان یەکتری بناسنەوە و پەیوەندییان پێکەوە هەبێت، ناونیشانی IPـی ئەو ئامێرەی کە سێرڤەرەکەی لەسەرە لێرە دابنێ و پاشەکەوت بکە.'),
            style: TextStyle(color: AppColors.softText, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ipController,
            enabled: !_loading && !_saving,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.tr('ئای-پی سێرڤەر'),
              hintText: '192.168.X.Y',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.lan_rounded, color: AppColors.primary),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          // دوگمەی سەیڤ لە ژێر بۆکسەکە
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_loading || _saving) ? null : _save,
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
          if (_deviceIp != null && _deviceIp!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${context.tr('ئای-پی ئەم ئامێرە')}: $_deviceIp',
                style: const TextStyle(color: AppColors.softText, fontSize: 12),
              ),
            ),
          ],
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.darkText),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          context.tr('ڕێخستنی IP'),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  _buildIpSection(),
                ],
              ),
            ),
    );
  }
}