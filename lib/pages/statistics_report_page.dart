import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/mysql_service.dart';

enum StatisticsReportType { defenseMemos, finalJudgments }

class StatisticsReportPage extends StatefulWidget {
  final StatisticsReportType type;
  final DateTime fromDate;
  final DateTime toDate;
  final List<CaseRecord> cases;
  final String? nature; // 'صالح' أو 'ضد' لاختيار عنوان خاص
  const StatisticsReportPage({
    super.key,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.cases,
    this.nature,
  });

  @override
  State<StatisticsReportPage> createState() => _StatisticsReportPageState();
}

class _StatisticsReportPageState extends State<StatisticsReportPage> {
  double _scale = 1.0;
  final _scrollController = ScrollController();

  String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _title() {
    final fromStr = _fmt(widget.fromDate);
    final toStr = _fmt(widget.toDate);
    switch (widget.type) {
      case StatisticsReportType.defenseMemos:
        return 'احصائية مذكرات الدفاع المقدمة من الفترة $fromStr إلى الفترة $toStr';
      case StatisticsReportType.finalJudgments:
        if (widget.nature != null) {
          if (widget.nature == 'صالح') {
            return 'احصائية احكام الصالح النهائية الصادرة خلال الفترة من $fromStr الى $toStr';
          }
          if (widget.nature == 'ضد') {
            return 'احصائية أحكام الضد النهائية الصادرة خلال الفترة من $fromStr الى $toStr';
          }
        }
        return 'احصائية الأحكام النهائية الصادرة خلال الفترة من $fromStr إلى $toStr';
    }
  }

  Future<Uint8List> _buildPdf() async {
    pw.Font? arabicRegular;
    pw.Font? arabicBold;
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      arabicRegular = pw.Font.ttf(regData);
      arabicBold = pw.Font.ttf(boldData);
    } catch (_) {}

    final doc = pw.Document(
      theme: (arabicRegular != null && arabicBold != null)
          ? pw.ThemeData.withFont(base: arabicRegular, bold: arabicBold)
          : null,
    );

    // All styles use bold font as requested
    final headerTextStyle = pw.TextStyle(font: arabicBold, fontSize: 18);
    final tableHeaderStyle = pw.TextStyle(
        font: arabicBold ?? arabicRegular, fontSize: 11); // keep size
    final cellStyle = pw.TextStyle(
        font: arabicBold ?? arabicRegular, fontSize: 9); // now bold

