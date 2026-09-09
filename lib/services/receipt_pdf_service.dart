import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/number_to_words.dart';

class ReceiptPdfService {
  static const List<String> _allMonths = [
    'APRIL', 'MAY', 'JUNE', 'JULY', 'AUG.', 'SEPT.',
    'OCT.', 'NOV.', 'DEC.', 'JAN.', 'FEB.', 'MAR.'
  ];

  static Future<Uint8List> generateReceiptPdf({
    PdfPageFormat? pageFormat,
    required String receiptNumber,
    required DateTime date,
    required String residentName,
    required String block,
    required String flatNumber,
    required String billingMonth,
    required String financialYear,
    required double baseMaintenance,
    required double carParkingCharges,
    required double bikeParkingCharges,
    required double pujaSubscription,
    required double totalAmount,
    required String vehicleReg,
    required String paymentMode,
    required String referenceNumber,
    String? bankName,
  }) async {
    final pdf = pw.Document();

    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    final amountInWords = NumberToWords.convert(totalAmount);

    // Normalize month name to identify which pill to highlight in the 12-month grid
    final upperMonth = billingMonth.toUpperCase();
    String activeMonthCode = '';
    if (upperMonth.contains('APR')) {
      activeMonthCode = 'APRIL';
    } else if (upperMonth.contains('MAY')) {
      activeMonthCode = 'MAY';
    } else if (upperMonth.contains('JUN')) {
      activeMonthCode = 'JUNE';
    } else if (upperMonth.contains('JUL')) {
      activeMonthCode = 'JULY';
    } else if (upperMonth.contains('AUG')) {
      activeMonthCode = 'AUG.';
    } else if (upperMonth.contains('SEP')) {
      activeMonthCode = 'SEPT.';
    } else if (upperMonth.contains('OCT')) {
      activeMonthCode = 'OCT.';
    } else if (upperMonth.contains('NOV')) {
      activeMonthCode = 'NOV.';
    } else if (upperMonth.contains('DEC')) {
      activeMonthCode = 'DEC.';
    } else if (upperMonth.contains('JAN')) {
      activeMonthCode = 'JAN.';
    } else if (upperMonth.contains('FEB')) {
      activeMonthCode = 'FEB.';
    } else if (upperMonth.contains('MAR')) {
      activeMonthCode = 'MAR.';
    }

    final totalParkingCharges = carParkingCharges + bikeParkingCharges;

    // Default to clean A4 or format provided by printer
    final targetFormat = pageFormat ?? PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: targetFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // 1. Header: RECEIPT
                pw.Center(
                  child: pw.Text(
                    'RECEIPT',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),

                // 2. Heavy Double/Thick Box: RAMKRISHNAPURAM RESIDENTS' WELFARE ASSOCIATION
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.8),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      "RAMKRISHNAPURAM RESIDENTS' WELFARE ASSOCIATION",
                      style: pw.TextStyle(
                        fontSize: 13.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),

                // 3. Address
                pw.Center(
                  child: pw.Text(
                    '156/1, MAHARAJA NANDA KUMAR ROAD (S)\nBARANAGAR, KOLKATA - 700 036',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      lineSpacing: 1.2,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),

                // 4. Receipt No. & Date
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.black, width: 1.2),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('No.  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.Text(receiptNumber, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        ],
                      ),
                    ),
                    pw.Text(
                      'Dated  $dateStr',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),

                // 5. Received with thanks from Sri / Smt.
                pw.Row(
                  children: [
                    pw.Text(
                      'Received with thanks from Sri / Smt. ',
                      style: const pw.TextStyle(fontSize: 9.5),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                        ),
                        padding: const pw.EdgeInsets.only(bottom: 1, left: 4),
                        child: pw.Text(
                          residentName.isNotEmpty ? residentName : 'Flat Occupant / Member',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),

                // 6. Block & Flat No.
                pw.Row(
                  children: [
                    pw.Text('Block  ', style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Container(
                      width: 90,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                      ),
                      padding: const pw.EdgeInsets.only(bottom: 1, left: 4),
                      child: pw.Text(
                        block.isNotEmpty ? block : (flatNumber.contains('-') ? flatNumber.split('-').first : 'A'),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                      ),
                    ),
                    pw.Text('  Flat No.  ', style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                        ),
                        padding: const pw.EdgeInsets.only(bottom: 1, left: 4),
                        child: pw.Text(
                          flatNumber,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                        ),
                      ),
                    ),
                    pw.Text('  as follows :', style: const pw.TextStyle(fontSize: 9.5)),
                  ],
                ),
                pw.SizedBox(height: 6),

