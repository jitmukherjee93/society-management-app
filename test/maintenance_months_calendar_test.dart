import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/widgets/maintenance/maintenance_months_calendar.dart';

void main() {
  group('MaintenanceMonthsCalendar Widget & Logic Tests', () {
    const testBreakdownWithVehicles = FlatMaintenanceBreakdown(
      flatNumber: 'B-312',
      block: 'B',
      baseMaintenance: 1200.0,
      carParkingCharges: 430.0,
      bikeParkingCharges: 100.0,
      carCount: 1,
      bikeCount: 1,
      pujaSubscription: 0.0,
      totalMonthlyDue: 1730.0,
    );

    const testBreakdownNoVehicles = FlatMaintenanceBreakdown(
      flatNumber: 'A-101',
      block: 'A',
      baseMaintenance: 450.0,
      carParkingCharges: 0.0,
      bikeParkingCharges: 0.0,
      carCount: 0,
      bikeCount: 0,
      pujaSubscription: 0.0,
      totalMonthlyDue: 450.0,
    );

    testWidgets('Renders calendar header, financial year tag, and legend', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaintenanceMonthsCalendar(
                duesDocs: [],
                breakdown: testBreakdownWithVehicles,
                userData: {'name': 'Test Resident', 'flatNumber': 'B-312'},
                flatDisplay: 'B-312',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Payment Calendar by Month'), findsOneWidget);
      expect(find.text('FY 2026-27'), findsOneWidget);
      expect(find.text('Legend:'), findsOneWidget);
      expect(find.text('Maint + Vehicle'), findsWidgets);
      expect(find.text('Maintenance Only'), findsWidgets);
    });

    testWidgets('Displays month tiles for all 12 financial year months', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaintenanceMonthsCalendar(
                duesDocs: [],
                breakdown: testBreakdownNoVehicles,
                userData: {'name': 'No Vehicle Resident', 'flatNumber': 'A-101'},
                flatDisplay: 'A-101',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check key financial year month abbreviations
      expect(find.textContaining('APR'), findsOneWidget);
      expect(find.textContaining('MAY'), findsOneWidget);
      expect(find.textContaining('DEC'), findsOneWidget);
      expect(find.textContaining('MAR'), findsOneWidget);
    });

    testWidgets('Tapping a month tile opens bottom sheet with itemized breakdown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaintenanceMonthsCalendar(
                duesDocs: [],
                breakdown: testBreakdownWithVehicles,
                userData: {'name': 'Test Resident', 'flatNumber': 'B-312'},
                flatDisplay: 'B-312',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on the first month tile ('APR')
      final aprFinder = find.textContaining('APR');
      expect(aprFinder, findsOneWidget);
      await tester.tap(aprFinder);
      await tester.pumpAndSettle();

      // Verify bottom sheet appears
      expect(find.text('Itemized Bill Breakdown'), findsOneWidget);
      expect(find.text('Society Flat Maintenance'), findsOneWidget);
      expect(find.text('4-Wheeler Parking (1 Car @ ₹430)'), findsOneWidget);
      expect(find.text('2-Wheeler Parking (1 Bike @ ₹100)'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Renders properly without overflow on narrow screens (320px width)', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaintenanceMonthsCalendar(
                duesDocs: [],
                breakdown: testBreakdownWithVehicles,
                userData: {'name': 'Test Resident', 'flatNumber': 'B-312'},
                flatDisplay: 'B-312',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Payment Calendar by Month'), findsOneWidget);
    });
  });
}
