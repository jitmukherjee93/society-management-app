// Ramkrishnapuram Residents' Welfare Association
// Official Budget 2026-27 Accounting Heads and Configuration
// Updated strictly as per "Updated RKP Budget.pdf"

class BudgetHead {
  final String name;
  final String category;
  final double yearlyBudget;
  final double monthlyBudget;
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
    required this.monthlyBudget,
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
  });

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
  static const String currentFinancialYear = '2026-27';

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

  // Block maintenance and puja rate break-up (2026-27)
  static const Map<String, Map<String, int>> blockRateBreakup = {
    'A': {'total': 450, 'maintenance': 360, 'puja': 90, 'flats': 50},
    'B': {'total': 420, 'maintenance': 330, 'puja': 90, 'flats': 60},
    'C': {'total': 390, 'maintenance': 300, 'puja': 90, 'flats': 60},
    'D': {'total': 490, 'maintenance': 400, 'puja': 90, 'flats': 50},
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
  // Exactly mapped to Ramkrishnapuram Welfare Association Budget 2026-27 Final
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

  /// Calculate itemized maintenance breakdown for FY 2026-27 strictly as per approved budget
  static FlatMaintenanceBreakdown calculateMaintenanceBreakdown({
    required String flatNumber,
    int carCount = 0,
    int bikeCount = 0,
  }) {
    final clean = flatNumber.trim().toUpperCase();
    String block = 'A';
    if (clean.startsWith('B') || clean.contains('B-') || clean.contains('B ')) {
      block = 'B';
    } else if (clean.startsWith('C') || clean.contains('C-') || clean.contains('C ')) {
      block = 'C';
    } else if (clean.startsWith('D') || clean.contains('D-') || clean.contains('D ')) {
      block = 'D';
    } else if (clean.startsWith('A') || clean.contains('A-') || clean.contains('A ')) {
      block = 'A';
    }

    final rateData = blockRateBreakup[block] ?? blockRateBreakup['A']!;
    final double baseMaint = (rateData['maintenance'] ?? 360).toDouble();
    final double pujaSub = (rateData['puja'] ?? 90).toDouble();
    final double carCharges = carCount * (parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final double bikeCharges = bikeCount * (parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final double total = baseMaint + pujaSub + carCharges + bikeCharges;

    return FlatMaintenanceBreakdown(
      block: block,
      flatNumber: flatNumber,
      baseMaintenance: baseMaint,
      pujaSubscription: pujaSub,
      carCount: carCount,
      carParkingCharges: carCharges,
      bikeCount: bikeCount,
      bikeParkingCharges: bikeCharges,
      totalMonthlyDue: total,
    );
  }

  /// Calculate maintenance breakdown from user profile document data
  static FlatMaintenanceBreakdown calculateFromUserData(Map<String, dynamic> userData) {
    final flatNumber = (userData['flatNumber'] ?? 'A-101').toString();
    final block = (userData['block'] ?? '').toString().trim().toUpperCase();
    
    // Count active approved cars
    int carCount = 0;
    if (userData['isCarOwner'] == true && (userData['carReg']?.toString().trim().isNotEmpty ?? false)) {
      carCount = 1;
    }

    // Count active approved bikes
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
    );
  }
}

/// Itemized Flat Maintenance Breakdown for FY 2026-27
class FlatMaintenanceBreakdown {
  final String block;
  final String flatNumber;
  final double baseMaintenance;
  final double pujaSubscription;
  final int carCount;
  final double carParkingCharges;
  final int bikeCount;
  final double bikeParkingCharges;
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
    'totalMonthlyDue': totalMonthlyDue,
    'financialYear': AccountingConfig.currentFinancialYear,
  };
}
