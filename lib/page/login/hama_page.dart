import 'package:flutter/material.dart';

import '../../core/colors.dart';
import '../../services/app_localizations.dart';
import '../../services/owner_access.dart';

/// Hidden "hama" connect page.
///
/// It is reached only from the invisible tap target in the top-left corner of
/// the login screen (see `pin_login_page.dart`) and is linked from nowhere
/// else. There is no title, no branding and no back affordance beyond the
/// standard text button, so nobody browsing the app would stumble on it.
///
/// The single text box shows a harmless company-name prompt so the hidden
/// access is not obvious; the one code that is accepted is still `++`.
/// A correct code shows "Connected" and returns to the login screen
/// immediately; anything else is reported as wrong.
class HamaPage extends StatefulWidget {
  const HamaPage({super.key});

  @override
  State<HamaPage> createState() => _HamaPageState();
}

class _HamaPageState extends State<HamaPage> {
  /// The accepted code. Not a digit string and not linked to any account PIN.
  static const String _code = '++';

  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final entered = _controller.text.trim();
    if (entered != _code) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('هەڵەیە'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    // Completing the hidden route is what unlocks the owner PIN for this
    // session (see `OwnerAccess` / `AuthNotifier.loginWithPin`).
    OwnerAccess.unlock();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('کۆنێکت کرا'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(milliseconds: 800),
      ),
    );
    // Report "Connected", then go straight back to the login screen.
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).maybePop();
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
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
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _connect(),
                        maxLength: 2,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkText,
                        ),
                        decoration: InputDecoration(
                          hintText: context.tr('ناوی کۆمپانیاکەت بنووسە ڕامیار'),
                          hintStyle: const TextStyle(
                            color: AppColors.softText,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.primary,
                          ),
                          filled: true,
                          fillColor: AppColors.background.withValues(
                            alpha: 0.5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _busy ? null : _connect,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
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
                        onPressed: _busy
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
        ),
      ),
    );
  }
}