    final isMemos = widget.type == StatisticsReportType.defenseMemos;
    // Build headers in on-screen logical order then reverse for PDF to render RTL visually identical
    final baseHeaders = isMemos
        ? [
            'رقم الدعوى',
            'سنة الدعوى',
            'المدعى',
            'المدعى عليه',
            'تاريخ نسخ المذكرة',
            'تاريخ جلسة المذكرة'
          ]
        : [
            'رقم الدعوى',
            'سنة الدعوى',
            'المدعى',
            'المدعى عليه',
            'جلسة صدور الحكم'
          ];
    final headers = baseHeaders.reversed.toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(_title(),
                      style: headerTextStyle, textAlign: pw.TextAlign.center),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey500, width: 0.6),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(3),
                        3: const pw.FlexColumnWidth(3),
                        4: const pw.FlexColumnWidth(3),
                        if (isMemos) 5: const pw.FlexColumnWidth(3),
                      },
                      children: [
                        pw.TableRow(
                          decoration:
                              const pw.BoxDecoration(color: PdfColors.grey300),
                          children: [
                            for (final h in headers)
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Center(
                                    child: pw.Text(h, style: tableHeaderStyle)),
                              ),
                          ],
                        ),
                        for (final c in widget.cases)
                          pw.TableRow(
                            children: () {
                              final cells = <pw.Widget>[];
                              if (isMemos) {
                                // Original order: number, year, plaintiff, defendant, copyDate, sessionDate
                                cells.addAll([
                                  _pdfCellCenter(
                                      _fmt(c.memoSessionDate), cellStyle),
                                  _pdfCellCenter(
                                      _fmt(c.memoCopyDate), cellStyle),
                                  _pdfCellText(c.defendant, cellStyle),
                                  _pdfCellText(c.plaintiff, cellStyle),
                                  _pdfCellCenter(c.year, cellStyle),
                                  _pdfCellCenter(c.number, cellStyle),
                                ]);
                              } else {
                                // Original order: number, year, plaintiff, defendant, judgmentDate
                                cells.addAll([
                                  _pdfCellCenter(
                                      _fmt(c.judgmentSessionDate), cellStyle),
                                  _pdfCellText(c.defendant, cellStyle),
                                  _pdfCellText(c.plaintiff, cellStyle),
                                  _pdfCellCenter(c.year, cellStyle),
                                  _pdfCellCenter(c.number, cellStyle),
                                ]);
                              }
                              return cells;
                            }(),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('عدد السجلات: ${widget.cases.length}',
                        style: cellStyle),
                  )
                ],
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: pw.Center(child: pw.Text(text, style: style)),
    );
  }

  pw.Widget _pdfCellText(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
    );
  }

  void _exportPdf() async {
    try {
      final data = await _buildPdf();
      await Printing.sharePdf(
          bytes: data, filename: 'statistics_${_title()}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل إنشاء PDF: $e')));
    }
  }

  void _printPdf() async {
    try {
      await Printing.layoutPdf(onLayout: (format) => _buildPdf());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل أمر الطباعة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMemos = widget.type == StatisticsReportType.defenseMemos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('عرض تقرير إحصائي'),
        actions: [
          IconButton(
              tooltip: 'PDF',
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf)),
          IconButton(
              tooltip: 'طباعة',
              onPressed: _printPdf,
              icon: const Icon(Icons.print)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: InteractiveViewer(
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 3,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Transform.scale(
                  scale: _scale,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _title(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _buildCasesTable(isMemos),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          const Text('تحكم العرض:'),
          const SizedBox(width: 12),
          IconButton(
              onPressed: () {
                setState(() {
                  _scale = (_scale - 0.1).clamp(0.5, 3);
                });
              },
              icon: const Icon(Icons.zoom_out)),
          IconButton(
              onPressed: () {
                setState(() {
                  _scale = 1.0;
                });
              },
              icon: const Icon(Icons.aspect_ratio)),
          IconButton(
              onPressed: () {
                setState(() {
                  _scale = (_scale + 0.1).clamp(0.5, 3);
                });
              },
              icon: const Icon(Icons.zoom_in)),
        ],
      ),
    );
  }

  Widget _buildCasesTable(bool isMemos) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.resolveWith((_) => Colors.grey.shade200),
          columns: [
            DataColumn(label: _bold('رقم الدعوى')),
            DataColumn(label: _bold('سنة الدعوى')),
            DataColumn(label: _bold('المدعى')),
            DataColumn(label: _bold('المدعى عليه')),
            if (isMemos) ...[
              DataColumn(label: _bold('تاريخ نسخ المذكرة')),
              DataColumn(label: _bold('تاريخ جلسة المذكرة')),
            ] else ...[
              DataColumn(label: _bold('جلسة صدور الحكم')),
            ]
          ],
          rows: [
            for (final c in widget.cases)
              DataRow(cells: [
                DataCell(_bold(c.number)),
                DataCell(_bold(c.year)),
                DataCell(_wrapBold(c.plaintiff)),
                DataCell(_wrapBold(c.defendant)),
                if (isMemos) ...[
                  DataCell(_bold(_fmt(c.memoCopyDate))),
                  DataCell(_bold(_fmt(c.memoSessionDate))),
                ] else ...[
                  DataCell(_bold(_fmt(c.judgmentSessionDate))),
                ]
              ])
          ],
        ),
      ),
    );
  }
}

Widget _wrapBold(String text) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: Text(
      text,
      softWrap: true,
      overflow: TextOverflow.visible,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}

Widget _bold(String text) =>
    Text(text, style: const TextStyle(fontWeight: FontWeight.bold));
