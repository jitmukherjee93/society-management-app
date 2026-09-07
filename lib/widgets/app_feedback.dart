import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Professional floating snackbars and embedded feedback banners
class AppFeedback {
  /// Displays a modern floating Success Toast
  static void showSuccess(BuildContext context, String message, {String? title}) {
    _showSnackBar(
      context,
      message: message,
      title: title,
      icon: Icons.check_circle_rounded,
      backgroundColor: AppColors.success,
    );
  }

  /// Displays a modern floating Error Toast
  static void showError(BuildContext context, String message, {String? title}) {
    _showSnackBar(
      context,
      message: message,
      title: title,
      icon: Icons.error_rounded,
      backgroundColor: AppColors.error,
    );
  }

  /// Displays a modern floating Warning Toast
  static void showWarning(BuildContext context, String message, {String? title}) {
    _showSnackBar(
      context,
      message: message,
      title: title,
      icon: Icons.warning_amber_rounded,
      backgroundColor: AppColors.warning,
    );
  }

  /// Displays a modern floating Info Toast
  static void showInfo(BuildContext context, String message, {String? title}) {
    _showSnackBar(
      context,
      message: message,
      title: title,
      icon: Icons.info_rounded,
      backgroundColor: AppColors.info,
    );
  }

  static void _showSnackBar(
    BuildContext context, {
    required String message,
    String? title,
    required IconData icon,
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title.isNotEmpty)
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

/// Embedded Banner Card for inline alerts, warnings, or instructions
class AppBanner extends StatelessWidget {
  final String message;
  final String? title;
  final IconData icon;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final Widget? trailing;

  const AppBanner({
    super.key,
    required this.message,
    this.title,
    required this.icon,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    this.trailing,
  });

  factory AppBanner.success({
    required String message,
    String? title,
    Widget? trailing,
  }) {
    return AppBanner(
      message: message,
      title: title,
      icon: Icons.check_circle_outline_rounded,
      textColor: AppColors.success,
      backgroundColor: AppColors.successSurface,
      borderColor: AppColors.successBorder,
      trailing: trailing,
    );
  }

  factory AppBanner.warning({
    required String message,
    String? title,
    Widget? trailing,
  }) {
    return AppBanner(
      message: message,
      title: title,
      icon: Icons.warning_amber_rounded,
      textColor: AppColors.warning,
      backgroundColor: AppColors.warningSurface,
      borderColor: AppColors.warningBorder,
      trailing: trailing,
    );
  }

  factory AppBanner.error({
    required String message,
    String? title,
    Widget? trailing,
  }) {
    return AppBanner(
      message: message,
      title: title,
      icon: Icons.error_outline_rounded,
      textColor: AppColors.error,
      backgroundColor: AppColors.errorSurface,
      borderColor: AppColors.errorBorder,
      trailing: trailing,
    );
  }

  factory AppBanner.info({
    required String message,
    String? title,
    Widget? trailing,
  }) {
    return AppBanner(
      message: message,
      title: title,
      icon: Icons.info_outline_rounded,
      textColor: AppColors.info,
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.infoBorder,
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: textColor == AppColors.error
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

