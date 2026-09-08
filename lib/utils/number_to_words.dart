/// Converts numeric currency amount to words in Indian English format.
/// e.g. 1290 -> "Rupees One Thousand Two Hundred Ninety Only"
class NumberToWords {
  static const List<String> _units = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];

  static const List<String> _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String convert(num amount) {
    final int rupees = amount.floor();
    final int paise = ((amount - rupees) * 100).round();

    if (rupees == 0 && paise == 0) return 'Rupees Zero Only';

    final buffer = StringBuffer();
    if (rupees > 0) {
      buffer.write(_convertRupees(rupees));
      buffer.write(' Rupees');
    }

    if (paise > 0) {
      if (buffer.isNotEmpty) buffer.write(' and ');
      buffer.write(_convertLessThanOneThousand(paise));
      buffer.write(' Paise');
    }

    buffer.write(' Only');
    return buffer.toString().trim();
  }

  static String _convertRupees(int n) {
    if (n == 0) return '';

    // Indian Numbering System: Crores (10,000,000), Lakhs (100,000), Thousands (1,000), Hundreds (100)
    final parts = <String>[];

    final int crore = n ~/ 10000000;
    n %= 10000000;

    final int lakh = n ~/ 100000;
    n %= 100000;

    final int thousand = n ~/ 1000;
    n %= 1000;

    final int hundred = n ~/ 100;
    final int rest = n % 100;

    if (crore > 0) {
      parts.add('${_convertLessThanOneThousand(crore)} Crore');
    }
    if (lakh > 0) {
      parts.add('${_convertLessThanOneThousand(lakh)} Lakh');
    }
    if (thousand > 0) {
      parts.add('${_convertLessThanOneThousand(thousand)} Thousand');
    }
    if (hundred > 0) {
      parts.add('${_units[hundred]} Hundred');
    }
    if (rest > 0) {
      if (rest < 20) {
        parts.add(_units[rest]);
      } else {
        final t = _tens[rest ~/ 10];
        final u = _units[rest % 10];
        parts.add(u.isEmpty ? t : '$t $u');
      }
    }

    return parts.join(' ');
  }

  static String _convertLessThanOneThousand(int n) {
    if (n == 0) return '';
    final parts = <String>[];

    final int hundred = n ~/ 100;
    final int rest = n % 100;

    if (hundred > 0) {
      parts.add('${_units[hundred]} Hundred');
    }

    if (rest > 0) {
      if (rest < 20) {
        parts.add(_units[rest]);
      } else {
        final t = _tens[rest ~/ 10];
        final u = _units[rest % 10];
        parts.add(u.isEmpty ? t : '$t $u');
      }
    }

    return parts.join(' ');
  }
}

