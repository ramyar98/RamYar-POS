import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/fmt.dart';
import '../core/constants.dart';
import '../core/responsive.dart';
import '../services/app_localizations.dart';
import '../models/table_model.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final Color statusColor;
  final String statusText;
  final IconData statusIcon;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final String? subtitle;

  const TableCard({
    super.key,
    required this.table,
    required this.statusColor,
    required this.statusText,
    required this.statusIcon,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = table.status == TableStatus.empty;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      // A hundred cards staggering forty milliseconds apart meant the last card
      // took four and a half seconds to appear - on a full floor the colour
      // signal arrived seconds after the change. The cascade now wraps every
      // twelve cards, so the whole floor is readable well under a second.
      duration: Duration(milliseconds: 250 + (index % 12) * 30),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            // The border is what makes a status readable across a wall of a
            // hundred mostly-white cards. The tint alone was too quiet to
            // answer "is this table free, seated, billed or overdue?" from
            // across the room, which is the only distance that matters.
            border: Border.all(
              color: isEmpty
                  ? AppColors.borderSide.withValues(alpha: 0.55)
                  : statusColor.withValues(alpha: 0.55),
              width: isEmpty ? 1 : 1.8,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isEmpty
                  ? [Colors.white, const Color(0xFFFAFAFA)]
                  : [Colors.white, statusColor.withValues(alpha: 0.16)],
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: isEmpty ? 0.04 : 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.paddingMedium),
            child: Center(
              child: FittedBox(
                // On desktop/tablet the grid cell is much larger than the
                // card's natural content (at 1920 a cell is ~300px wide
                // against ~150px of content), and scaleDown would just center
                // the small content in a sea of white. contain grows the card
                // to fill its cell on the big screens while still scaling
                // down when the cell is tight - phones (<600) keep the
                // original scaleDown so the small-screen rendering is
                // untouched.
                fit: Responsive.isPhone(context)
                    ? BoxFit.scaleDown
                    : BoxFit.contain,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(
                              alpha: isEmpty ? 0.06 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(statusIcon, size: 16, color: statusColor),
                        ),
                        const SizedBox(width: 8),
                        if (!isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              context.tr(statusText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                          if (table.note.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.note_alt_rounded,
                              size: 14,
                              color: AppColors.blue,
                            ),
                          ],
                          if (trailing != null) ...[
                            const SizedBox(width: 4),
                            trailing!,
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      table.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isEmpty
                            ? AppColors.darkText.withValues(alpha: 0.5)
                            : AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!isEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: AppColors.softText.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            table.formattedSeatedTimeAmPm,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.trp('د.ع {amount}', {
                          'amount': money(table.totalAmount),
                        }),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 11,
                            color: AppColors.softText.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            subtitle!,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.softText.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.paddingSmall,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.borderSide.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.tr('بەتاڵ'),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.softText.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
