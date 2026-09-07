import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Reusable decorations, compact badges, and borders
class AppDecorations {
  /// Standard compact card decoration with subtle border
  static BoxDecoration card({
    Color? backgroundColor,
    Color? color,
    Color borderColor = AppColors.border,
    double borderRadius = 12.0,
    bool hasShadow = true,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? color ?? AppColors.cardSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 0.9),
      boxShadow: hasShadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  /// Compact header icon container
  static Widget iconContainer({
    required IconData icon,
    Color color = AppColors.primary,
    Color? surfaceColor,
    Color? backgroundColor,
    double size = 18,
    double padding = 8,
    double borderRadius = 8,
  }) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: surfaceColor ?? backgroundColor ?? color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// Compact Status Badges & Chips
class AppBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final double fontSize;
  final EdgeInsets padding;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  factory AppBadge.success(String label, {IconData? icon}) {
    return AppBadge(
      label: label,
      icon: icon ?? Icons.check_circle_outline,
      textColor: AppColors.success,
      backgroundColor: AppColors.successSurface,
      borderColor: AppColors.successBorder,
    );
  }

  factory AppBadge.warning(String label, {IconData? icon}) {
    return AppBadge(
      label: label,
      icon: icon ?? Icons.hourglass_top_rounded,
      textColor: AppColors.warning,
      backgroundColor: AppColors.warningSurface,
      borderColor: AppColors.warningBorder,
    );
  }

  factory AppBadge.error(String label, {IconData? icon}) {
    return AppBadge(
      label: label,
      icon: icon ?? Icons.error_outline,
      textColor: AppColors.error,
      backgroundColor: AppColors.errorSurface,
      borderColor: AppColors.errorBorder,
    );
  }

  factory AppBadge.info(String label, {IconData? icon}) {
    return AppBadge(
      label: label,
      icon: icon ?? Icons.info_outline,
      textColor: AppColors.info,
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.infoBorder,
    );
  }

  factory AppBadge.category(String label, {bool isOnline = true}) {
    final color = isOnline ? AppColors.onlinePayment : AppColors.offlinePayment;
    return AppBadge(
      label: label,
      icon: isOnline ? Icons.credit_card : Icons.receipt_long,
      textColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.25),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
