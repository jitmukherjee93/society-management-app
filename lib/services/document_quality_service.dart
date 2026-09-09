import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Result of document readability and optimization analysis
class ReadabilityResult {
  final bool isReadable;
  final String? rejectionReason;
  final double sharpnessScore;
  final Uint8List? optimizedBytes;
  final String? optimizedFileName;
  final int originalWidth;
  final int originalHeight;
  final int optimizedWidth;
  final int optimizedHeight;
  final int originalSize;
  final int optimizedSize;

  const ReadabilityResult({
    required this.isReadable,
    this.rejectionReason,
    required this.sharpnessScore,
    this.optimizedBytes,
    this.optimizedFileName,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.optimizedWidth = 0,
    this.optimizedHeight = 0,
    this.originalSize = 0,
    this.optimizedSize = 0,
  });
}

/// Service for validating document readability, detecting blurriness/low contrast,
/// and optimizing/shrinking document image payloads before uploading to Firebase.
class DocumentQualityService {
  /// Minimum width and height required for readable text on mobile/web
  static const int minDimension = 250;

  /// Maximum target dimension for document images (e.g. vouchers, cheques, agreements)
  static const int maxDocumentDimension = 1400;

  /// Sharpness score threshold below which image is deemed blurry
  static const double blurThreshold = 85.0;

  /// Minimum luminance contrast standard deviation
  static const double minContrastStdDev = 12.0;

  /// Analyzes a file's bytes for text readability and optimizes if readable.
  static Future<ReadabilityResult> evaluateAndOptimize({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final lower = fileName.toLowerCase();

    // 1. PDF Handling
    if (lower.endsWith('.pdf')) {
      if (bytes.length < 300) {
        return ReadabilityResult(
          isReadable: false,
          rejectionReason: 'The PDF file appears corrupted or empty (less than 300 bytes).',
          sharpnessScore: 0,
          originalSize: bytes.length,
        );
      }
      // Valid PDF magic header check: %PDF-
      if (bytes.length >= 5) {
        final header = String.fromCharCodes(bytes.take(5));
        if (!header.startsWith('%PDF')) {
          return ReadabilityResult(
            isReadable: false,
            rejectionReason: 'Invalid PDF format. Please upload a standard PDF document.',
            sharpnessScore: 0,
            originalSize: bytes.length,
          );
        }
      }
      return ReadabilityResult(
        isReadable: true,
        sharpnessScore: 100,
        optimizedBytes: bytes,
        optimizedFileName: fileName,
        originalSize: bytes.length,
        optimizedSize: bytes.length,
      );
    }

    // 2. Non-Image and CSV / Excel documents
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');

    if (!isImage) {
      return ReadabilityResult(
        isReadable: true,
        sharpnessScore: 100,
        optimizedBytes: bytes,
        optimizedFileName: fileName,
        originalSize: bytes.length,
        optimizedSize: bytes.length,
      );
    }

    // 3. Image Decoding
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      return ReadabilityResult(
        isReadable: false,
        rejectionReason: 'Unable to decode the image. Please upload a valid JPG, PNG, or WebP photo.',
        sharpnessScore: 0,
        originalSize: bytes.length,
      );
    }

    final origW = decodedImage.width;
    final origH = decodedImage.height;

    // 4. Dimension Resolution Check
    if (origW < minDimension || origH < minDimension) {
      return ReadabilityResult(
        isReadable: false,
        rejectionReason: 'Image resolution is too low ($origW x $origH px). Document text and characters will be illegible.',
        sharpnessScore: 10,
        originalWidth: origW,
        originalHeight: origH,
        originalSize: bytes.length,
      );
    }

    // 5. Blur & Contrast Assessment (Laplacian Edge Variance)
    final grayscale = img.grayscale(decodedImage);
    final stats = _computeLaplacianAndContrast(grayscale);
    final sharpness = stats.laplacianVariance;
    final contrast = stats.contrastStdDev;

    debugPrint('Doc Quality Check: [sharpness=$sharpness, contrast=$contrast, res=${origW}x$origH]');

    if (contrast < minContrastStdDev) {
      return ReadabilityResult(
        isReadable: false,
        rejectionReason: 'The document image is almost entirely blank, overexposed, or too dark to read.',
        sharpnessScore: sharpness,
        originalWidth: origW,
        originalHeight: origH,
        originalSize: bytes.length,
      );
    }

    if (sharpness < blurThreshold) {
      return ReadabilityResult(
        isReadable: false,
        rejectionReason: 'The document appears blurry or out of focus (sharpness score: ${sharpness.toStringAsFixed(1)} / $blurThreshold). Characters cannot be clearly deciphered.',
        sharpnessScore: sharpness,
        originalWidth: origW,
        originalHeight: origH,
        originalSize: bytes.length,
      );
    }

    // 6. Optimization: Proportional Downscaling & High-Quality JPEG Compression
    img.Image targetImage = decodedImage;
    if (origW > maxDocumentDimension || origH > maxDocumentDimension) {
      if (origW >= origH) {
        targetImage = img.copyResize(
          decodedImage,
          width: maxDocumentDimension,
          interpolation: img.Interpolation.cubic,
        );
      } else {
        targetImage = img.copyResize(
          decodedImage,
          height: maxDocumentDimension,
          interpolation: img.Interpolation.cubic,
        );
      }
    }

    // Encode as compressed JPEG (quality 82 - crystal clear text, minimal file size)
    final optimizedJpgBytes = Uint8List.fromList(img.encodeJpg(targetImage, quality: 82));
    final baseName = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    final outName = '$baseName.jpg';

    return ReadabilityResult(
      isReadable: true,
      sharpnessScore: sharpness,
      optimizedBytes: optimizedJpgBytes,
      optimizedFileName: outName,
      originalWidth: origW,
      originalHeight: origH,
      optimizedWidth: targetImage.width,
      optimizedHeight: targetImage.height,
      originalSize: bytes.length,
      optimizedSize: optimizedJpgBytes.length,
    );
  }

