import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/utils/app_formatters.dart';

void main() {
  group('AppFormatters Tests', () {
    test('currency formats whole numbers in Indian locale without decimals', () {
      expect(AppFormatters.currency(1500), '₹1,500');
      expect(AppFormatters.currency(0), '₹0');
      expect(AppFormatters.currency(100000), '₹1,00,000');
      expect(AppFormatters.currency(null), '₹0');
    });

    test('currencyDecimals formats numbers with 2 decimal places', () {
      expect(AppFormatters.currencyDecimals(1500.5), '₹1,500.50');
      expect(AppFormatters.currencyDecimals(0), '₹0.00');
      expect(AppFormatters.currencyDecimals(null), '₹0.00');
    });

    test('date formats DateTime to dd MMM yyyy and handles null', () {
      final dt = DateTime(2026, 9, 7);
      expect(AppFormatters.date(dt), '07 Sep 2026');
      expect(AppFormatters.date(null), '');
    });

    test('dateTime formats DateTime to dd MMM yyyy, hh:mm a and handles null', () {
      final dt = DateTime(2026, 9, 7, 15, 45);
      expect(AppFormatters.dateTime(dt), '07 Sep 2026, 03:45 PM');
      expect(AppFormatters.dateTime(null), '');
    });

    test('monthYear and shortMonthYear format properly', () {
      final dt = DateTime(2026, 9, 7);
      expect(AppFormatters.monthYear(dt), 'September 2026');
      expect(AppFormatters.shortMonthYear(dt), 'Sep 2026');
      expect(AppFormatters.monthYear(null), '');
      expect(AppFormatters.shortMonthYear(null), '');
    });
  });
}
