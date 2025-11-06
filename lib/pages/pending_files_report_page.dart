import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import '../services/mysql_service.dart';

class PendingFilesReportPage extends StatefulWidget {
  final List<PendingFileRecord> files;
  const PendingFilesReportPage({super.key, required this.files});

  @override
  State<PendingFilesReportPage> createState() => _PendingFilesReportPageState();
}

class _PendingFilesReportPageState extends State<PendingFilesReportPage> {
  double _scale = 1.0;

  String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<pw.ImageProvider?> _loadLogo() async {
    Future<ByteData?> load(String path) async {
      try {
        return await rootBundle.load(path);
      } catch (_) {
        return null;
      }
    }

    // Prefer the requested JPEG logo; fallback to PNG (if present) then agenda default
    final try1 = await load('assets/images/sla-logo.jpg');
    final data = try1 ??
        await load('assets/images/sla-logo.png') ??
        await load('assets/images/agenda-logo.png');
    if (data == null) return null;
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  Future<Uint8List> _buildPdf() async {
    pw.Font? arReg;
    pw.Font? arBold;
    try {
      arReg =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
      arBold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
    } catch (_) {}
    final theme = (arReg != null && arBold != null)
        ? pw.ThemeData.withFont(base: arReg, bold: arBold)
        : null;
    final doc = pw.Document(theme: theme);
    final logo = await _loadLogo();
    final headerStyle = pw.TextStyle(font: arBold, fontSize: 16);
    final tableHeader = pw.TextStyle(font: arBold, fontSize: 8);
    final cellStyle = pw.TextStyle(font: arBold, fontSize: 7);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(children: [
            // Logo pinned to top-right
            if (logo != null)
              pw.Align(
                alignment: pw.Alignment.topRight,
                child: pw.SizedBox(
                    width: 60,
                    height: 60,
                    child: pw.Image(logo, fit: pw.BoxFit.contain)),
              ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'بيان ملفات تحت الرفع',
                style: headerStyle,
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
                columnWidths: {
                  0: const pw.FixedColumnWidth(50), // تاريخ الجلسة
                  1: const pw.FlexColumnWidth(1.5), // الدائرة
                  2: const pw.FixedColumnWidth(55), // رقم وسنة الدعوى
                  3: const pw.FlexColumnWidth(2), // الرأى القانونى
                  4: const pw.FixedColumnWidth(50), // تاريخ الاستلام
                  5: const pw.FlexColumnWidth(2), // المدعى عليه
                  6: const pw.FlexColumnWidth(2), // المدعى
                  7: const pw.FixedColumnWidth(55), // رقم وسنة تحت الرفع
                  8: const pw.FixedColumnWidth(25), // م
                },
                children: [
                  pw.TableRow(
                      decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFE0E0E0)),
                      children: [
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child:
                                  pw.Text('تاريخ\nالجلسة', style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('الدائرة', style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('رقم وسنة\nالدعوى المقيدة',
                                  style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child:
                                  pw.Text('الرأى القانونى', style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('تاريخ\nالاستلام',
                                  style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('المدعى عليه', style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('المدعى', style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('رقم وسنة\nتحت الرفع',
                                  style: tableHeader),
                            )),
                        pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text('م', style: tableHeader),
                            )),
                      ]),
                  ...widget.files.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final file = entry.value;
                    final caseNumberYear = file.caseNumberAfterFiling != null &&
                            file.caseYearAfterFiling != null
                        ? '${file.caseNumberAfterFiling} لسنة ${file.caseYearAfterFiling}'
                        : '-';
                    return pw.TableRow(children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(_fmt(file.firstSessionDate),
                              style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(file.circuitAfterFiling ?? '-',
                              style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(caseNumberYear, style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(
                              file.legalOpinion.isEmpty
                                  ? '-'
                                  : file.legalOpinion,
                              style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child:
                              pw.Text(_fmt(file.receiptDate), style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(file.defendant, style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(file.plaintiff, style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(
                              '${file.fileNumber} لسنة ${file.fileYear}',
                              style: cellStyle),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(index.toString(), style: cellStyle),
                        ),
                      ),
                    ]);
                  }),
                ],
              ),
            ),
          ]),
        ),
      ],
    ));
    return doc.save();
  }

  Future<void> _savePdf() async {
    try {
      final bytes = await _buildPdf();
      final fileName =
          'pending_files_${DateTime.now().toIso8601String().substring(0, 10)}.pdf';
      final path = await getSaveLocation(suggestedName: fileName);
      if (path == null) return;
      await File(path.path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حفظ التقرير بنجاح'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في حفظ التقرير: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _print() async {
    try {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في الطباعة: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقرير ملفات تحت الرفع'),
          actions: [
            IconButton(
              onPressed: _print,
              icon: const Icon(Icons.print),
              tooltip: 'طباعة',
            ),
            IconButton(
              onPressed: _savePdf,
              icon: const Icon(Icons.save),
              tooltip: 'حفظ PDF',
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              onPressed: () => setState(() {
                _scale = (_scale * 1.2).clamp(0.5, 3.0);
              }),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_out),
              onPressed: () => setState(() {
                _scale = (_scale / 1.2).clamp(0.5, 3.0);
              }),
            ),
          ],
        ),
        body: FutureBuilder<Uint8List>(
          future: _buildPdf(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 3.0,
              scaleEnabled: true,
              child: Center(
                child: Transform.scale(
                  scale: _scale,
                  child: PdfPreview(
                    build: (_) async => snap.data!,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    allowSharing: false,
                    allowPrinting: false,
                    pdfFileName:
                        'pending_files_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
