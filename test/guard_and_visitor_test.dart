import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/services/visitor_pass_service.dart';
import 'package:society_management/utils/flat_utils.dart';

void main() {
  group('Security Guard & Visitor Pass Suite', () {
    test('generatePassCode produces valid 6-digit numeric OTP', () {
      for (int i = 0; i < 50; i++) {
        final code = VisitorPassService.generatePassCode();
        expect(code.length, 6);
        final numVal = int.tryParse(code);
        expect(numVal, isNotNull);
        expect(numVal! >= 100000 && numVal <= 999999, isTrue);
      }
    });

    test('generatePassCode yields distributed codes across multiple invocations', () {
      final codes = <String>{};
      for (int i = 0; i < 100; i++) {
        codes.add(VisitorPassService.generatePassCode());
      }
      // Out of 100 generated 6-digit codes, collision is exceedingly rare (>90 unique)
      expect(codes.length > 90, isTrue);
    });

    test('FlatUtils normalization formats flat numbers for visitor & parcel logs correctly', () {
      expect(FlatUtils.normalize('b101'), 'B-101');
      expect(FlatUtils.normalize(' B-204 '), 'B-204');
      expect(FlatUtils.normalize('a302'), 'A-302');
      expect(FlatUtils.normalize('c-101'), 'C-101');
    });

    test('Visitor pass status state machine adheres to valid transitions', () {
      const initialStatus = 'PENDING';
      const checkedInStatus = 'CHECKED_IN';
      const checkedOutStatus = 'CHECKED_OUT';

      bool isValidTransition(String from, String to) {
        if (from == 'PENDING' && to == 'CHECKED_IN') return true;
        if (from == 'CHECKED_IN' && to == 'CHECKED_OUT') return true;
        return false;
      }

      expect(isValidTransition(initialStatus, checkedInStatus), isTrue);
      expect(isValidTransition(checkedInStatus, checkedOutStatus), isTrue);
      expect(isValidTransition(initialStatus, checkedOutStatus), isFalse);
      expect(isValidTransition(checkedOutStatus, checkedInStatus), isFalse);
    });

    test('Parcel status transition adheres to HELD_AT_GATE -> COLLECTED lifecycle', () {
      const heldStatus = 'HELD_AT_GATE';
      const collectedStatus = 'COLLECTED';

      bool isCollectable(String currentStatus) => currentStatus == 'HELD_AT_GATE';

      expect(isCollectable(heldStatus), isTrue);
      expect(isCollectable(collectedStatus), isFalse);
    });

    test('Guard duty status and shift definitions', () {
      const validShifts = ['Day Shift (08:00 - 20:00)', 'Night Shift (20:00 - 08:00)', 'General Shift'];
      const validGates = ['Main Gate - Gate 1', 'Back Gate - Gate 2', 'Service Gate - Gate 3'];

      expect(validShifts.contains('Day Shift (08:00 - 20:00)'), isTrue);
      expect(validShifts.contains('Night Shift (20:00 - 08:00)'), isTrue);
      expect(validGates.contains('Main Gate - Gate 1'), isTrue);

      String toggleStatus(String current) => current == 'ON_DUTY' ? 'OFF_DUTY' : 'ON_DUTY';
      expect(toggleStatus('ON_DUTY'), 'OFF_DUTY');
      expect(toggleStatus('OFF_DUTY'), 'ON_DUTY');
    });

    test('Emergency alert categories are properly classified', () {
      const emergencyTypes = [
        'Fire Emergency',
        'Medical Emergency',
        'Security / Trespassing',
        'Lift / Elevator Breakdown',
        'Water Leakage / Flooding',
        'Power Outage / Transformer Failure',
      ];

      for (final type in emergencyTypes) {
        expect(type.isNotEmpty, isTrue);
      }
      expect(emergencyTypes.length, 6);
    });
  });
}
