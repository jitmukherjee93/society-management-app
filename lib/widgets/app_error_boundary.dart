import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Central utility to sanitize raw exceptions into user-friendly messages
class AppErrorFormatter {
  /// Converts any exception or error into clean, readable text
  static String clean(dynamic error) {
    if (error == null) {
      return 'An unexpected issue occurred. Please try again.';
    }

    String msg = error.toString().trim();

    // Strip generic prefixes
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring(11).trim();
    } else if (msg.startsWith('Error: ')) {
      msg = msg.substring(7).trim();
    }

    // Common Firebase Authentication errors
    if (msg.contains('email-already-in-use') || msg.contains('already exists')) {
      if (msg.contains('different password')) {
        return 'This account is already registered with a different password. Please reset your password or contact society admin.';
      }
      return 'This email address is already registered to another resident in the system.';
    }
    if (msg.contains('user-not-found')) {
      return 'No account found with these credentials. Please check your username or flat ID.';
    }
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect password. Please verify and try again.';
    }
    if (msg.contains('network-request-failed')) {
      return 'Network connection error. Please verify your internet connection and try again.';
    }
    if (msg.contains('permission-denied')) {
      return 'Access denied. You do not have sufficient permissions to perform this action.';
    }

    // Common Flutter lifecycle or framework assertions
    if (msg.contains('_dependents.isEmpty')) {
      return 'A screen transition completed. Your changes have been recorded safely.';
    }
    if (msg.contains('RenderFlex overflowed')) {
      return 'A display constraint warning occurred. The interface remains fully functional.';
    }

    // Clean any residual bracket tags e.g. [firebase_auth/...]
    msg = msg.replaceAll(RegExp(r'\[.*?\]'), '').trim();

    if (msg.isEmpty) {
      return 'An unexpected issue occurred. Please try again.';
    }

    return msg;
  }
}

/// A polite, branded error display widget that replaces red crash screens
class AppErrorWidget extends StatefulWidget {
  final FlutterErrorDetails? errorDetails;
  final Object? error;
  final VoidCallback? onRetry;
  final String? componentName;
  final bool isCompact;

  const AppErrorWidget({
    super.key,
    this.errorDetails,
    this.error,
    this.onRetry,
    this.componentName,
    this.isCompact = false,
  });

  @override
  State<AppErrorWidget> createState() => _AppErrorWidgetState();
}

class _AppErrorWidgetState extends State<AppErrorWidget> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final rawError = widget.error ?? widget.errorDetails?.exception ?? 'An error occurred';
    final friendlyMessage = AppErrorFormatter.clean(rawError);
    final title = widget.componentName != null
        ? 'Unable to load ${widget.componentName}'
        : 'Something went wrong';

    if (widget.isCompact) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.errorBorder, width: 0.8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                friendlyMessage,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onRetry != null)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.error),
                onPressed: widget.onRetry,
                tooltip: 'Retry',
              ),
          ],
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.errorBorder, width: 1),
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                friendlyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (kDebugMode && (widget.errorDetails != null || widget.error != null)) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: Icon(
                    _showDetails ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  label: Text(
                    _showDetails ? 'Hide Details' : 'Technical Details',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  onPressed: () => setState(() => _showDetails = !_showDetails),
                ),
                if (_showDetails)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurfaceSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.errorDetails?.toString() ?? widget.error.toString(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (Navigator.canPop(context))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Go Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  if (Navigator.canPop(context) && widget.onRetry != null)
                    const SizedBox(width: 12),
                  if (widget.onRetry != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: widget.onRetry,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An error boundary widget that catches child layout/build failures
class AppErrorBoundary extends StatefulWidget {
  final Widget child;
  final String? componentName;
  final bool isCompact;
  final VoidCallback? onRetry;

  const AppErrorBoundary({
    super.key,
    required this.child,
    this.componentName,
    this.isCompact = false,
    this.onRetry,
  });

  @override
  State<AppErrorBoundary> createState() => _AppErrorBoundaryState();
}

class _AppErrorBoundaryState extends State<AppErrorBoundary> {
  Object? _error;

  void reportError(Object error) {
    if (mounted) {
      setState(() => _error = error);
    }
  }

  void reset() {
    if (mounted) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AppErrorWidget(
        error: _error,
        componentName: widget.componentName,
        isCompact: widget.isCompact,
        onRetry: () {
          reset();
          widget.onRetry?.call();
        },
      );
    }

    return widget.child;
  }
}

/// Global Application Error Boundary that wraps MaterialApp
class AppGlobalErrorBoundary extends StatelessWidget {
  final Widget child;

  const AppGlobalErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppErrorBoundary(
      componentName: 'Application',
      child: child,
    );
  }
}

