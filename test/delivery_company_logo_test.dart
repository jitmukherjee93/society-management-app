import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/widgets/delivery_company_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeliveryCompanyUtils - Brand Resolution Tests', () {
    test('resolves Blinkit correctly from various metadata keys', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Blinkit'),
        equals(DeliveryBrand.blinkit),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Blinkit grocery delivery'),
        equals(DeliveryBrand.blinkit),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(visitorName: 'Ramesh (Blinkit)'),
        equals(DeliveryBrand.blinkit),
      );
    });

    test('resolves Swiggy and Instamart correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Swiggy'),
        equals(DeliveryBrand.swiggy),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Swiggy / Instamart'),
        equals(DeliveryBrand.swiggy),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Instamart order delivery'),
        equals(DeliveryBrand.swiggy),
      );
    });

    test('resolves Zomato correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Zomato'),
        equals(DeliveryBrand.zomato),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(title: 'Zomato Food Delivery waiting at Main Gate'),
        equals(DeliveryBrand.zomato),
      );
    });

    test('resolves Zepto correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Zepto'),
        equals(DeliveryBrand.zepto),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Zepto 10 min groceries'),
        equals(DeliveryBrand.zepto),
      );
    });

    test('resolves Amazon correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Amazon'),
        equals(DeliveryBrand.amazon),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryProvider: 'Amazon Logistics'),
        equals(DeliveryBrand.amazon),
      );
    });

    test('resolves Flipkart correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Flipkart'),
        equals(DeliveryBrand.flipkart),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryProvider: 'Ekart (Flipkart)'),
        equals(DeliveryBrand.flipkart),
      );
    });

    test('resolves BigBasket and bbdaily correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'BigBasket'),
        equals(DeliveryBrand.bigbasket),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'bbdaily morning milk'),
        equals(DeliveryBrand.bigbasket),
      );
    });

    test('resolves Blue Dart courier correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Blue Dart / Courier'),
        equals(DeliveryBrand.blueDart),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Bluedart express parcel'),
        equals(DeliveryBrand.blueDart),
      );
    });

    test('resolves India Post and Speed Post correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'India Post'),
        equals(DeliveryBrand.indiaPost),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Speed Post envelope delivery'),
        equals(DeliveryBrand.indiaPost),
      );
    });

    test('resolves Dunzo correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Dunzo'),
        equals(DeliveryBrand.dunzo),
      );
    });

    test('resolves Domino\'s correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Domino\'s'),
        equals(DeliveryBrand.dominos),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(purpose: 'Domino pizza delivery'),
        equals(DeliveryBrand.dominos),
      );
    });

    test('resolves DTDC and Shadowfax correctly', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'DTDC'),
        equals(DeliveryBrand.dtdc),
      );
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Shadowfax'),
        equals(DeliveryBrand.shadowfax),
      );
    });

    test('falls back to other/generic delivery for unrecognized providers', () {
      expect(
        DeliveryCompanyUtils.resolveBrand(deliveryApp: 'Local Bakery Express'),
        equals(DeliveryBrand.other),
      );
      final info = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.other, 'Local Bakery Express');
      expect(info.displayName, equals('Local Bakery Express'));
    });
  });

  group('DeliveryCompanyUtils - Brand Info Metadata', () {
    test('returns accurate brand colors and display names', () {
      final blinkitInfo = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.blinkit);
      expect(blinkitInfo.displayName, equals('Blinkit'));
      expect(blinkitInfo.primaryColor, equals(const Color(0xFFF8CB46)));

      final swiggyInfo = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.swiggy);
      expect(swiggyInfo.displayName, equals('Swiggy'));
      expect(swiggyInfo.primaryColor, equals(const Color(0xFFFC8019)));

      final zomatoInfo = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.zomato);
      expect(zomatoInfo.displayName, equals('Zomato'));
      expect(zomatoInfo.primaryColor, equals(const Color(0xFFE23744)));

      final zeptoInfo = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.zepto);
      expect(zeptoInfo.displayName, equals('Zepto'));
      expect(zeptoInfo.primaryColor, equals(const Color(0xFF3B006A)));

      final amazonInfo = DeliveryCompanyUtils.getBrandInfo(DeliveryBrand.amazon);
      expect(amazonInfo.displayName, equals('Amazon'));
      expect(amazonInfo.primaryColor, equals(const Color(0xFF131921)));
    });
  });

  group('DeliveryCompanyLogo & DeliveryCompanyTag Widget Rendering', () {
    for (final brand in DeliveryBrand.values) {
      testWidgets('renders DeliveryCompanyLogo for ${brand.name} without crashing', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: DeliveryCompanyLogo(
                  brand: brand,
                  customName: brand == DeliveryBrand.other ? 'Custom Courier' : null,
                  size: 66,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(DeliveryCompanyLogo), findsOneWidget);
      });
    }

    testWidgets('renders DeliveryCompanyTag with brand name and mini logo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DeliveryCompanyTag(
                deliveryApp: 'Blinkit',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DeliveryCompanyTag), findsOneWidget);
      expect(find.text('Blinkit'), findsOneWidget);
      expect(find.byType(DeliveryCompanyLogo), findsOneWidget);
    });

    testWidgets('renders DeliveryCompanyTag for Swiggy / Instamart', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DeliveryCompanyTag(
                deliveryApp: 'Swiggy / Instamart',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DeliveryCompanyTag), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
    });
  });
}
