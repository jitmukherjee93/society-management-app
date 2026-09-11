import 'package:intl/intl.dart';

// Ramkrishnapuram Residents' Welfare Association
// Official Budget 2026-27 Accounting Heads and Configuration
// Updated strictly as per "Updated RKP Budget.pdf"

class BudgetHead {
  final String name;
  final String category;
  final double yearlyBudget;
  final double? _explicitMonthlyBudget;
  final bool isDocRequired;
  final String description;
  final bool isRevised;
  final String? momDocumentUrl;
  final String? momFileName;
  final String? meetingType;
  final DateTime? meetingDate;
  final String? revisionReason;
  final String? revisedBy;
  final DateTime? revisedAt;

  const BudgetHead({
    required this.name,
    required this.category,
    required this.yearlyBudget,
    double? monthlyBudget,
    this.isDocRequired = true,
    this.description = '',
    this.isRevised = false,
    this.momDocumentUrl,
    this.momFileName,
    this.meetingType,
    this.meetingDate,
    this.revisionReason,
    this.revisedBy,
    this.revisedAt,
  }) : _explicitMonthlyBudget = monthlyBudget;

  double get monthlyBudget => _explicitMonthlyBudget ?? (yearlyBudget / 12);

  BudgetHead copyWith({
    String? name,
    String? category,
    double? yearlyBudget,
    double? monthlyBudget,
    bool? isDocRequired,
    String? description,
    bool? isRevised,
    String? momDocumentUrl,
    String? momFileName,
    String? meetingType,
    DateTime? meetingDate,
    String? revisionReason,
    String? revisedBy,
    DateTime? revisedAt,
  }) {
    return BudgetHead(
      name: name ?? this.name,
      category: category ?? this.category,
      yearlyBudget: yearlyBudget ?? this.yearlyBudget,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      isDocRequired: isDocRequired ?? this.isDocRequired,
      description: description ?? this.description,
      isRevised: isRevised ?? this.isRevised,
      momDocumentUrl: momDocumentUrl ?? this.momDocumentUrl,
      momFileName: momFileName ?? this.momFileName,
      meetingType: meetingType ?? this.meetingType,
      meetingDate: meetingDate ?? this.meetingDate,
      revisionReason: revisionReason ?? this.revisionReason,
      revisedBy: revisedBy ?? this.revisedBy,
      revisedAt: revisedAt ?? this.revisedAt,
    );
  }
}

class AccountingConfig {
  /// Simulated date for testing. Set to null for normal operation (uses DateTime.now()).
  static DateTime? simulatedDate;

  /// Current active date (either simulated or system now)
  static DateTime get currentDate => simulatedDate ?? DateTime.now();

  /// Generates the canonical financial year label (e.g. '2026-27')
  static String getFinancialYear([DateTime? date]) {
    final d = date ?? currentDate;
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final endYear = (startYear + 1) % 100;
    return '$startYear-${endYear.toString().padLeft(2, '0')}';
  }

  /// Dynamically computes financial year months for a given financial year or date
  static List<String> getFinancialYearMonths([DateTime? date]) {
    final d = date ?? currentDate;
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    return [
      'April $startYear',
      'May $startYear',
      'June $startYear',
      'July $startYear',
      'August $startYear',
      'September $startYear',
      'October $startYear',
      'November $startYear',
      'December $startYear',
      'January ${startYear + 1}',
      'February ${startYear + 1}',
      'March ${startYear + 1}',
    ];
  }

  /// Current active financial year string
  static String get currentFinancialYear => getFinancialYear();

  /// Chronological list of months in the active financial year
  static List<String> get financialYearMonths => getFinancialYearMonths();

  /// Returns the 0-based index of a month within the FY, or -1 if unknown
  static int getMonthIndex(String monthName) {
    final clean = monthName.trim();
    final months = financialYearMonths;
    for (int i = 0; i < months.length; i++) {
      if (months[i].toLowerCase() == clean.toLowerCase()) return i;
      // Partial check like "September" matching "September 2026"
      if (months[i].toLowerCase().startsWith(clean.toLowerCase())) return i;
    }
    return -1;
  }

