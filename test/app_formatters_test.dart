import 'package:flutter/services.dart';
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

    test('guardTime formats DateTime to hh:mm a, dd MMM and handles null', () {
      final dt = DateTime(2026, 9, 14, 10, 30);
      expect(AppFormatters.guardTime(dt), '10:30 AM, 14 Sep');
      expect(AppFormatters.guardTime(null), '');
    });

    test('vehicleNumber normalizes and auto-capitalizes registration numbers', () {
      expect(AppFormatters.vehicleNumber(null), '');
      expect(AppFormatters.vehicleNumber(''), '');
      expect(AppFormatters.vehicleNumber('   '), '');
      expect(AppFormatters.vehicleNumber('dl 01 ab 1234'), 'DL 01 AB 1234');
      expect(AppFormatters.vehicleNumber('  wb02cd5678  '), 'WB02CD5678');
      expect(AppFormatters.vehicleNumber('Mh-12-de-9999'), 'MH-12-DE-9999');
    });

    test('UpperCaseTextFormatter converts lowercase input to uppercase preserving selection', () {
      final formatter = AppFormatters.upperCaseFormatter;
      const oldValue = TextEditingValue(text: '');
      const newValue = TextEditingValue(
        text: 'wb06a1234',
        selection: TextSelection.collapsed(offset: 9),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'WB06A1234');
      expect(result.selection.baseOffset, 9);
      expect(result.selection.extentOffset, 9);
    });

    test('UpperCaseTextFormatter returns unchanged value when text is already uppercase', () {
      final formatter = AppFormatters.upperCaseFormatter;
      const oldValue = TextEditingValue(text: 'WB06');
      const newValue = TextEditingValue(
        text: 'WB06A',
        selection: TextSelection.collapsed(offset: 5),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, 'WB06A');
      expect(result.selection.baseOffset, 5);
    });
  });
}
