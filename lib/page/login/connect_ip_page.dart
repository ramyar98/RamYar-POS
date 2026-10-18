import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/digits.dart';
import '../../database/local_db.dart';
import '../../services/app_localizations.dart';
import '../../services/network_guard_service.dart';
import '../../services/sync_provider.dart';
import 'hama_page.dart';

/// Pre-login "Connect with IP" page (بەستنەوە بە IP).
///
/// The owner assigns every staff account a unique IP. One device can bind to
/// MANY of those IPs at once - e.g. to use Admin AND Captain on the same
/// tablet, or to let a trusted phone log in to every account the admin
/// created. Every box below holds one IP address; the small "+" button (icon
/// only, no text) under the boxes adds another box, up to 50. Remove a box
/// with its "x" button, then press "کۆنێکت" (Connect) to bind this device to
/// all of them and sync the user registry from the central server. Once done,
/// each listed member can log in with their own 5-digit PIN on this device.
/// Until at least one IP is entered, only the owner (خاوەن سیستەم) can log in.
class ConnectIpPage extends ConsumerStatefulWidget {
  const ConnectIpPage({super.key});

  @override
  ConsumerState<ConnectIpPage> createState() => _ConnectIpPageState();
}

class _ConnectIpPageState extends ConsumerState<ConnectIpPage> {
  static const int _maxIps = 50;

