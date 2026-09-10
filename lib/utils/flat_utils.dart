/// Canonical utilities for standardizing flat numbers and blocks across the app
class FlatUtils {
  /// Standardizes flat numbers to canonical BLOCK-NUMBER format (e.g. 'B-312')
  static String normalize(String? rawFlat) {
    if (rawFlat == null) return '';
    final trimmed = rawFlat.trim().toUpperCase();
    if (trimmed.isEmpty) return '';

    // If already contains hyphen (e.g., 'B-312' or 'B-312-A')
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length >= 2) {
        final block = parts[0].trim();
        final rest = parts.sublist(1).map((p) => p.trim()).join('-');
        return '$block-$rest';
      }
      return trimmed;
    }

    // Match leading block letter followed by separator or digits (e.g., 'B 312' or 'B312' -> 'B-312')
    final match = RegExp(r'^([A-D])[\s-]*([0-9A-Za-z]+)$').firstMatch(trimmed);
    if (match != null) {
      return '${match.group(1)}-${match.group(2)}';
    }

    return trimmed;
  }

  /// Extracts the block letter (A, B, C, D) strictly from a flat number
  static String extractBlock(String? rawFlat) {
    final norm = normalize(rawFlat);
    final match = RegExp(r'^([A-D])(?=[- ]|$)').firstMatch(norm);
    if (match != null) {
      return match.group(1)!;
    }
    return 'General';
  }

  /// Returns the corresponding budget head name for a flat
  static String getMaintenanceHead(String? rawFlat) {
    final block = extractBlock(rawFlat);
    switch (block) {
      case 'A':
        return 'Monthly Maintenance - Block A';
      case 'B':
        return 'Monthly Maintenance - Block B';
      case 'C':
        return 'Monthly Maintenance - Block C';
      case 'D':
        return 'Monthly Maintenance - Block D';
      default:
        return 'Monthly Maintenance Collection';
    }
  }

  /// Returns all possible lookup variants for robust query matching
  static Set<String> getLookupKeys(String? rawFlat) {
    final norm = normalize(rawFlat);
    if (norm.isEmpty) return {};
    final keys = <String>{norm, norm.toLowerCase()};
    if (norm.contains('-')) {
      final parts = norm.split('-');
      keys.add(parts.last); // '312'
      keys.add(norm.replaceAll('-', '')); // 'B312'
      keys.add(norm.replaceAll('-', '').toLowerCase()); // 'b312'
    }
    return keys;
  }
}