  /// Determines if a month string (e.g. 'April 2026', 'March 2027', 'January 2026') is in the past
  /// relative to [referenceDate] (defaults to [currentDate]).
  /// Accurately handles prior financial years and arbitrary historical dates.
  static bool isMonthPast(String monthStr, [DateTime? referenceDate]) {
    final now = referenceDate ?? currentDate;
    final clean = monthStr.trim();
    if (clean.isEmpty) return false;

    // Try full 'MMMM yyyy' parsing first (e.g. "April 2026")
    try {
      final parsed = DateFormat('MMMM yyyy').parse(clean);
      if (parsed.year < now.year) return true;
      if (parsed.year == now.year && parsed.month < now.month) return true;
      return false;
    } catch (_) {}

    // Fallback: If month does not have year (e.g. "April"), resolve year from active FY
    final idx = getMonthIndex(clean);
    if (idx != -1) {
      final fullMonthName = financialYearMonths[idx];
      try {
        final parsed = DateFormat('MMMM yyyy').parse(fullMonthName);
        if (parsed.year < now.year) return true;
        if (parsed.year == now.year && parsed.month < now.month) return true;
        return false;
      } catch (_) {}

      final curMonthName = DateFormat('MMMM yyyy').format(now);
      final curIdx = getMonthIndex(curMonthName);
      return curIdx != -1 && idx < curIdx;
    }

    return false;
  }

  /// Base monthly late fine per overdue month (₹10)
  static const double lateFineRatePerMonth = 10.0;

  /// Calculates the number of calendar months [monthStr] is overdue relative to [referenceDate] (defaults to [currentDate]).
  /// If [monthStr] is current month or future, returns 0.
  /// If 1 month in the past (e.g. Sep evaluated in Oct), returns 1.
  /// If 2 months in the past (e.g. Sep evaluated in Nov), returns 2, etc.
  static int getOverdueMonths(String monthStr, [DateTime? referenceDate]) {
    final now = referenceDate ?? currentDate;
    final clean = monthStr.trim();
    if (clean.isEmpty) return 0;

    int billYear = -1;
    int billMonth = -1;

    try {
      final parsed = DateFormat('MMMM yyyy').parse(clean);
      billYear = parsed.year;
      billMonth = parsed.month;
    } catch (_) {
      final idx = getMonthIndex(clean);
      if (idx != -1) {
        final fullMonthName = financialYearMonths[idx];
        try {
          final parsed = DateFormat('MMMM yyyy').parse(fullMonthName);
          billYear = parsed.year;
          billMonth = parsed.month;
        } catch (_) {}
      }
    }

    if (billYear == -1 || billMonth == -1) return 0;

    final diff = (now.year - billYear) * 12 + (now.month - billMonth);
    return diff > 0 ? diff : 0;
  }

  /// Calculates the progressive late fine for [monthStr] relative to [referenceDate] (defaults to [currentDate]).
  /// Logic: ₹10 per month of delay.
  /// e.g. Sep evaluated in Oct -> 1 month late = ₹10
  ///      Sep evaluated in Nov -> 2 months late = ₹20
  ///      Oct evaluated in Nov -> 1 month late = ₹10
  static double calculateProgressiveLateFine(String monthStr, [DateTime? referenceDate]) {
    final overdueMonths = getOverdueMonths(monthStr, referenceDate);
    return overdueMonths * lateFineRatePerMonth;
  }