  // Starts with one empty box so the first frame always shows a field; saved
  // IPs are loaded into their own boxes shortly after.
  final List<TextEditingController> _ipControllers = [TextEditingController()];
  final ScrollController _scrollController = ScrollController();
  bool _connecting = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _offline = !NetworkGuardService.instance.isSecure;
    NetworkGuardService.instance.status.addListener(_onNetworkChanged);
    _load();
  }

  void _onNetworkChanged() {
    final offline = !NetworkGuardService.instance.isSecure;
    if (offline != _offline && mounted) {
      setState(() => _offline = offline);
    }
  }

  Future<void> _load() async {
    final saved = await getDeviceAccessCodes();
    if (!mounted) return;
    setState(() {
      _ipControllers
        ..clear()
        ..addAll(saved.map((ip) => TextEditingController(text: ip)));
      if (_ipControllers.isEmpty) _ipControllers.add(TextEditingController());
    });
  }

  @override
  void dispose() {
    NetworkGuardService.instance.status.removeListener(_onNetworkChanged);
    for (final c in _ipControllers) {
      c.dispose();
    }
    _scrollController.dispose();
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

  void _openHiddenHamaPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HamaPage()));
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Adds one more empty IP box below the current ones (max [_maxIps]).
  void _addBox() {
    if (_ipControllers.length >= _maxIps) {
      _showSnack(
        context.trp('گەیشتە {count} IP - بۆ زیادکردنی زیاتر یەکێک سڕەوە', {
          'count': '$_maxIps',
        }),
        AppColors.danger,
      );
      return;
    }
    setState(() => _ipControllers.add(TextEditingController()));
    // Bring the freshly added box into view. A jump (not an animated scroll)
    // keeps rapid taps responsive - a 250ms animation would swallow the taps
    // that follow right after an add.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _removeBox(int index) {
    setState(() {
      final removed = _ipControllers.removeAt(index);
      removed.dispose();
      // Always keep at least one box visible.
      if (_ipControllers.isEmpty) _ipControllers.add(TextEditingController());
    });
  }

  bool get _hasAnyIp => _ipControllers.any((c) => c.text.trim().isNotEmpty);

  /// Validates every filled box and returns the deduplicated list, or null
  /// (after showing the relevant error) when any box holds an invalid IP.
  List<String>? _collectValidIps() {
    final result = <String>[];
    for (final c in _ipControllers) {
      final ip = c.text.trim();
      if (ip.isEmpty) continue;
      if (!_isValidIp4(ip)) {
        _showSnack(
          context.tr(
            'نیشانەی IP هەڵەیە - دڵنیابە شێوەکەی وەک (مثال: 192.168.1.10) بێت',
          ),
          AppColors.danger,
        );
        return null;
      }
      if (!result.contains(ip)) result.add(ip);
    }
    return result;
  }

  Future<void> _connect() async {
    if (_offline) {
      _showSnack(
        context.tr('وایفای پەیوەست نییە - ناتوانیت ببەسترێیتەوە'),
        AppColors.danger,
      );
      return;
    }
    if (!_hasAnyIp) return;
    final ips = _collectValidIps();
    if (ips == null) return;
    if (ips.isEmpty) return;
    setState(() => _connecting = true);
    final db = ref.read(localDbProvider);
    final state = ref.read(syncConnectionProvider.notifier);
    final ok = await connectWithAccountIp(db, state, ips);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (ok) {
      _showSnack(
        context.tr('بەسترایتەوە - ئێستا بە PINـی خۆت چوونە ژوورەوە بکە'),
        AppColors.success,
      );
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).maybePop();
    } else {
      _showSnack(
        context.tr(
          'پەیوەندی سەرکەوتوو نەبوو - دڵنیابە IPـەکانت ڕاستن و ئامێری سێرڤەرەکە لەسەر هەمان وای-فایە',
        ),
        AppColors.danger,
      );
    }
  }

  Widget _buildIpField(TextEditingController controller) {
    return TextField(
      controller: controller,
      enabled: !_connecting && !_offline,
      // A URL keyboard is used (not `number`): the numeric keypad on most
      // phones has no "." key, which made a 4-part IP impossible to type on
      // mobile. The URL layout shows digits AND the dot, so the whole address
      // can be typed on both a phone's soft keyboard and a laptop's physical
      // one. The formatter below still keeps everything limited to digits/dots.
      keyboardType: TextInputType.url,
      inputFormatters: [
        // Allow ASCII plus Arabic-Indic/Persian digits; any localized form
        // typed from an Arabic/Persian keyboard is converted to Latin below.
        FilteringTextInputFormatter.allow(
          RegExp('[0-9\\u0660-\\u0669\\u06F0-\\u06F9.]'),
        ),
      ],
      // IP addresses must always be Latin digits in every language, so
      // localized keyboard digits are mapped back to 0-9 as soon as typed.
      onChanged: (value) {
        final latin = toLatinDigits(value);
        if (latin != value) {
          controller.value = TextEditingValue(
            text: latin,
            selection: TextSelection.collapsed(offset: latin.length),
          );
        }
        setState(() {});
      },
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _offline ? Colors.white70 : AppColors.darkText,
      ),
      decoration: InputDecoration(
        hintText: '192.168.1.10',
        hintStyle: TextStyle(
          color: _offline ? Colors.white38 : AppColors.softText,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          _offline ? Icons.wifi_off_rounded : Icons.lan_rounded,
          color: _offline ? Colors.white38 : AppColors.primary,
        ),
        filled: true,
        // No Wi-Fi → the box goes BLACK and locked (per owner welcome-screen
        // request) so nobody can attempt a connection on a dead network.
        fillColor: _offline
            ? Colors.black
            : AppColors.background.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onSubmitted: (_) =>
          _connecting || _offline || !_hasAnyIp ? null : _connect(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg_login.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 30,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // No Wi-Fi → the whole connection form locks down: a red
                          // banner, black/disabled IP boxes and a dead Connect button.
                          if (_offline) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.wifi_off_rounded,
                                    color: AppColors.danger,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      context.tr(
                                        'وایفای پەیوەست نییە - ناتوانیت ببەسترێیتەوە',
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // One IP box per bound/saved address.
                          for (var i = 0; i < _ipControllers.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildIpField(_ipControllers[i]),
                                ),
                                const SizedBox(width: 4),
                                // Small "x" to remove this box (kept tiny, no text).
                                IconButton(
                                  onPressed: _connecting || _offline
                                      ? null
                                      : () => _removeBox(i),
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  icon: const Icon(Icons.cancel_rounded),
                                  color: AppColors.softText,
                                  tooltip: context.tr('سڕینەوە'),
                                ),
                              ],
                            ),
                          ],
                          // Small "+" button (icon only, no text) below the boxes:
                          // adds another IP box, up to [_maxIps] total.
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Center(
                              child: IconButton(
                                onPressed: _connecting || _offline
                                    ? null
                                    : _addBox,
                                icon: const Icon(Icons.add_rounded, size: 24),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.primary.withValues(
                                    alpha: 0.14,
                                  ),
                                  foregroundColor: AppColors.primary,
                                  disabledForegroundColor: AppColors.softText,
                                  minimumSize: const Size(40, 40),
                                ),
                                tooltip: context.tr('زیادکردنی IP'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _connecting || _offline || !_hasAnyIp
                                  ? null
                                  : _connect,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _connecting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      context.tr('کۆنێکت'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _connecting
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            child: Text(
                              context.tr('گەڕانەوە بۆ چوونە ژوورەوە'),
                              style: const TextStyle(color: AppColors.darkText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Semantics(
                  label: 'hama',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openHiddenHamaPage,
                    child: const SizedBox(width: 56, height: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
