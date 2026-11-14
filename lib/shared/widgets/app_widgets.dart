import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'tv_focus.dart';

class TechBadge extends StatelessWidget {
  final String label;
  final Color? bgColor;
  final Color? textColor;

  const TechBadge({
    super.key,
    required this.label,
    this.bgColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor ?? AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.badge.copyWith(color: textColor ?? AppColors.white),
      ),
    );
  }
}

class FilterChipWidget extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const FilterChipWidget({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              const Icon(Icons.check, size: 14, color: AppColors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTheme.badge.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: isActive ? AppColors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StarRating extends StatelessWidget {
  final double rating;
  const StarRating({super.key, required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_outlined, color: Color(0xFFFFD700), size: 14),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: AppTheme.metadata.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTheme.sectionTitle),
          ),
          if (actionLabel != null)
            TvFocusable(
              onSelect: onAction,
              semanticLabel: actionLabel,
              scale: 1.05,
              borderRadius: 8,
              child: GestureDetector(
                onTap: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        actionLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.metadata.copyWith(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.primaryLight, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── CineSnackBar ─────────────────────────────────────────────────────────────
// Central helper so every toast in the app has consistent styling:
//   • Dark surface background
//   • White text (not the default system theme colour which can be dark on
//     some Material 3 themes, making text invisible on dark surfaces)
//   • Floating behaviour with rounded corners

class CineSnackBar {
  CineSnackBar._();

  /// Show a simple one-line toast.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? textColor,
    Widget? action,
    Color? backgroundColor,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTheme.badge.copyWith(
              color: textColor ?? AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: backgroundColor ?? AppColors.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          action: action is SnackBarAction ? action : null,
        ),
      );
  }

  /// Build a [SnackBar] directly (for cases where you need to add it
  /// to a [ScaffoldMessengerState] manually with your own timing).
  static SnackBar build(
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? textColor,
    Color? backgroundColor,
  }) {
    return SnackBar(
      content: Text(
        message,
        style: AppTheme.badge.copyWith(
          color: textColor ?? AppColors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor ?? AppColors.surfaceContainerHigh,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
