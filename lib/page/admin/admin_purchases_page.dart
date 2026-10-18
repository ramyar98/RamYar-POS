import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/widgets/amount_input_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../providers/auth_provider.dart';

class AdminPurchasesPage extends ConsumerStatefulWidget {
  const AdminPurchasesPage({super.key});

  @override
  ConsumerState<AdminPurchasesPage> createState() => _AdminPurchasesPageState();
}

class _AdminPurchasesPageState extends ConsumerState<AdminPurchasesPage> {
  final _itemController = TextEditingController();
  final _priceController = TextEditingController();
  bool _isAdding = false;

  late final VoidCallback _revisionListener;

  @override
  void initState() {
    super.initState();
    _revisionListener = () {
      if (mounted) setState(() {});
    };
    ref.read(localDbProvider).shiftsRevision.addListener(_revisionListener);
  }

  @override
  void dispose() {
    try {
      ref
          .read(localDbProvider)
          .shiftsRevision
          .removeListener(_revisionListener);
    } catch (_) {}
    _itemController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _addPurchase() async {
    final name = _itemController.text.trim();
    final price = parseAmount(_priceController.text).toDouble();
    if (name.isEmpty || price <= 0) return;
    setState(() => _isAdding = true);
    final db = ref.read(localDbProvider);
    final user = ref.read(authProvider);
    await db.addPurchase(
      Purchase(
        itemName: name,
        price: price,
        purchasedAt: DateTime.now().toIso8601String(),
        purchasedBy: user?.id ?? 0,
      ),
    );
    _itemController.clear();
    _priceController.clear();
    setState(() => _isAdding = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.tr('کڕینی ئەشیاکان'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(AppConstants.paddingMedium),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Responsive.isPhone(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _itemController,
                        decoration: InputDecoration(
                          labelText: context.tr('ناوی ئاشیا'),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [AmountInputFormatter()],
                              decoration: InputDecoration(
                                labelText: context.tr('نرخ (د.ع)'),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _isAdding ? null : _addPurchase,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(context.tr('زیادکردن')),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _itemController,
                          decoration: InputDecoration(
                            labelText: context.tr('ناوی ئاشیا'),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [AmountInputFormatter()],
                          decoration: InputDecoration(
                            labelText: context.tr('نرخ (د.ع)'),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _isAdding ? null : _addPurchase,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(context.tr('زیادکردن')),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: FutureBuilder<List<Purchase>>(
              future: ref.read(localDbProvider).getAllPurchases(),
              builder: (context, snapshot) {
                final purchases = snapshot.data ?? [];
                if (purchases.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('هیچ کڕینێک نییە'),
                      style: TextStyle(color: AppColors.softText),
                    ),
                  );
                }
                final total = purchases.fold<double>(
                  0,
                  (sum, p) => sum + p.price,
                );
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                  ),
                  itemCount: purchases.length + 1,
                  itemBuilder: (context, index) {
                    if (index == purchases.length) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Text(
                              context.tr('کۆی گشتی'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${context.tr('د.ع')} ${money(total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final purchase = purchases[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_rounded,
                              color: AppColors.danger,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  purchase.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  purchase.purchasedAt.substring(0, 10),
                                  style: TextStyle(
                                    color: AppColors.softText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${context.tr('د.ع')} ${money(purchase.price)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