  /// Computes Laplacian edge variance and luminance contrast standard deviation
  static _ImageStats _computeLaplacianAndContrast(img.Image gray) {
    final w = gray.width;
    final h = gray.height;

    // Sample across grid to keep computation instant even on large photos
    final step = (w * h > 1000000) ? 2 : 1;

    double sumLuminance = 0;
    double sumSqLuminance = 0;
    int pixelCount = 0;

    double sumLaplacian = 0;
    double sumSqLaplacian = 0;
    int laplacianCount = 0;

    for (int y = 1; y < h - 1; y += step) {
      for (int x = 1; x < w - 1; x += step) {
        final p = gray.getPixel(x, y).r;
        sumLuminance += p;
        sumSqLuminance += p * p;
        pixelCount++;

        // 3x3 Laplacian: 4*center - left - right - top - bottom
        final top = gray.getPixel(x, y - 1).r;
        final bottom = gray.getPixel(x, y + 1).r;
        final left = gray.getPixel(x - 1, y).r;
        final right = gray.getPixel(x + 1, y).r;

        final lap = (4 * p - top - bottom - left - right).abs().toDouble();
        sumLaplacian += lap;
        sumSqLaplacian += lap * lap;
        laplacianCount++;
      }
    }

    if (pixelCount == 0 || laplacianCount == 0) {
      return _ImageStats(0, 0);
    }

    final meanLum = sumLuminance / pixelCount;
    final varLum = max(0.0, (sumSqLuminance / pixelCount) - (meanLum * meanLum));
    final contrastStdDev = sqrt(varLum);

    final meanLap = sumLaplacian / laplacianCount;
    final varLap = max(0.0, (sumSqLaplacian / laplacianCount) - (meanLap * meanLap));

    return _ImageStats(varLap, contrastStdDev);
  }
}

class _ImageStats {
  final double laplacianVariance;
  final double contrastStdDev;
  const _ImageStats(this.laplacianVariance, this.contrastStdDev);
}

