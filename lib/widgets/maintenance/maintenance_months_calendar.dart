import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../models/accounting_heads.dart';
import '../../utils/app_formatters.dart';
import '../receipt_preview_dialog.dart';

enum MonthPaymentStatus {
  paidBoth,            // Maintenance + Vehicle parking paid
  paidMaintenanceOnly, // Maintenance paid, parking excluded / no vehicle
  paidVehicleOnly,     // Only vehicle parking paid
  pendingApproval,     // Submitted payment awaiting admin verification
  unpaid,              // Bill issued, unpaid / overdue
  overdueUnbilled,     // Past month with no bill issued
  upcoming,            // Future/current month available for advance payment
}

class MonthSummaryData {
  final String month;
  final MonthPaymentStatus status;
  final double totalAmount;
  final double baseMaintenance;
  final double carParkingCharges;
  final double bikeParkingCharges;
  final double fine;
  final int carCount;
  final int bikeCount;
  final bool hasVehicles;
  final List<Map<String, dynamic>> duesData;
  final String? receiptNumber;
  final String? paidDateStr;
  final String? paymentMode;
  final String? uniqueId;
  final String? primaryDocId;

  const MonthSummaryData({
    required this.month,
    required this.status,
    this.totalAmount = 0.0,
    this.baseMaintenance = 0.0,
    this.carParkingCharges = 0.0,
    this.bikeParkingCharges = 0.0,
    this.fine = 0.0,
    this.carCount = 0,
    this.bikeCount = 0,
    this.hasVehicles = false,
    this.duesData = const [],
    this.receiptNumber,
    this.paidDateStr,
    this.paymentMode,
    this.uniqueId,
    this.primaryDocId,
  });
}

class MaintenanceMonthsCalendar extends StatefulWidget {
  final List<QueryDocumentSnapshot> duesDocs;
  final FlatMaintenanceBreakdown breakdown;
  final Map<String, dynamic> userData;
  final String flatDisplay;
  final void Function(String month, String? dueId)? onPayMonth;

  const MaintenanceMonthsCalendar({
    super.key,
    required this.duesDocs,
    required this.breakdown,
    required this.userData,
    required this.flatDisplay,
    this.onPayMonth,
  });

  @override
  State<MaintenanceMonthsCalendar> createState() => _MaintenanceMonthsCalendarState();
}

class _MaintenanceMonthsCalendarState extends State<MaintenanceMonthsCalendar> {
  final _currencyFmt = AppFormatters.currencyFormat;
  bool _isExpanded = true;

