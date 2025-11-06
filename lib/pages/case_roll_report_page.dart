import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import '../services/mysql_service.dart';

class CaseRollReportPage extends StatefulWidget {
  final DateTime sessionDate; // required selected session date from search
  final CircuitRecord circuit; // selected circuit
  final List<CaseRecord>
      cases; // cases currently displayed in table (already filtered)
  const CaseRollReportPage(
      {super.key,
      required this.sessionDate,
      required this.circuit,
      required this.cases});

  @override
  State<CaseRollReportPage> createState() => _CaseRollReportPageState();
}

class _CaseRollReportPageState extends State<CaseRollReportPage> {
  double _scale = 1.0;
  final _scrollController = ScrollController();

  String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Uint8List> _buildPdf() async {
    // Attempt to load embedded Arabic fonts (Cairo). If missing, fallback to default.
    pw.Font? arabicRegular;
    pw.Font? arabicBold;
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      arabicRegular = pw.Font.ttf(regData);
      arabicBold = pw.Font.ttf(boldData);
    } catch (_) {
      // Fonts not found; will use default PDF font (non-Arabic shaping) but at least won't crash.
    }
    final doc = pw.Document(
      theme: (arabicRegular != null && arabicBold != null)
          ? pw.ThemeData.withFont(base: arabicRegular, bold: arabicBold)
          : null,
    );
    final cases = widget.cases;
    // توحيد جميع النصوص بخط عريض مع أحجام أصغر لزيادة الكثافة
    final headerTextStyle = pw.TextStyle(font: arabicBold, fontSize: 18);
    final tableHeaderStyle = headerTextStyle.copyWith(fontSize: 12);
    final tableCellTextStyle = headerTextStyle.copyWith(fontSize: 10);
    final baseTextStyle = headerTextStyle.copyWith(fontSize: 11);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('رول جلسة', style: headerTextStyle),
                    pw.SizedBox(height: 4),
                    pw.Text('تاريخ الجلسة: ${_fmt(widget.sessionDate)}',
                        style: baseTextStyle),
                    pw.SizedBox(height: 8),
                    pw.Text(
                        'الدائرة: ${widget.circuit.name} (${widget.circuit.number}) - يوم الانعقاد: ${widget.circuit.meetingDay} - الموعد: ${widget.circuit.meetingTime}',
                        textAlign: pw.TextAlign.center,
                        style: baseTextStyle),
                    pw.SizedBox(height: 16),
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                      ),
                      child: pw.Table(
                        border: pw.TableBorder.all(
                          color: PdfColors.grey400,
                          width: 0.6,
                        ),
                        // نعكس الترتيب فعلياً بحيث العنصر الأخير (رقم الرول) يُمرر أخيراً لكن سيظهر في أقصى اليمين في عرض RTL
                        columnWidths: {
                          0: const pw.FlexColumnWidth(4), // القرار (واسع)
                          1: const pw.FlexColumnWidth(
                              4), // ما يقدم بالجلسة (واسع)
                          2: const pw.FlexColumnWidth(3.5), // المدعى عليه
                          3: const pw.FlexColumnWidth(3.5), // المدعى
                          4: const pw.FlexColumnWidth(2), // سنة الدعوى
                          5: const pw.FlexColumnWidth(2.2), // رقم الدعوى
                          6: const pw.FlexColumnWidth(1.2), // رقم الرول (فارغ)
                        },
                        children: [
                          // لضمان أن أول عمود (رقم الرول) يظهر في أقصى اليمين عند الطباعة
                          // نحتفظ بالتسلسل المنطقي للقائمة لكن نلف كل صف داخل Directionality RTL
                          // نبني الرؤوس معكوسة (القرار أولاً ثم رقم الرول أخيراً)
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(
                                color: PdfColors.grey300),
                            children: [
                              for (final h in const [
                                'القرار',
                                'ما يقدم بالجلسة',
                                'المدعى عليه',
                                'المدعى',
                                'سنة الدعوى',
                                'رقم الدعوى',
                                'رقم الرول',
                              ])
                                pw.Container(
                                  padding: const pw.EdgeInsets.all(4),
                                  alignment: pw.Alignment.center,
                                  child: pw.Directionality(
                                    textDirection: pw.TextDirection.rtl,
                                    child: pw.Text(h, style: tableHeaderStyle),
                                  ),
                                ),
                            ],
                          ),
                          for (final c in cases)
                            pw.TableRow(
                              children: [
                                for (final cell in [
                                  '', // القرار
                                  '', // ما يقدم
                                  c.defendant,
                                  c.plaintiff,
                                  c.year,
                                  c.number,
                                  '', // رقم الرول فارغ
                                ])
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 3),
                                    alignment: pw.Alignment.topRight,
                                    child: pw.Directionality(
                                      textDirection: pw.TextDirection.rtl,
                                      child: pw.Text(
                                        cell,
                                        style: tableCellTextStyle,
                                        softWrap: true,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  void _exportPdf() async {
    try {
      final data = await _buildPdf();
      await Printing.sharePdf(
          bytes: data, filename: 'roll_${_fmt(widget.sessionDate)}.pdf');
    } catch (e) {
      if (e is MissingPluginException) {
        // Fallback: let user pick a location to save the PDF manually
        try {
          final data = await _buildPdf();
          final fileName = 'roll_${_fmt(widget.sessionDate)}.pdf';
          final dirPath = await getDirectoryPath();
          if (dirPath != null) {
            final outFile = File('$dirPath/$fileName');
            await outFile.writeAsBytes(data);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('تم حفظ الملف بنجاح: ${outFile.path}')));
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم إلغاء اختيار المسار')));
            }
          }
        } catch (se) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('تعذر حفظ الملف: $se')));
          }
        }
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل إنشاء PDF: $e')));
    }
  }

  void _printPdf() async {
    try {
      await Printing.layoutPdf(onLayout: (format) => _buildPdf());
    } catch (e) {
      if (e is MissingPluginException) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'إضافة الطباعة غير مفعلة. تم توفير حفظ PDF بدلاً من ذلك')));
        _exportPdf();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل أمر الطباعة: $e')));
    }
  }

  void _exportCsv() async {
    final rows = <List<dynamic>>[];
    rows.add([
      'رقم الرول',
      'رقم الدعوى',
      'سنة الدعوى',
      'المدعى',
      'المدعى عليه',
      'ما يقدم بالجلسة',
      'القرار'
    ]);
    for (final c in widget.cases) {
      rows.add(['', c.number, c.year, c.plaintiff, c.defendant, '', '']);
    }
    final csvStr = const ListToCsvConverter().convert(rows);
    // For simplicity show dialog with CSV preview (user can copy). Could integrate file_saver plugin later.
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV (انسخ المحتوى)'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: SelectableText(csvStr)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  // Placeholders for Word / Excel (could be implemented by generating .docx / xlsx externally)
  void _exportWordPlaceholder() {
    _info('تنفيذ Word سيتطلب إضافة حزمة docx؛ حالياً غير متاح');
  }

  void _exportExcelPlaceholder() {
    _info('تنفيذ Excel سيتطلب حزمة xlsx؛ حالياً نوفر CSV كبديل');
  }

  void _info(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final cases = widget.cases;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير رول الجلسة'),
        actions: [
          IconButton(
              tooltip: 'PDF',
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf)),
          IconButton(
              tooltip: 'طباعة',
              onPressed: _printPdf,
              icon: const Icon(Icons.print)),
          IconButton(
              tooltip: 'CSV',
              onPressed: _exportCsv,
              icon: const Icon(Icons.table_view)),
          IconButton(
              tooltip: 'Word',
              onPressed: _exportWordPlaceholder,
              icon: const Icon(Icons.description_outlined)),
          IconButton(
              tooltip: 'Excel',
              onPressed: _exportExcelPlaceholder,
              icon: const Icon(Icons.grid_on)),
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
                        Text('رول جلسة',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                )),
                        const SizedBox(height: 2),
                        Text('تاريخ الجلسة: ${_fmt(widget.sessionDate)}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                            'الدائرة: ${widget.circuit.name} (${widget.circuit.number}) - يوم الانعقاد: ${widget.circuit.meetingDay} - الموعد: ${widget.circuit.meetingTime}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 16),
                        _buildCasesTable(cases),
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

  Widget _buildCasesTable(List<CaseRecord> cases) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // so initial view anchors on the right side
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.resolveWith((_) => Colors.grey.shade200),
          columns: const [
            DataColumn(
                label: Text('رقم الرول', style: TextStyle(fontSize: 12))),
            DataColumn(
                label: Text('رقم الدعوى', style: TextStyle(fontSize: 12))),
            DataColumn(
                label: Text('سنة الدعوى', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('المدعى', style: TextStyle(fontSize: 12))),
            DataColumn(
                label: Text('المدعى عليه', style: TextStyle(fontSize: 12))),
            DataColumn(
                label: Text('ما يقدم بالجلسة', style: TextStyle(fontSize: 12))),
            DataColumn(label: Text('القرار', style: TextStyle(fontSize: 12))),
          ],
          rows: [
            for (final c in cases)
              DataRow(cells: [
                const DataCell(_SmallCellText('')),
                DataCell(_wrapSmall(c.number)),
                DataCell(_wrapSmall(c.year)),
                DataCell(_wrapSmall(c.plaintiff)),
                DataCell(_wrapSmall(c.defendant)),
                const DataCell(_SmallCellText('')),
                const DataCell(_SmallCellText('')),
              ])
          ],
        ),
      ),
    );
  }
}

// Helpers for smaller table font in DataTable
class _SmallCellText extends StatelessWidget {
  final String text;
  const _SmallCellText(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }
}

Widget _wrapSmall(String text) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: _SmallCellText(text),
  );
}
