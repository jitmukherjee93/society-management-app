import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Centralized Date and Currency formatters across the application
class AppFormatters {
  static final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _currencyDecimalsFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final DateFormat _dateFmt = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _monthYearFmt = DateFormat('MMMM yyyy');
  static final DateFormat _shortMonthYearFmt = DateFormat('MMM yyyy');
  static final DateFormat _guardTimeFmt = DateFormat('hh:mm a, dd MMM');

  /// Direct helper: AppFormatters.currency(1500) -> ₹1,500
  static String currency(num? amount) => _currencyFmt.format(amount ?? 0);

  /// Direct helper: AppFormatters.currencyDecimals(1500.5) -> ₹1,500.50
  static String currencyDecimals(num? amount) => _currencyDecimalsFmt.format(amount ?? 0);

  /// Direct helper: AppFormatters.date(dateTime) -> 07 Sep 2026
  static String date(DateTime? dt) => dt != null ? _dateFmt.format(dt) : '';

  /// Direct helper: AppFormatters.dateTime(dateTime) -> 07 Sep 2026, 03:45 PM
  static String dateTime(DateTime? dt) => dt != null ? _dateTimeFmt.format(dt) : '';

  /// Direct helper: AppFormatters.guardTime(dateTime) -> 10:30 AM, 14 Sep
  static String guardTime(DateTime? dt) => dt != null ? _guardTimeFmt.format(dt) : '';

  /// Direct helper: AppFormatters.monthYear(dateTime) -> September 2026
  static String monthYear(DateTime? dt) => dt != null ? _monthYearFmt.format(dt) : '';

  /// Direct helper: AppFormatters.shortMonthYear(dateTime) -> Sep 2026
  static String shortMonthYear(DateTime? dt) => dt != null ? _shortMonthYearFmt.format(dt) : '';

  // Getters for intl formatter instances
  static NumberFormat get currencyFormat => _currencyFmt;
  static DateFormat get dateFormat => _dateFmt;
  static DateFormat get dateTimeFormat => _dateTimeFmt;
  static DateFormat get guardTimeFormat => _guardTimeFmt;

  /// Centralized TextInputFormatter to automatically force uppercase letters
  /// in real-time as users type or paste text into vehicle number fields.
  static final TextInputFormatter upperCaseFormatter = UpperCaseTextFormatter();

  /// Canonical normalization utility for vehicle registration numbers throughout the app.
  /// Trims leading/trailing whitespace and converts all characters to uppercase.
  /// Returns empty string if the provided vehicle string is null or empty.
  static String vehicleNumber(String? reg) {
    if (reg == null) return '';
    return reg.trim().toUpperCase();
  }
}

/// Custom TextInputFormatter that automatically transforms any lowercase character
/// to uppercase in real-time while preserving cursor/selection position.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the text is already uppercase or empty, return unchanged
    if (newValue.text.isEmpty || newValue.text == newValue.text.toUpperCase()) {
      return newValue;
    }
    // Convert text to uppercase while preserving user selection/cursor offset
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

