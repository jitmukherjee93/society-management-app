import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';

/// Professional, standardized modal dialog wrapper
class AppDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;
  final bool showCloseButton;

  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor = AppColors.primary,
    this.iconBgColor,
    required this.content,
    this.actions,
    this.maxWidth = 520,
    this.showCloseButton = true,
  });

  /// Static helper to launch the dialog easily
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    required IconData icon,
    Color iconColor = AppColors.primary,
    Color? iconBgColor,
    Widget? content,
    Widget? body,
    List<Widget>? actions,
    double maxWidth = 520,
    bool barrierDismissible = true,
  }) {
    final effectiveContent = content ?? body ?? const SizedBox.shrink();
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AppDialog(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        iconBgColor: iconBgColor,
        content: effectiveContent,
        actions: actions,
        maxWidth: maxWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 0.9),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
              child: Row(
                children: [
                  AppDecorations.iconContainer(
                    icon: icon,
                    color: iconColor,
                    size: 20,
                    padding: 8,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      splashRadius: 18,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable Dialog Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: content,
              ),
            ),

            // Footer Actions
            if (actions != null && actions!.isNotEmpty) ...[
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppColors.cardSurfaceSecondary,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
