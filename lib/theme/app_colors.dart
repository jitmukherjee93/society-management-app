import 'package:flutter/material.dart';

/// Centralized color palette and semantic tokens for the Society Management App
class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF0F766E); // Deep Teal
  static const Color primaryDark = Color(0xFF115E59);
  static const Color primaryLight = Color(0xFFCCFBF1);
  static const Color secondary = Color(0xFF1E293B); // Slate 800
  static const Color accent = Color(0xFF2563EB); // Royal Blue

  // Surface & Neutral Gradients
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Colors.white;
  static const Color cardSurface = Colors.white;
  static const Color cardSurfaceSecondary = Color(0xFFF1F5F9); // Slate 100
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color borderDark = Color(0xFFCBD5E1); // Slate 300

  // Typography Colors
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400

  // Semantic Status: Success (Paid, Approved, Completed)
  static const Color success = Color(0xFF059669); // Emerald 600
  static const Color successSurface = Color(0xFFECFDF5); // Emerald 50
  static const Color successBorder = Color(0xFFA7F3D0); // Emerald 200

  // Semantic Status: Warning & Pending (Under Verification, Pending Approval)
  static const Color warning = Color(0xFFD97706); // Amber 600
  static const Color warningSurface = Color(0xFFFFFBEB); // Amber 50
  static const Color warningBorder = Color(0xFFFDE68A); // Amber 200

  // Semantic Status: Error & Rejected (Unpaid, Rejected, Overdue)
  static const Color error = Color(0xFFDC2626); // Red 600
  static const Color errorSurface = Color(0xFFFEF2F2); // Red 50
  static const Color errorBorder = Color(0xFFFECACA); // Red 200

  // Semantic Status: Info (Announcements, General Notice)
  static const Color info = Color(0xFF2563EB); // Blue 600
  static const Color infoSurface = Color(0xFFEFF6FF); // Blue 50
  static const Color infoBorder = Color(0xFFBFDBFE); // Blue 200

  // Category Colors
  static const Color onlinePayment = Color(0xFF1D4ED8); // Blue 700
  static const Color offlinePayment = Color(0xFF7E22CE); // Purple 700

  // Color Scale & Semantic Aliases
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  static const Color primarySurface = Color(0xFFCCFBF1);
  static const Color primaryBorder = Color(0xFF99F6E4); // Teal 200
  static const Color secondarySurface = Color(0xFFF1F5F9);
  static const Color secondaryBorder = Color(0xFFCBD5E1); // Slate 300
  static const Color secondaryDark = Color(0xFF0F172A);
  static const Color successDark = Color(0xFF047857);
  static const Color warningDark = Color(0xFFB45309);
  static const Color errorDark = Color(0xFFB91C1C);
  static const Color infoDark = Color(0xFF1D4ED8);
}