                // 7. Middle Core: Left Rates & Breakdown + Right Compact Locked Table
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // LEFT & CENTER AREA
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Rates + Month Matrix Row
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              // Left Rates per month
                              pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'Rate Per Month',
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Maint. :  Rs. ${baseMaintenance.toStringAsFixed(0)}',
                                    style: const pw.TextStyle(fontSize: 8.5),
                                  ),
                                  if (carParkingCharges > 0) ...[
                                    pw.SizedBox(height: 2),
                                    pw.Text(
                                      'Car Park : Rs. ${carParkingCharges.toStringAsFixed(0)}',
                                      style: const pw.TextStyle(fontSize: 8.5),
                                    ),
                                  ],
                                  if (bikeParkingCharges > 0) ...[
                                    pw.SizedBox(height: 2),
                                    pw.Text(
                                      'Bike Park : Rs. ${bikeParkingCharges.toStringAsFixed(0)}',
                                      style: const pw.TextStyle(fontSize: 8.5),
                                    ),
                                  ],
                                ],
                              ),
                              pw.SizedBox(width: 12),

                              // Month Matrix Pill Box
                              pw.Expanded(
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                                  children: [
                                    pw.Text(
                                      'Maintenance Charge for the month of :',
                                      style: const pw.TextStyle(fontSize: 8.5),
                                    ),
                                    pw.SizedBox(height: 3),
                                    // Row 1: Apr to Sept
                                    pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: _allMonths.sublist(0, 6).map((m) {
                                        final isSelected = (m == activeMonthCode);
                                        return _buildMonthPill(m, isSelected);
                                      }).toList(),
                                    ),
                                    pw.SizedBox(height: 2),
                                    // Row 2: Oct to Mar
                                    pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: [
                                        ..._allMonths.sublist(6, 12).map((m) {
                                          final isSelected = (m == activeMonthCode);
                                          return _buildMonthPill(m, isSelected);
                                        }),
                                        pw.SizedBox(width: 4),
                                        pw.Text(
                                          'YEAR: $financialYear',
                                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (totalParkingCharges > 0) ...[
                            pw.SizedBox(height: 6),

                            // Car / Bike Parking Charge for month line
                            pw.Row(
                              children: [
                                pw.Text(
                                  (carParkingCharges > 0 && bikeParkingCharges > 0)
                                      ? 'Car & Two-Wheeler Parking Charge for the month of '
                                      : (bikeParkingCharges > 0 && carParkingCharges <= 0)
                                          ? 'Two-Wheeler Parking Charge for the month of '
                                          : 'Car Parking Charge for the month of ',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                                pw.Expanded(
                                  child: pw.Container(
                                    decoration: const pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                    ),
                                    padding: const pw.EdgeInsets.only(left: 4),
                                    child: pw.Text(
                                      billingMonth,
                                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 4),

                            // T.W / F.W No. & Rs.
                            pw.Row(
                              children: [
                                pw.Text('T.W/F.W. No. ', style: const pw.TextStyle(fontSize: 8.5)),
                                pw.Expanded(
                                  flex: 6,
                                  child: pw.Container(
                                    decoration: const pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                    ),
                                    padding: const pw.EdgeInsets.only(left: 4),
                                    child: pw.Text(
                                      vehicleReg.isNotEmpty ? vehicleReg : '—',
                                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                    ),
                                  ),
                                ),
                                pw.Text('  Rs. ', style: const pw.TextStyle(fontSize: 8.5)),
                                pw.Expanded(
                                  flex: 3,
                                  child: pw.Container(
                                    decoration: const pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                    ),
                                    padding: const pw.EdgeInsets.only(left: 4),
                                    child: pw.Text(
                                      totalParkingCharges.toStringAsFixed(2),
                                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          pw.SizedBox(height: 4),

                          // Cash / Cheque / UTR No. line
                          pw.Row(
                            children: [
                              pw.Text('Mode / Ref No. ', style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Expanded(
                                flex: 5,
                                child: pw.Container(
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                  ),
                                  padding: const pw.EdgeInsets.only(left: 4),
                                  child: pw.Text(
                                    referenceNumber.isNotEmpty ? referenceNumber : paymentMode,
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                    overflow: pw.TextOverflow.clip,
                                  ),
                                ),
                              ),
                              pw.Text('  Date ', style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Container(
                                width: 65,
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                ),
                                padding: const pw.EdgeInsets.only(left: 2),
                                child: pw.Text(dateStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                              ),
                              pw.Text('  Bank ', style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Expanded(
                                flex: 3,
                                child: pw.Container(
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                  ),
                                  padding: const pw.EdgeInsets.only(left: 2),
                                  child: pw.Text(
                                    bankName ?? (paymentMode.toUpperCase().contains('ONLINE') ? 'Online UPI/NEFT' : paymentMode),
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4),

                          // Rupees in words
                          pw.Row(
                            children: [
                              pw.Text('(Rupees ', style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Expanded(
                                child: pw.Container(
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8, style: pw.BorderStyle.dotted)),
                                  ),
                                  padding: const pw.EdgeInsets.only(left: 2),
                                  child: pw.Text(
                                    amountInWords,
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                                  ),
                                ),
                              ),
                              pw.Text(' )', style: const pw.TextStyle(fontSize: 8.5)),
                            ],
                          ),
                          pw.SizedBox(height: 8),

                          // Electronically generated disclaimer
                          pw.Text(
                            '* This is an electronically generated receipt and does not require a physical signature.',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontStyle: pw.FontStyle.italic,
                              fontSize: 7.5,
                              color: PdfColors.black,
                            ),
                          ),
                        ],
                      ),
                    ),

                    pw.SizedBox(width: 8),

                    // RIGHT AREA: Row-locked Table (Special Fund, TOTAL + Rs. | P.)
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Left Labels aligned with respective table rows
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Container(height: 18), // Header row spacer
                            pw.Container(height: 18), // Maint row spacer
                            pw.Container(height: 18), // Parking row spacer
                            pw.Container(
                              height: 18,
                              alignment: pw.Alignment.centerRight,
                              padding: const pw.EdgeInsets.only(right: 4),
                              child: pw.Text(
                                'Special Fund',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                              ),
                            ),
                            pw.Container(
                              height: 22,
                              alignment: pw.Alignment.centerRight,
                              padding: const pw.EdgeInsets.only(right: 4),
                              child: pw.Text(
                                'TOTAL',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                              ),
                            ),
                          ],
                        ),

                        // Locked-height Table Box with No Stretching
                        pw.Container(
                          width: 85,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.black, width: 1.2),
                          ),
                          child: pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              // Table Header: Rs. | P.
                              pw.Container(
                                height: 18,
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
                                ),
                                child: pw.Row(
                                  children: [
                                    pw.Expanded(
                                      flex: 65,
                                      child: pw.Center(child: pw.Text('Rs.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                                    ),
                                    pw.Container(width: 1, height: 18, color: PdfColors.black),
                                    pw.Expanded(
                                      flex: 35,
                                      child: pw.Center(child: pw.Text('P.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                                    ),
                                  ],
                                ),
                              ),
                              // Row 1: Maintenance
                              _buildAmountRow(baseMaintenance),
                              // Row 2: Car/Bike Parking
                              _buildAmountRow(totalParkingCharges),
                              // Row 3: Special Fund / Puja
                              _buildAmountRow(pujaSubscription),
                              // TOTAL Row with top double/heavy border
                              pw.Container(
                                height: 22,
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(
                                    top: pw.BorderSide(color: PdfColors.black, width: 1.5),
                                  ),
                                ),
                                child: pw.Row(
                                  children: [
                                    pw.Expanded(
                                      flex: 65,
                                      child: pw.Container(
                                        alignment: pw.Alignment.centerRight,
                                        padding: const pw.EdgeInsets.only(right: 4),
                                        child: pw.Text(
                                          totalAmount.floor().toString(),
                                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                                        ),
                                      ),
                                    ),
                                    pw.Container(width: 1, height: 22, color: PdfColors.black),
                                    pw.Expanded(
                                      flex: 35,
                                      child: pw.Container(
                                        alignment: pw.Alignment.center,
                                        child: pw.Text(
                                          ((totalAmount - totalAmount.floor()) * 100).round().toString().padLeft(2, '0'),
                                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 6),

                // 8. Footer: Association Tagline
                pw.Center(
                  child: pw.Text(
                    'Regular monthly payment of Maintenance Charge, Makes our Task easy.',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontStyle: pw.FontStyle.italic,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildMonthPill(String monthName, bool isSelected) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
      decoration: pw.BoxDecoration(
        color: isSelected ? PdfColors.black : PdfColors.white,
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Text(
        monthName,
        style: pw.TextStyle(
          fontSize: 6.5,
          fontWeight: isSelected ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isSelected ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _buildAmountRow(double amount) {
    final rupees = amount.floor();
    final paise = ((amount - rupees) * 100).round();

    return pw.Container(
      height: 18,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 65,
            child: pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.only(right: 4),
              child: pw.Text(
                amount > 0 ? rupees.toString() : '',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
          ),
          pw.Container(width: 1, height: 18, color: PdfColors.black),
          pw.Expanded(
            flex: 35,
            child: pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                amount > 0 ? paise.toString().padLeft(2, '0') : '',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Direct download / save with auto-populated file name
  static Future<void> downloadReceiptPdf({
    required String receiptNumber,
    required DateTime date,
    required String residentName,
    required String block,
    required String flatNumber,
    required String billingMonth,
    required String financialYear,
    required double baseMaintenance,
    required double carParkingCharges,
    required double bikeParkingCharges,
    required double pujaSubscription,
    required double totalAmount,
    required String vehicleReg,
    required String paymentMode,
    required String referenceNumber,
    String? bankName,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      pageFormat: PdfPageFormat.a4,
      receiptNumber: receiptNumber,
      date: date,
      residentName: residentName,
      block: block,
      flatNumber: flatNumber,
      billingMonth: billingMonth,
      financialYear: financialYear,
      baseMaintenance: baseMaintenance,
      carParkingCharges: carParkingCharges,
      bikeParkingCharges: bikeParkingCharges,
      pujaSubscription: pujaSubscription,
      totalAmount: totalAmount,
      vehicleReg: vehicleReg,
      paymentMode: paymentMode,
      referenceNumber: referenceNumber,
      bankName: bankName,
    );

    final cleanFlat = flatNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
    final cleanMonth = billingMonth.replaceAll(RegExp(r'[^\w\-]'), '_');
    final cleanReceipt = receiptNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
    final fileName = 'Receipt_${cleanFlat}_${cleanMonth}_$cleanReceipt.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: fileName,
    );
  }

  /// Direct printing action
  static Future<void> printReceipt({
    required String receiptNumber,
    required DateTime date,
    required String residentName,
    required String block,
    required String flatNumber,
    required String billingMonth,
    required String financialYear,
    required double baseMaintenance,
    required double carParkingCharges,
    required double bikeParkingCharges,
    required double pujaSubscription,
    required double totalAmount,
    required String vehicleReg,
    required String paymentMode,
    required String referenceNumber,
    String? bankName,
  }) async {
    final cleanFlat = flatNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
    final cleanMonth = billingMonth.replaceAll(RegExp(r'[^\w\-]'), '_');
    final cleanReceipt = receiptNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
    final docName = 'Receipt_${cleanFlat}_${cleanMonth}_$cleanReceipt';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => generateReceiptPdf(
        pageFormat: format,
        receiptNumber: receiptNumber,
        date: date,
        residentName: residentName,
        block: block,
        flatNumber: flatNumber,
        billingMonth: billingMonth,
        financialYear: financialYear,
        baseMaintenance: baseMaintenance,
        carParkingCharges: carParkingCharges,
        bikeParkingCharges: bikeParkingCharges,
        pujaSubscription: pujaSubscription,
        totalAmount: totalAmount,
        vehicleReg: vehicleReg,
        paymentMode: paymentMode,
        referenceNumber: referenceNumber,
        bankName: bankName,
      ),
      name: docName,
    );
  }
}