  List<MonthSummaryData> _computeMonthsSummary() {
    final months = AccountingConfig.financialYearMonths;
    final bool residentHasVehicles = (widget.breakdown.carCount > 0 || widget.breakdown.bikeCount > 0);

    return months.map((m) {
      final matchingDocs = widget.duesDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final docMonth = (data['month'] ?? '').toString().trim().toLowerCase();
        return docMonth == m.trim().toLowerCase();
      }).toList();

      if (matchingDocs.isNotEmpty) {
        final paidDocs = matchingDocs.where((doc) {
          final st = (doc.data() as Map<String, dynamic>)['status']?.toString().toUpperCase() ?? '';
          return st.startsWith('PAID') || st == 'PAID_VERIFIED' || st == 'PAID_ONLINE' || st == 'PAID_OFFLINE_VERIFIED';
        }).toList();

        final pendingDocs = matchingDocs.where((doc) {
          final st = (doc.data() as Map<String, dynamic>)['status']?.toString().toUpperCase() ?? '';
          return st == 'PAYMENT_PENDING_APPROVAL' || st == 'PAID_OFFLINE_PENDING';
        }).toList();

        final unpaidDocs = matchingDocs.where((doc) {
          final st = (doc.data() as Map<String, dynamic>)['status']?.toString().toUpperCase() ?? '';
          return st == 'UNPAID';
        }).toList();

        if (paidDocs.isNotEmpty) {
          double totalBase = 0.0;
          double totalCar = 0.0;
          double totalBike = 0.0;
          double totalFine = 0.0;
          double totalAmt = 0.0;
          String? receiptNo;
          String? paidDate;
          String? pMode;
          String? uId;

          final allDuesData = <Map<String, dynamic>>[];

          for (final doc in paidDocs) {
            final d = doc.data() as Map<String, dynamic>;
            allDuesData.add(d);
            totalBase += (d['baseMaintenance'] as num?)?.toDouble() ?? 0.0;
            totalCar += (d['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
            totalBike += (d['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
            totalFine += (d['fine'] as num?)?.toDouble() ?? 0.0;
            totalAmt += (d['amount'] as num?)?.toDouble() ?? 0.0;

            if (receiptNo == null && d['receiptNumber'] != null) {
              receiptNo = d['receiptNumber'].toString();
            }
            if (paidDate == null && d['paidAt'] != null) {
              final val = d['paidAt'];
              if (val is Timestamp) {
                paidDate = DateFormat('dd MMM yyyy').format(val.toDate());
              } else {
                paidDate = val.toString();
              }
            }
            pMode ??= d['paymentMode']?.toString();
            uId ??= d['uniqueId']?.toString() ?? d['utrNumber']?.toString();
          }

          final bool hasPaidVehicleCharges = (totalCar + totalBike) > 0;
          MonthPaymentStatus status;

          if (residentHasVehicles) {
            if (hasPaidVehicleCharges && totalBase > 0) {
              status = MonthPaymentStatus.paidBoth;
            } else if (totalBase > 0 && !hasPaidVehicleCharges) {
              status = MonthPaymentStatus.paidMaintenanceOnly;
            } else if (totalBase == 0 && hasPaidVehicleCharges) {
              status = MonthPaymentStatus.paidVehicleOnly;
            } else {
              status = MonthPaymentStatus.paidBoth;
            }
          } else {
            // Resident owns no vehicles: Paying maintenance means maintenance is fully covered
            status = MonthPaymentStatus.paidMaintenanceOnly;
          }

          return MonthSummaryData(
            month: m,
            status: status,
            totalAmount: totalAmt > 0 ? totalAmt : (totalBase + totalCar + totalBike + totalFine),
            baseMaintenance: totalBase,
            carParkingCharges: totalCar,
            bikeParkingCharges: totalBike,
            fine: totalFine,
            carCount: widget.breakdown.carCount,
            bikeCount: widget.breakdown.bikeCount,
            hasVehicles: residentHasVehicles,
            duesData: allDuesData,
            receiptNumber: receiptNo,
            paidDateStr: paidDate,
            paymentMode: pMode,
            uniqueId: uId,
            primaryDocId: paidDocs.first.id,
          );
        } else if (pendingDocs.isNotEmpty) {
          final first = pendingDocs.first;
          final d = first.data() as Map<String, dynamic>;
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          return MonthSummaryData(
            month: m,
            status: MonthPaymentStatus.pendingApproval,
            totalAmount: amt,
            baseMaintenance: (d['baseMaintenance'] as num?)?.toDouble() ?? 0.0,
            carParkingCharges: (d['carParkingCharges'] as num?)?.toDouble() ?? 0.0,
            bikeParkingCharges: (d['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0,
            fine: (d['fine'] as num?)?.toDouble() ?? 0.0,
            hasVehicles: residentHasVehicles,
            duesData: [d],
            paymentMode: d['paymentMode']?.toString(),
            uniqueId: d['uniqueId']?.toString() ?? d['utrNumber']?.toString(),
            primaryDocId: first.id,
          );
        } else if (unpaidDocs.isNotEmpty) {
          final first = unpaidDocs.first;
          final d = first.data() as Map<String, dynamic>;
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          return MonthSummaryData(
            month: m,
            status: MonthPaymentStatus.unpaid,
            totalAmount: amt > 0 ? amt : widget.breakdown.totalMonthlyDue,
            baseMaintenance: (d['baseMaintenance'] as num?)?.toDouble() ?? widget.breakdown.baseMaintenance,
            carParkingCharges: (d['carParkingCharges'] as num?)?.toDouble() ?? widget.breakdown.carParkingCharges,
            bikeParkingCharges: (d['bikeParkingCharges'] as num?)?.toDouble() ?? widget.breakdown.bikeParkingCharges,
            fine: AccountingConfig.getEffectiveFine(d),
            hasVehicles: residentHasVehicles,
            duesData: [d],
            primaryDocId: first.id,
          );
        }
      }

      // No document found in Firestore for this month
      if (AccountingConfig.isMonthPast(m)) {
        return MonthSummaryData(
          month: m,
          status: MonthPaymentStatus.overdueUnbilled,
          totalAmount: widget.breakdown.totalMonthlyDue,
          baseMaintenance: widget.breakdown.baseMaintenance,
          carParkingCharges: widget.breakdown.carParkingCharges,
          bikeParkingCharges: widget.breakdown.bikeParkingCharges,
          hasVehicles: residentHasVehicles,
        );
      } else {
        return MonthSummaryData(
          month: m,
          status: MonthPaymentStatus.upcoming,
          totalAmount: widget.breakdown.totalMonthlyDue,
          baseMaintenance: widget.breakdown.baseMaintenance,
          carParkingCharges: widget.breakdown.carParkingCharges,
          bikeParkingCharges: widget.breakdown.bikeParkingCharges,
          hasVehicles: residentHasVehicles,
        );
      }
    }).toList();
  }

  void _showMonthDetailsSheet(BuildContext context, MonthSummaryData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MonthDetailsBottomSheet(
        data: data,
        flatDisplay: widget.flatDisplay,
        breakdown: widget.breakdown,
        currencyFmt: _currencyFmt,
        onPayPressed: () {
          Navigator.pop(ctx);
          if (widget.onPayMonth != null) {
            widget.onPayMonth!(data.month, data.primaryDocId);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _computeMonthsSummary();

    final bothCount = summaries.where((s) => s.status == MonthPaymentStatus.paidBoth).length;
    final maintOnlyCount = summaries.where((s) => s.status == MonthPaymentStatus.paidMaintenanceOnly).length;
    final pendingCount = summaries.where((s) => s.status == MonthPaymentStatus.pendingApproval).length;
    final unpaidCount = summaries.where((s) => s.status == MonthPaymentStatus.unpaid || s.status == MonthPaymentStatus.overdueUnbilled).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: const Text(
                              'Payment Calendar by Month',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.slate900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              'FY ${AccountingConfig.currentFinancialYear}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Detailed status of maintenance & vehicle parking dues',
                        style: TextStyle(fontSize: 12, color: AppColors.slate500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.slate600,
                  ),
                  tooltip: _isExpanded ? 'Collapse' : 'Expand',
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
              ],
            ),
          ),

          // Summary Stats Pills
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatPill(
                  icon: Icons.check_circle_rounded,
                  label: '$bothCount Paid (Maint + Vehicle)',
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFF10B981),
                  textColor: const Color(0xFF047857),
                ),
                _buildStatPill(
                  icon: Icons.apartment_rounded,
                  label: '$maintOnlyCount Paid (Maintenance Only)',
                  bgColor: const Color(0xFFEFF6FF),
                  borderColor: const Color(0xFF3B82F6),
                  textColor: const Color(0xFF1D4ED8),
                ),
                if (pendingCount > 0)
                  _buildStatPill(
                    icon: Icons.schedule_rounded,
                    label: '$pendingCount Under Approval',
                    bgColor: const Color(0xFFFFFBEB),
                    borderColor: const Color(0xFFF59E0B),
                    textColor: const Color(0xFFB45309),
                  ),
                if (unpaidCount > 0)
                  _buildStatPill(
                    icon: Icons.error_outline_rounded,
                    label: '$unpaidCount Due / Unpaid',
                    bgColor: const Color(0xFFFEF2F2),
                    borderColor: const Color(0xFFEF4444),
                    textColor: const Color(0xFFB91C1C),
                  ),
              ],
            ),
          ),

          if (_isExpanded) ...[
            const Divider(height: 1),
            // Months Grid
            Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 4;
                  if (constraints.maxWidth < 460) {
                    crossAxisCount = 2;
                  } else if (constraints.maxWidth < 720) {
                    crossAxisCount = 3;
                  }

                  final double aspectRatio = constraints.maxWidth < 380
                      ? 1.15
                      : (constraints.maxWidth < 480
                          ? 1.22
                          : (constraints.maxWidth < 720 ? 1.35 : 1.45));

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: aspectRatio,
                    ),
                    itemCount: summaries.length,
                    itemBuilder: (context, index) {
                      final item = summaries[index];
                      return _MonthGridTile(
                        data: item,
                        currencyFmt: _currencyFmt,
                        onTap: () => _showMonthDetailsSheet(context, item),
                      );
                    },
                  );
                },
              ),
            ),

            // Legend Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Legend:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.slate700)),
                  _buildLegendItem(const Color(0xFF10B981), 'Maint + Vehicle'),
                  _buildLegendItem(const Color(0xFF3B82F6), 'Maintenance Only'),
                  _buildLegendItem(const Color(0xFFF59E0B), 'Pending Approval'),
                  _buildLegendItem(const Color(0xFFEF4444), 'Unpaid / Overdue'),
                  _buildLegendItem(const Color(0xFF94A3B8), 'Upcoming'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.slate600, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _MonthGridTile extends StatelessWidget {
  final MonthSummaryData data;
  final NumberFormat currencyFmt;
  final VoidCallback onTap;

  const _MonthGridTile({
    required this.data,
    required this.currencyFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color cardBg;
    Color borderCol;
    Color titleCol;
    Color badgeBg;
    Color badgeTextCol;
    String badgeText;
    IconData statusIcon;

    switch (data.status) {
      case MonthPaymentStatus.paidBoth:
        cardBg = const Color(0xFFF0FDF4);
        borderCol = const Color(0xFF86EFAC);
        titleCol = const Color(0xFF166534);
        badgeBg = const Color(0xFFDCFCE7);
        badgeTextCol = const Color(0xFF15803D);
        badgeText = 'Maint + Vehicle';
        statusIcon = Icons.directions_car_rounded;
        break;

      case MonthPaymentStatus.paidMaintenanceOnly:
        cardBg = const Color(0xFFF0F9FF);
        borderCol = const Color(0xFFBAE6FD);
        titleCol = const Color(0xFF075985);
        badgeBg = const Color(0xFFE0F2FE);
        badgeTextCol = const Color(0xFF0369A1);
        badgeText = data.hasVehicles ? 'Maint Only' : 'Maintenance Paid';
        statusIcon = Icons.apartment_rounded;
        break;

      case MonthPaymentStatus.paidVehicleOnly:
        cardBg = const Color(0xFFFAF5FF);
        borderCol = const Color(0xFFE9D5FF);
        titleCol = const Color(0xFF6B21A8);
        badgeBg = const Color(0xFFF3E8FF);
        badgeTextCol = const Color(0xFF7E22CE);
        badgeText = 'Vehicle Only';
        statusIcon = Icons.directions_car_filled_rounded;
        break;

      case MonthPaymentStatus.pendingApproval:
        cardBg = const Color(0xFFFFFBEB);
        borderCol = const Color(0xFFFDE68A);
        titleCol = const Color(0xFF92400E);
        badgeBg = const Color(0xFFFEF3C7);
        badgeTextCol = const Color(0xFFB45309);
        badgeText = 'Approval Pending';
        statusIcon = Icons.schedule_rounded;
        break;

      case MonthPaymentStatus.unpaid:
      case MonthPaymentStatus.overdueUnbilled:
        cardBg = const Color(0xFFFEF2F2);
        borderCol = const Color(0xFFFECACA);
        titleCol = const Color(0xFF991B1B);
        badgeBg = const Color(0xFFFEE2E2);
        badgeTextCol = const Color(0xFFDC2626);
        badgeText = data.status == MonthPaymentStatus.overdueUnbilled ? 'Overdue' : 'Unpaid';
        statusIcon = Icons.error_outline_rounded;
        break;

      case MonthPaymentStatus.upcoming:
        cardBg = const Color(0xFFF8FAFC);
        borderCol = const Color(0xFFE2E8F0);
        titleCol = const Color(0xFF475569);
        badgeBg = const Color(0xFFF1F5F9);
        badgeTextCol = const Color(0xFF64748B);
        badgeText = 'Upcoming';
        statusIcon = Icons.event_available_rounded;
        break;
    }

    final parts = data.month.split(' ');
    final monthAbbr = parts.first.toUpperCase();
    final yearStr = parts.length > 1 ? parts.last : '';

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: borderCol.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$monthAbbr${yearStr.isNotEmpty ? " '${yearStr.substring(yearStr.length - 2)}" : ""}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: titleCol,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(statusIcon, size: 14, color: titleCol),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeTextCol,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      currencyFmt.format(data.totalAmount),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: titleCol,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.black26),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthDetailsBottomSheet extends StatelessWidget {
  final MonthSummaryData data;
  final String flatDisplay;
  final FlatMaintenanceBreakdown breakdown;
  final NumberFormat currencyFmt;
  final VoidCallback onPayPressed;

  const _MonthDetailsBottomSheet({
    required this.data,
    required this.flatDisplay,
    required this.breakdown,
    required this.currencyFmt,
    required this.onPayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaid = data.status == MonthPaymentStatus.paidBoth ||
        data.status == MonthPaymentStatus.paidMaintenanceOnly ||
        data.status == MonthPaymentStatus.paidVehicleOnly;
    final bool isUnpaid = data.status == MonthPaymentStatus.unpaid ||
        data.status == MonthPaymentStatus.overdueUnbilled;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sheet Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.month,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.slate900),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Flat $flatDisplay (Block ${breakdown.block})',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(data.status),
            ],
          ),

          const SizedBox(height: 18),

          // Itemized Charges Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Itemized Bill Breakdown',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate800),
                ),
                const SizedBox(height: 10),
                _buildBreakdownRow(
                  label: 'Society Flat Maintenance',
                  amount: data.baseMaintenance > 0 ? data.baseMaintenance : breakdown.baseMaintenance,
                  isCovered: isPaid ? data.baseMaintenance > 0 : null,
                ),
                if (data.carParkingCharges > 0 || breakdown.carCount > 0) ...[
                  const SizedBox(height: 6),
                  _buildBreakdownRow(
                    label: '4-Wheeler Parking (${breakdown.carCount} Car @ ₹430)',
                    amount: data.carParkingCharges > 0 ? data.carParkingCharges : breakdown.carParkingCharges,
                    isCovered: isPaid ? data.carParkingCharges > 0 : null,
                  ),
                ],
                if (data.bikeParkingCharges > 0 || breakdown.bikeCount > 0) ...[
                  const SizedBox(height: 6),
                  _buildBreakdownRow(
                    label: '2-Wheeler Parking (${breakdown.bikeCount} Bike @ ₹100)',
                    amount: data.bikeParkingCharges > 0 ? data.bikeParkingCharges : breakdown.bikeParkingCharges,
                    isCovered: isPaid ? data.bikeParkingCharges > 0 : null,
                  ),
                ],
                if (data.fine > 0) ...[
                  const SizedBox(height: 6),
                  _buildBreakdownRow(
                    label: 'Late Fine / Delay Assessment',
                    amount: data.fine,
                    isFine: true,
                  ),
                ],
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900)),
                    Text(
                      currencyFmt.format(data.totalAmount > 0 ? data.totalAmount : breakdown.totalMonthlyDue),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Payment Info if Paid or Pending
          if (isPaid || data.status == MonthPaymentStatus.pendingApproval) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPaid ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isPaid ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                ),
              ),
              child: Column(
                children: [
                  if (data.paymentMode != null)
                    _buildInfoRow('Payment Mode:', data.paymentMode!),
                  if (data.uniqueId != null)
                    _buildInfoRow('Reference / UTR:', data.uniqueId!),
                  if (data.paidDateStr != null)
                    _buildInfoRow('Payment Date:', data.paidDateStr!),
                  if (data.receiptNumber != null)
                    _buildInfoRow('Receipt No:', data.receiptNumber!),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              if (isPaid && data.duesData.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('View Receipt'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      final docData = data.duesData.first;
                      ReceiptPreviewDialog.show(
                        context: context,
                        dueData: docData,
                        receiptNumber: data.receiptNumber ?? 'RCPT-${data.month}',
                        dateStr: data.paidDateStr,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (isUnpaid) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment_rounded, size: 18),
                    label: const Text('Pay Maintenance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onPayPressed,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (data.status == MonthPaymentStatus.upcoming) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Pay in Advance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onPayPressed,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required String label,
    required double amount,
    bool? isCovered,
    bool isFine = false,
  }) {
    Color? textColor;
    String badge = '';
    if (isCovered == true) {
      textColor = const Color(0xFF047857);
      badge = ' [PAID]';
    } else if (isCovered == false) {
      textColor = const Color(0xFFB45309);
      badge = ' [EXCLUDED]';
    } else if (isFine) {
      textColor = const Color(0xFFDC2626);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            '$label$badge',
            style: TextStyle(
              fontSize: 12.5,
              color: textColor ?? AppColors.slate700,
              fontWeight: isCovered == true ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          currencyFmt.format(amount),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: textColor ?? AppColors.slate800,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slate600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(MonthPaymentStatus status) {
    Color bg;
    Color textCol;
    String text;

    switch (status) {
      case MonthPaymentStatus.paidBoth:
        bg = const Color(0xFFDCFCE7);
        textCol = const Color(0xFF15803D);
        text = 'Maintenance + Vehicle Paid';
        break;
      case MonthPaymentStatus.paidMaintenanceOnly:
        bg = const Color(0xFFE0F2FE);
        textCol = const Color(0xFF0369A1);
        text = 'Maintenance Only Paid';
        break;
      case MonthPaymentStatus.paidVehicleOnly:
        bg = const Color(0xFFF3E8FF);
        textCol = const Color(0xFF7E22CE);
        text = 'Vehicle Only Paid';
        break;
      case MonthPaymentStatus.pendingApproval:
        bg = const Color(0xFFFEF3C7);
        textCol = const Color(0xFFB45309);
        text = 'Under Admin Verification';
        break;
      case MonthPaymentStatus.unpaid:
      case MonthPaymentStatus.overdueUnbilled:
        bg = const Color(0xFFFEE2E2);
        textCol = const Color(0xFFDC2626);
        text = 'Unpaid / Due';
        break;
      case MonthPaymentStatus.upcoming:
        bg = const Color(0xFFF1F5F9);
        textCol = const Color(0xFF64748B);
        text = 'Upcoming Advance';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textCol),
      ),
    );
  }
}