  /// Resolves the effective late fine for a bill.
  /// Late fine is strictly imposed on flat maintenance and NEVER on vehicle parking.
  /// If the bill is parking-only (or has zero base maintenance), late fine is strictly 0.0.
  /// If the bill is already PAID, returns the historically recorded fine.
  /// If UNPAID, returns the progressive fine (₹10/mo of delay), or the explicitly assessed fine if higher.
  static double getEffectiveFine(Map<String, dynamic> dueData, [DateTime? referenceDate]) {
    final bool isParkingOnly = dueData['isParkingOnlyBill'] == true ||
        (dueData.containsKey('baseMaintenance') &&
            ((dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0 &&
            (((dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0) > 0 ||
                ((dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0) > 0));
    if (isParkingOnly) {
      return 0.0;
    }

    final explicitFine = (dueData['fine'] as num?)?.toDouble() ?? (dueData['lateFee'] as num?)?.toDouble();
    final status = (dueData['status'] ?? '').toString().toUpperCase();
    final isPaid = status.startsWith('PAID') || dueData['paidAt'] != null;
    if (isPaid && explicitFine != null) {
      return explicitFine;
    }
    final month = (dueData['month'] ?? '').toString();
    final progressive = calculateProgressiveLateFine(month, referenceDate);
    if (explicitFine != null && explicitFine > progressive) {
      return explicitFine;
    }
    return progressive;
  }

  static int _voucherSeq = 0;

  /// Generates a collision-resistant monotonic voucher code for accounting entries (e.g. 'INC-2627-12345' or 'EXP-2627-12345')
  static String generateVoucherCode([String prefix = 'INC']) {
    final d = currentDate;
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final endYear = (startYear + 1) % 100;
    final fy = '${(startYear % 100).toString().padLeft(2, '0')}${endYear.toString().padLeft(2, '0')}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _voucherSeq = (_voucherSeq + 1) % 1000;
    final suffix = ((timestamp + _voucherSeq) % 90000 + 10000).toString();
    return '$prefix-$fy-$suffix';
  }

  static const List<String> meetingTypes = [
    'Annual General Meeting (AGM)',
    'Extraordinary General Meeting (EGM)',
    'Managing Committee Meeting',
    'Emergency Committee Resolution',
  ];

  // ────────────────────────────── INCOME HEADS ──────────────────────────────
  static const List<String> incomeHeads = [
    'Monthly Maintenance - Block A',
    'Monthly Maintenance - Block B',
    'Monthly Maintenance - Block C',
    'Monthly Maintenance - Block D',
    'Tower Rent',
    'CESC (Transformer Room Rent)',
    'Car Parking Fees (Two-Wheelers)',
    'Car Parking Fees (Four-Wheelers)',
    'Puja Subscriptions & Allocations',
    'Bank Interest / Dividend',
    'Other / Miscellaneous Inflow',
  ];

  static const Map<String, double> projectedIncomeYearly = {
    'Monthly Maintenance - Block A': 270000.0, // 50 flats @ ₹450 = ₹22,500/mo
    'Monthly Maintenance - Block B': 302400.0, // 60 flats @ ₹420 = ₹25,200/mo
    'Monthly Maintenance - Block C': 280800.0, // 60 flats @ ₹390 = ₹23,400/mo
    'Monthly Maintenance - Block D': 294000.0, // 50 flats @ ₹490 = ₹24,500/mo
    'Tower Rent': 242652.0, // ₹20,221/mo
    'CESC (Transformer Room Rent)': 5088.0, // ₹424/mo
    'Car Parking Fees (Two-Wheelers)': 84000.0, // 70 nos @ ₹100 = ₹7,000/mo
    'Car Parking Fees (Four-Wheelers)': 299280.0, // 58 nos @ ₹430 = ₹24,940/mo
  };

  static const Map<String, double> projectedIncomeMonthly = {
    'Monthly Maintenance - Block A': 22500.0,
    'Monthly Maintenance - Block B': 25200.0,
    'Monthly Maintenance - Block C': 23400.0,
    'Monthly Maintenance - Block D': 24500.0,
    'Tower Rent': 20221.0,
    'CESC (Transformer Room Rent)': 424.0,
    'Car Parking Fees (Two-Wheelers)': 7000.0,
    'Car Parking Fees (Four-Wheelers)': 24940.0,
  };

  // Block maintenance rate (2026-27) - Puja subscription is merged into base maintenance
  static const Map<String, Map<String, int>> blockRateBreakup = {
    'A': {'total': 450, 'maintenance': 450, 'puja': 0, 'flats': 50},
    'B': {'total': 420, 'maintenance': 420, 'puja': 0, 'flats': 60},
    'C': {'total': 390, 'maintenance': 390, 'puja': 0, 'flats': 60},
    'D': {'total': 490, 'maintenance': 490, 'puja': 0, 'flats': 50},
  };

  // Parking rates (2026-27)
  static const Map<String, int> parkingRates = {
    'Two-Wheeler': 100, // ₹100/mo (70 nos = ₹7,000/mo)
    'Four-Wheeler': 430, // ₹430/mo (58 nos = ₹24,940/mo)
  };

  // Staff Remuneration Monthly Breakdown (2026-27)
  static const Map<String, double> staffRemunerationMonthly = {
    'Electrician': 5346.0,
    'Guard 1': 4472.0,
    'Guard 2': 4472.0,
    'Sweeper 1': 3911.0,
    'Sweeper 2': 3438.0,
    'Sweeper 3': 3212.0,
    'Sweeper 4': 3212.0,
    'Medical Allowance': 875.0,
    'Leave Encashment': 875.0,
    'Puja Assistance': 2126.0,
    '2 Nos. New Security Guard': 20600.0,
  };

  // ─────────────────────────── EXPENDITURE HEADS ────────────────────────────
  // Exactly mapped to Ramkrishnapuram Residents' Welfare Association Budget 2026-27 Final
  static const List<BudgetHead> expenditureHeads = [
    BudgetHead(
      name: "Auditor's Remuneration",
      category: 'Professional & Legal',
      yearlyBudget: 8000.0,
      monthlyBudget: 667.0,
      description: "Statutory annual audit fees for society books",
    ),
    BudgetHead(
      name: 'Annual Sports + Sit & Draw',
      category: 'Events & Culture',
      yearlyBudget: 26000.0,
      monthlyBudget: 2167.0,
      description: 'Annual sports day and children painting contest',
    ),
    BudgetHead(
      name: 'Beautification',
      category: 'Campus & Garden',
      yearlyBudget: 10000.0,
      monthlyBudget: 833.0,
      description: 'Garden plants, lawn maintenance, lighting decor',
    ),
    BudgetHead(
      name: 'Bush Cleaning & Tree Trimming',
      category: 'Campus & Garden',
      yearlyBudget: 35000.0,
      monthlyBudget: 2917.0,
      description: 'Seasonal pruning, bush clearance, horticulture labour',
    ),
    BudgetHead(
      name: 'CCTV',
      category: 'Security & Safety',
      yearlyBudget: 19000.0,
      monthlyBudget: 1583.0,
      description: 'Camera maintenance, DVR/NVR, cable repairs',
    ),
    BudgetHead(
      name: 'Conveyance',
      category: 'Administrative',
      yearlyBudget: 3500.0,
      monthlyBudget: 292.0,
      description: 'Society errands, administrative local travel',
    ),
    BudgetHead(
      name: 'Electric Charges (CESC)',
      category: 'Utilities',
      yearlyBudget: 318000.0,
      monthlyBudget: 26500.0,
      description: 'Common area lighting, pump power, transformer bill',
    ),
    BudgetHead(
      name: 'Electric Equipment',
      category: 'Utilities',
      yearlyBudget: 10000.0,
      monthlyBudget: 833.0,
      description: 'LED lamps, MCBs, contactors, wiring hardware',
    ),
    BudgetHead(
      name: 'I.T. Filling Charges',
      category: 'Professional & Legal',
      yearlyBudget: 5000.0,
      monthlyBudget: 417.0,
      description: 'Income Tax return filing charges',
    ),
    BudgetHead(
      name: 'Meeting Expenses',
      category: 'Administrative',
      yearlyBudget: 20000.0,
      monthlyBudget: 1667.0,
      description: 'Annual General Meeting (AGM) and Committee sessions',
    ),
    BudgetHead(
      name: 'Office Expenses',
      category: 'Administrative',
      yearlyBudget: 3000.0,
      monthlyBudget: 250.0,
      description: 'Tea, refreshment, office upkeep',
    ),
    BudgetHead(
      name: 'Overhead Tanks Cleaning (For 3 times yearly)',
      category: 'Repairs & Maintenance',
      yearlyBudget: 15000.0,
      monthlyBudget: 1250.0,
      description: 'Three times yearly mechanised reservoir & water tank cleaning',
    ),
    BudgetHead(
      name: 'Plumbing',
      category: 'Repairs & Maintenance',
      yearlyBudget: 70000.0,
      monthlyBudget: 5833.0,
      description: 'Pipe leaks, valves, drainage repairs, contractor bills',
    ),
    BudgetHead(
      name: 'Pump Repairs & Maintenance',
      category: 'Repairs & Maintenance',
      yearlyBudget: 150000.0,
      monthlyBudget: 12500.0,
      description: 'Submersible motor rewinding, pump replacement, starters',
    ),
    BudgetHead(
      name: 'Printing & Stationery',
      category: 'Administrative',
      yearlyBudget: 10000.0,
      monthlyBudget: 833.0,
      description: 'Receipt books, registers, toner, notice prints',
    ),
    BudgetHead(
      name: 'Puja Subscription (Resti.)',
      category: 'Events & Culture',
      yearlyBudget: 237600.0,
      monthlyBudget: 19800.0,
      description: 'Puja subscription allocation (220 flats @ ₹90/month)',
    ),
    BudgetHead(
      name: 'Rabindra Nazrul Jayanti',
      category: 'Events & Culture',
      yearlyBudget: 13500.0,
      monthlyBudget: 1125.0,
      description: 'Annual cultural remembrance program',
    ),
    BudgetHead(
      name: 'Independence Day & Republic Day Celebration',
      category: 'Events & Culture',
      yearlyBudget: 3000.0,
      monthlyBudget: 250.0,
      description: 'Flag hoisting, sweets, Independence & Republic day celebrations',
    ),
    BudgetHead(
      name: 'Registration',
      category: 'Professional & Legal',
      yearlyBudget: 150.0,
      monthlyBudget: 13.0,
      description: 'Society annual statutory registration renewal fees',
    ),
    BudgetHead(
      name: 'Repair & Maintenance (Civil)',
      category: 'Repairs & Maintenance',
      yearlyBudget: 70000.0,
      monthlyBudget: 5833.0,
      description: 'Plastering, compound wall, pathway, masonry works',
    ),
    BudgetHead(
      name: 'Staff Remuneration',
      category: 'Staff & Security',
      yearlyBudget: 630468.0,
      monthlyBudget: 52539.0,
      description: 'Electrician, 2 Guards, 4 Sweepers, 2 New Guards, Allowances, Puja assistance',
    ),
    BudgetHead(
      name: 'Sundry Expenses / Misc',
      category: 'Miscellaneous',
      yearlyBudget: 5000.0,
      monthlyBudget: 417.0,
      isDocRequired: false, // EXEMPTED: Supporting document upload is optional
      description: 'Petty cash miscellaneous expenses without mandatory voucher',
    ),
    BudgetHead(
      name: 'Sweeping / Conservancy',
      category: 'Staff & Security',
      yearlyBudget: 50000.0,
      monthlyBudget: 4167.0,
      description: 'Drainage desilting, waste collection, disinfectant acids',
    ),
    BudgetHead(
      name: 'Staff Welfare (FD)',
      category: 'Reserve & Investments',
      yearlyBudget: 20000.0,
      monthlyBudget: 1667.0,
      description: 'Fixed deposit contribution for staff welfare fund',
    ),
    BudgetHead(
      name: 'Exigency Fund (FD)',
      category: 'Reserve & Investments',
      yearlyBudget: 20000.0,
      monthlyBudget: 1667.0,
      description: 'Emergency reserve fixed deposit allocation',
    ),
    BudgetHead(
      name: 'Telephone (Gate Office)',
      category: 'Utilities',
      yearlyBudget: 2340.0,
      monthlyBudget: 195.0,
      description: 'Gate intercom and telephone connection rental',
    ),
    BudgetHead(
      name: 'Fire Extinguisher',
      category: 'Security & Safety',
      yearlyBudget: 10000.0,
      monthlyBudget: 833.0,
      description: 'Gas refill, nozzle replacement, annual safety inspection',
    ),
    BudgetHead(
      name: 'Iron Ladder (Emergency)',
      category: 'Security & Safety',
      yearlyBudget: 5000.0,
      monthlyBudget: 417.0,
      description: 'Emergency iron ladder installation and maintenance',
    ),
    BudgetHead(
      name: 'Pest Control',
      category: 'Repairs & Maintenance',
      yearlyBudget: 6000.0,
      monthlyBudget: 500.0,
      description: 'Termite and pest extermination treatments across society campus',
    ),
  ];

  /// Total Approved Annual Expenditure Outlay: ₹17,75,558.0
  static double get totalAnnualBudget =>
      expenditureHeads.fold(0.0, (sum, h) => sum + h.yearlyBudget);

  /// Total Approved Monthly Expenditure Outlay: ₹1,47,965.0
  static double get totalMonthlyBudget =>
      expenditureHeads.fold(0.0, (sum, h) => sum + h.monthlyBudget);

  /// Total Projected Annual Income: ₹17,78,220.0
  static double get totalProjectedIncomeYearly =>
      projectedIncomeYearly.values.fold(0.0, (sum, v) => sum + v);

  /// Total Projected Monthly Inflow: ₹1,48,185.0
  static double get totalProjectedIncomeMonthly =>
      projectedIncomeMonthly.values.fold(0.0, (sum, v) => sum + v);

  /// Monthly Projected Surplus: ₹222 / month
  static const double monthlySurplus = 222.0;

  /// Check whether an expenditure head strictly requires a supporting document.
  /// Rule: Every payment must have a document EXCEPT 'Sundry Expenses / Misc'.
  static bool requiresSupportingDocument(String headName) {
    final head = expenditureHeads.cast<BudgetHead?>().firstWhere(
          (h) => h?.name == headName,
          orElse: () => null,
        );
    if (head != null) {
      return head.isDocRequired;
    }
    // Fallback: If contains 'misc' or 'sundry', exempt, else require.
    final lower = headName.toLowerCase();
    return !(lower.contains('misc') || lower.contains('sundry'));
  }

  /// Get budget details for a given expenditure head
  static BudgetHead? getBudgetHead(String name) {
    return expenditureHeads.cast<BudgetHead?>().firstWhere(
          (h) => h?.name == name,
          orElse: () => null,
        );
  }

  /// Available payment modes
  static const List<String> paymentModes = [
    'Bank Transfer / NEFT / IMPS',
    'UPI',
    'Cheque',
    'Cash',
    'Demand Draft',
  ];

  /// Calculate itemized maintenance breakdown for active FY strictly as per approved budget
  static FlatMaintenanceBreakdown calculateMaintenanceBreakdown({
    required String flatNumber,
    int carCount = 0,
    int bikeCount = 0,
    double fine = 0.0,
  }) {
    final clean = flatNumber.trim().toUpperCase();
    final match = RegExp(r'^([A-D])(?=[- ]|$)').firstMatch(clean);
    final String block = match != null ? match.group(1)! : 'A';

    final rateData = blockRateBreakup[block] ?? blockRateBreakup['A']!;
    final double baseMaint = (rateData['maintenance'] ?? rateData['total'] ?? 390).toDouble();
    final double pujaSub = 0.0;
    final double carCharges = carCount * (parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final double bikeCharges = bikeCount * (parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final double total = baseMaint + carCharges + bikeCharges + fine;

    return FlatMaintenanceBreakdown(
      block: block,
      flatNumber: flatNumber,
      baseMaintenance: baseMaint,
      pujaSubscription: pujaSub,
      carCount: carCount,
      carParkingCharges: carCharges,
      bikeCount: bikeCount,
      bikeParkingCharges: bikeCharges,
      fine: fine,
      totalMonthlyDue: total,
    );
  }

  /// Calculate maintenance breakdown from user profile document data
  static FlatMaintenanceBreakdown calculateFromUserData(Map<String, dynamic> userData, {double fine = 0.0}) {
    final flatNumber = (userData['flatNumber'] ?? 'A-101').toString();
    final block = (userData['block'] ?? '').toString().trim().toUpperCase();
    
    // Count active approved cars (capped at 1 per society rule)
    int carCount = 0;
    if (userData['isCarOwner'] == true && (userData['carReg']?.toString().trim().isNotEmpty ?? false)) {
      carCount = 1;
    }

    // Count active approved bikes (max 2 per society rule)
    int bikeCount = 0;
    if (userData['isBikeOwner'] == true && (userData['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
      bikeCount++;
    }
    if (userData['hasBike2'] == true && (userData['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
      bikeCount++;
    }

    // If block is specified directly in user document, use it
    final effectiveFlat = (block.isNotEmpty && !flatNumber.toUpperCase().startsWith(block))
        ? '$block-$flatNumber'
        : flatNumber;

    return calculateMaintenanceBreakdown(
      flatNumber: effectiveFlat,
      carCount: carCount,
      bikeCount: bikeCount,
      fine: fine,
    );
  }
}

/// Itemized Flat Maintenance Breakdown
class FlatMaintenanceBreakdown {
  final String block;
  final String flatNumber;
  final double baseMaintenance;
  final double pujaSubscription;
  final int carCount;
  final double carParkingCharges;
  final int bikeCount;
  final double bikeParkingCharges;
  final double fine;
  final double totalMonthlyDue;

  const FlatMaintenanceBreakdown({
    required this.block,
    required this.flatNumber,
    required this.baseMaintenance,
    required this.pujaSubscription,
    required this.carCount,
    required this.carParkingCharges,
    required this.bikeCount,
    required this.bikeParkingCharges,
    this.fine = 0.0,
    required this.totalMonthlyDue,
  });

  Map<String, dynamic> toMap() => {
    'block': block,
    'flatNumber': flatNumber,
    'baseMaintenance': baseMaintenance,
    'pujaSubscription': pujaSubscription,
    'carCount': carCount,
    'carParkingCharges': carParkingCharges,
    'bikeCount': bikeCount,
    'bikeParkingCharges': bikeParkingCharges,
    if (fine > 0) 'fine': fine,
    'totalMonthlyDue': totalMonthlyDue,
    'financialYear': AccountingConfig.currentFinancialYear,
  };
}
