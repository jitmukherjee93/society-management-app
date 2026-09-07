/// Canonical utilities for standardizing flat numbers and blocks across the app
class FlatUtils {
  /// Standardizes flat numbers to canonical BLOCK-NUMBER format (e.g. 'B-312')
  static String normalize(String? rawFlat) {
    if (rawFlat == null) return '';
    final trimmed = rawFlat.trim().toUpperCase();
    if (trimmed.isEmpty) return '';

    // If already contains hyphen (e.g., 'B-312')
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length == 2) {
        return '${parts[0].trim()}-${parts[1].trim()}';
      }
      return trimmed;
    }

    // Match leading block letter followed by flat digits (e.g., 'B312' -> 'B-312')
    final match = RegExp(r'^([A-D])(\d{3,4})$').firstMatch(trimmed);
    if (match != null) {
      return '${match.group(1)}-${match.group(2)}';
    }

    return trimmed;
  }

  /// Extracts the block letter (A, B, C, D) from a flat number
  static String extractBlock(String? rawFlat) {
    final norm = normalize(rawFlat);
    if (norm.startsWith('A')) return 'A';
    if (norm.startsWith('B')) return 'B';
    if (norm.startsWith('C')) return 'C';
    if (norm.startsWith('D')) return 'D';
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

