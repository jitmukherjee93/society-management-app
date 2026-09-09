import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/utils/currency_math.dart';
import 'package:society_management/utils/flat_utils.dart';

void main() {
  group('Stability & Sanitization Unit Tests', () {
    test('CurrencyMath precision prevents floating-point rounding artifacts', () {
      final val1 = 1000.10;
      final val2 = 50.20;
      final result = CurrencyMath.roundPaise(val1 + val2);
      expect(result, 1050.30);
      expect(CurrencyMath.roundPaise(1050.0000000000002), 1050.00);
    });

    test('FlatUtils normalizes various flat number formats correctly', () {
      expect(FlatUtils.normalize('B-312'), 'B-312');
      expect(FlatUtils.normalize('b312'), 'B-312');
      expect(FlatUtils.normalize('312'), '312');
      expect(FlatUtils.normalize('  a-101  '), 'A-101');
      expect(FlatUtils.normalize('C-405'), 'C-405');
      expect(FlatUtils.normalize('d202'), 'D-202');
    });

    test('FlatUtils assigns correct accounting budget head to block', () {
      expect(FlatUtils.getMaintenanceHead('B-312'), 'Monthly Maintenance - Block B');
      expect(FlatUtils.getMaintenanceHead('A-101'), 'Monthly Maintenance - Block A');
      expect(FlatUtils.getMaintenanceHead('C-204'), 'Monthly Maintenance - Block C');
      expect(FlatUtils.getMaintenanceHead('D-401'), 'Monthly Maintenance - Block D');
      expect(FlatUtils.getMaintenanceHead('Unknown'), 'Monthly Maintenance Collection');
    });

    test('Complaint status sanitization logic resilience', () {
      String sanitizeStatus(dynamic raw) {
        final rawStatus = (raw ?? 'OPEN').toString().toUpperCase().replaceAll(' ', '_');
        const validStatuses = ['OPEN', 'IN_PROGRESS', 'RESOLVED'];
        return validStatuses.contains(rawStatus) ? rawStatus : 'OPEN';
      }

      expect(sanitizeStatus('OPEN'), 'OPEN');
      expect(sanitizeStatus('open'), 'OPEN');
      expect(sanitizeStatus('in progress'), 'IN_PROGRESS');
      expect(sanitizeStatus('IN_PROGRESS'), 'IN_PROGRESS');
      expect(sanitizeStatus('RESOLVED'), 'RESOLVED');
      expect(sanitizeStatus('resolved'), 'RESOLVED');
      expect(sanitizeStatus('CLOSED'), 'OPEN'); // Unknown fallback
      expect(sanitizeStatus(null), 'OPEN');
      expect(sanitizeStatus(''), 'OPEN');
    });
  });
}
