import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import '../services/mysql_service.dart';

class AgendaSessionReportPage extends StatefulWidget {
  final DateTime sessionDate;
  final CircuitRecord circuit;
  final List<CaseRecord> cases;
  const AgendaSessionReportPage(
      {super.key,
      required this.sessionDate,
      required this.circuit,
      required this.cases});

  @override
  State<AgendaSessionReportPage> createState() =>
      _AgendaSessionReportPageState();
}

class _AgendaSessionReportPageState extends State<AgendaSessionReportPage> {
  double _scale = 1.0;
  final _scroll = ScrollController();

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
    final headerStyle = pw.TextStyle(font: arBold, fontSize: 18);
    final tableHeader = pw.TextStyle(font: arBold, fontSize: 12);
    final cellStyle = pw.TextStyle(font: arBold, fontSize: 10);

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
                'جلسة ${_fmt(widget.sessionDate)}  الدائرة: ${widget.circuit.name}  رقم: ${widget.circuit.number}  يوم الانعقاد: ${widget.circuit.meetingDay}',
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
                // نعكس الترتيب فعلياً ليظهر "رول" في أقصى اليمين و"القرار الحالي" في أقصى اليسار
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.5), // القرار الحالي
                  1: const pw.FlexColumnWidth(2.5), // الجلسة السابقة
                  2: const pw.FlexColumnWidth(3.5), // المدعى عليه
                  3: const pw.FlexColumnWidth(3.5), // المدعى
                  4: const pw.FlexColumnWidth(2.5), // رقم وسنة الدعوى
                  5: const pw.FlexColumnWidth(1.2), // رول
                },
                children: [
                  pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        for (final h in const [
                          'القرار الحالي',
                          'الجلسة السابقة',
                          'المدعى عليه',
                          'المدعى',
                          'رقم وسنة الدعوى',
                          'رول'
                        ])
                          pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            alignment: pw.Alignment.center,
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text(h, style: tableHeader),
                            ),
                          ),
                      ]),
                  for (final c in widget.cases)
                    pw.TableRow(children: [
                      // القرار الحالي (يسار)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(c.decision, style: cellStyle),
                        ),
                      ),
                      // الجلسة السابقة
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(_fmt(c.prevSessionDate),
                              style: cellStyle),
                        ),
                      ),
                      // المدعى عليه
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(c.defendant, style: cellStyle),
                        ),
                      ),
                      // المدعى
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(c.plaintiff, style: cellStyle),
                        ),
                      ),
                      // رقم وسنة الدعوى
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text('${c.number} لسنة ${c.year}',
                              style: cellStyle),
                        ),
                      ),
                      // رول (يمين)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.rtl,
                          child: pw.Text(c.rollNumber ?? '', style: cellStyle),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ]),
        )
      ],
    ));
    return doc.save();
  }

  void _exportPdf() async {
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(
          bytes: bytes,
          filename: 'agenda_session_${_fmt(widget.sessionDate)}.pdf');
    } catch (e) {
      if (e is MissingPluginException) {
        try {
          final bytes = await _buildPdf();
          final dir = await getDirectoryPath();
          if (dir != null) {
            final out =
                File('$dir/agenda_session_${_fmt(widget.sessionDate)}.pdf');
            await out.writeAsBytes(bytes);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حفظ الملف: ${out.path}')));
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
      await Printing.layoutPdf(onLayout: (_) => _buildPdf());
    } catch (e) {
      if (e is MissingPluginException) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('الطباعة غير متاحة الآن؛ تم توفير حفظ PDF بدلاً من ذلك')));
        _exportPdf();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل أمر الطباعة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طباعة جلسة الأجندة'),
          actions: [
            IconButton(
                onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf)),
            IconButton(onPressed: _printPdf, icon: const Icon(Icons.print)),
          ],
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.grey.shade100,
              child: Row(children: [
                const Text('تحكم العرض:'),
                const SizedBox(width: 12),
                IconButton(
                    onPressed: () =>
                        setState(() => _scale = (_scale - 0.1).clamp(0.5, 3)),
                    icon: const Icon(Icons.zoom_out)),
                IconButton(
                    onPressed: () => setState(() => _scale = 1.0),
                    icon: const Icon(Icons.aspect_ratio)),
                IconButton(
                    onPressed: () =>
                        setState(() => _scale = (_scale + 0.1).clamp(0.5, 3)),
                    icon: const Icon(Icons.zoom_in)),
              ]),
            ),
            Expanded(
              child: InteractiveViewer(
                scaleEnabled: true,
                minScale: 0.5,
                maxScale: 3,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Transform.scale(
                    scale: _scale,
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Header preview (non-PDF) aligned to right
                            const Align(
                              alignment: Alignment.topRight,
                              child: Icon(Icons.image, size: 48),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'جلسة ${_fmt(widget.sessionDate)}  الدائرة: ${widget.circuit.name}  رقم: ${widget.circuit.number}  يوم الانعقاد: ${widget.circuit.meetingDay}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            _buildTable(widget.cases),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<CaseRecord> cases) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.resolveWith((_) => Colors.grey.shade200),
          columns: const [
            DataColumn(
                label: Center(
                    child: Text('رول',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
            DataColumn(
                label: Center(
                    child: Text('رقم وسنة الدعوى',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
            DataColumn(
                label: Center(
                    child: Text('المدعى',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
            DataColumn(
                label: Center(
                    child: Text('المدعى عليه',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
            DataColumn(
                label: Center(
                    child: Text('الجلسة السابقة',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
            DataColumn(
                label: Center(
                    child: Text('القرار الحالي',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center))),
          ],
          rows: [
            for (final c in cases)
              DataRow(cells: [
                DataCell(Center(
                    child: Text(c.rollNumber ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
                DataCell(Center(
                    child: Text('${c.number} لسنة ${c.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
                DataCell(Center(
                    child: Text(c.plaintiff,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
                DataCell(Center(
                    child: Text(c.defendant,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
                DataCell(Center(
                    child: Text(_fmt(c.prevSessionDate),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
                DataCell(Center(
                    child: Text(c.decision,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)))),
              ])
          ],
        ),
      ),
    );
  }
}
