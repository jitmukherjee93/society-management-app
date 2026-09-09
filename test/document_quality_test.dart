import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:society_management/services/document_quality_service.dart';

void main() {
  group('Document Quality & Readability Verification Tests', () {
    test('Rejects tiny corrupted or empty PDF files', () async {
      final emptyPdf = Uint8List.fromList([1, 2, 3]);
      final result = await DocumentQualityService.evaluateAndOptimize(
        bytes: emptyPdf,
        fileName: 'voucher.pdf',
      );
      expect(result.isReadable, isFalse);
      expect(result.rejectionReason, contains('empty'));
    });

    test('Accepts valid PDF files', () async {
      final validPdf = Uint8List.fromList(
        List.filled(400, 65)..setRange(0, 5, '%PDF-'.codeUnits),
      );
      final result = await DocumentQualityService.evaluateAndOptimize(
        bytes: validPdf,
        fileName: 'rent_agreement.pdf',
      );
      expect(result.isReadable, isTrue);
      expect(result.optimizedBytes, isNotNull);
    });

    test('Rejects low-resolution image under minimum dimension (e.g. 100x100)', () async {
      final lowResImg = img.Image(width: 100, height: 100);
      img.fill(lowResImg, color: img.ColorRgb8(200, 200, 200));
      final jpgBytes = Uint8List.fromList(img.encodeJpg(lowResImg));

      final result = await DocumentQualityService.evaluateAndOptimize(
        bytes: jpgBytes,
        fileName: 'receipt_thumb.jpg',
      );
      expect(result.isReadable, isFalse);
      expect(result.rejectionReason, contains('resolution is too low'));
    });

    test('Rejects completely blank or low-contrast images', () async {
      final blankImg = img.Image(width: 400, height: 400);
      img.fill(blankImg, color: img.ColorRgb8(128, 128, 128)); // completely uniform gray
      final jpgBytes = Uint8List.fromList(img.encodeJpg(blankImg));

      final result = await DocumentQualityService.evaluateAndOptimize(
        bytes: jpgBytes,
        fileName: 'blank_scan.jpg',
      );
      expect(result.isReadable, isFalse);
      expect(result.rejectionReason, contains('blank, overexposed, or too dark'));
    });

    test('Accepts sharp document image with text-like high frequency edges and optimizes size', () async {
      // Create a simulated sharp document with high-contrast text lines and borders
      final sharpImg = img.Image(width: 2000, height: 2000);
      img.fill(sharpImg, color: img.ColorRgb8(255, 255, 255));

      // Draw high-contrast black grid and text-like strokes
      for (int y = 50; y < 1950; y += 40) {
        for (int x = 50; x < 1950; x += 10) {
          if ((x / 10).floor() % 2 == 0) {
            img.fillRect(sharpImg, x1: x, y1: y, x2: x + 6, y2: y + 20, color: img.ColorRgb8(0, 0, 0));
          }
        }
      }

      final origBytes = Uint8List.fromList(img.encodePng(sharpImg)); // Uncompressed PNG ~ large

      final result = await DocumentQualityService.evaluateAndOptimize(
        bytes: origBytes,
        fileName: 'voucher_receipt.png',
      );

      expect(result.isReadable, isTrue);
      expect(result.sharpnessScore > DocumentQualityService.blurThreshold, isTrue);
      expect(result.optimizedBytes, isNotNull);
      expect(result.optimizedBytes!.isNotEmpty, isTrue);
      expect(result.optimizedFileName, 'voucher_receipt.jpg');
    });
  });
}

