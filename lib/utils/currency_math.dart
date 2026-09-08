/// Utility for decimal-accurate currency arithmetic and formatting
class CurrencyMath {
  /// Rounds an amount to 2 decimal places (paise precision)
  static double roundPaise(double amount) {
    return (amount * 100).round() / 100.0;
  }

  /// Converts a rupee amount to integer paise
  static int toPaise(double amount) {
    return (amount * 100).round();
  }

  /// Converts integer paise back to double rupees
  static double fromPaise(int paise) {
    return paise / 100.0;
  }

  /// Safely sums a collection of amounts with paise precision
  static double sum(Iterable<double> amounts) {
    int totalPaise = 0;
    for (final amount in amounts) {
      totalPaise += (amount * 100).round();
    }
    return totalPaise / 100.0;
  }
}

