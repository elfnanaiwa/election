import 'package:flutter/material.dart';
import '../services/mysql_service.dart';
import 'pending_files_report_page.dart';

class PendingFilesPage extends StatefulWidget {
  const PendingFilesPage({super.key});

  @override
  State<PendingFilesPage> createState() => _PendingFilesPageState();
}

class _PendingFilesPageState extends State<PendingFilesPage> {
  final _fileNumberController = TextEditingController();
  final _fileYearController = TextEditingController();
  final _plaintiffController = TextEditingController();
  final _defendantController = TextEditingController();

  final _service = MySqlService();

  bool _loading = false;
  List<PendingFileRecord> _results = [];
  PendingFileRecord? _selected;
  bool _showAll = false;

  @override
  void dispose() {
    _fileNumberController.dispose();
    _fileYearController.dispose();
    _plaintiffController.dispose();
    _defendantController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() {
      _showAll = false;
    });
    final fileNumber = _fileNumberController.text.trim();
    final fileYear = _fileYearController.text.trim();
    final plaintiff = _plaintiffController.text.trim();
    final defendant = _defendantController.text.trim();

    final hasNumberYear = fileNumber.isNotEmpty && fileYear.isNotEmpty;
    final hasPlaintiff = plaintiff.isNotEmpty;
    final hasDefendant = defendant.isNotEmpty;

    if (!hasNumberYear && !hasPlaintiff && !hasDefendant) {
      _showMsg('أدخل (رقم وسنة) معاً أو المدعى أو المدعى عليه', isError: true);
      return;
    }
    if ((fileNumber.isNotEmpty && fileYear.isEmpty) ||
        (fileYear.isNotEmpty && fileNumber.isEmpty)) {
      _showMsg('لابد من إدخال رقم وسنة الملف معاً', isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _selected = null;
    });

    try {
      final data = await _service.searchPendingFiles(
        fileNumber: hasNumberYear ? fileNumber : null,
        fileYear: hasNumberYear ? fileYear : null,
        plaintiff: hasPlaintiff ? plaintiff : null,
        defendant: hasDefendant ? defendant : null,
      );
      if (!mounted) return;
      setState(() {
        _results = data;
      });
      if (data.isEmpty) {
        _showMsg('لا توجد نتائج');
      }
    } catch (e) {
      _showMsg('خطأ أثناء البحث: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadAllFiles() async {
    setState(() {
      _loading = true;
      _showAll = true;
      _selected = null;
    });
    try {
      final data = await _service.getAllPendingFiles();
      if (!mounted) return;
      setState(() {
        _results = data;
      });
      if (data.isEmpty) {
        _showMsg('لا توجد ملفات محفوظة');
      }
    } catch (e) {
      _showMsg('خطأ أثناء تحميل الملفات: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.right),
      backgroundColor: isError ? Colors.red : null,
    ));
  }

  Future<void> _openAddEditDialog({PendingFileRecord? existing}) async {
    final formKey = GlobalKey<FormState>();
    final fileNumberCtrl =
        TextEditingController(text: existing?.fileNumber ?? '');
    final fileYearCtrl = TextEditingController(text: existing?.fileYear ?? '');
    final plaintiffCtrl =
        TextEditingController(text: existing?.plaintiff ?? '');
    final defendantCtrl =
        TextEditingController(text: existing?.defendant ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    DateTime? receiptDate = existing?.receiptDate;
    String? legalOpinion = existing?.legalOpinion;

    final caseNumberCtrl =
        TextEditingController(text: existing?.caseNumberAfterFiling ?? '');
    final caseYearCtrl =
        TextEditingController(text: existing?.caseYearAfterFiling ?? '');
    final circuitCtrl =
        TextEditingController(text: existing?.circuitAfterFiling ?? '');
    DateTime? firstSessionDate = existing?.firstSessionDate;

    final legalOpinionNotifier = ValueNotifier<String?>(legalOpinion);

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
              existing == null ? 'إضافة ملف تحت الرفع' : 'تعديل ملف تحت الرفع'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // رقم الملف
                    TextFormField(
                      controller: fileNumberCtrl,
                      decoration:
                          const InputDecoration(labelText: 'رقم الملف *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    // سنة الملف
                    TextFormField(
                      controller: fileYearCtrl,
                      decoration:
                          const InputDecoration(labelText: 'سنة الملف *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    // تاريخ الاستلام
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: receiptDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          receiptDate = picked;
                          (ctx as Element).markNeedsBuild();
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الاستلام *',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          receiptDate != null
                              ? receiptDate!.toIso8601String().substring(0, 10)
                              : 'اختر التاريخ',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // المدعى
                    TextFormField(
                      controller: plaintiffCtrl,
                      decoration: const InputDecoration(labelText: 'المدعى *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    // المدعى عليه
                    TextFormField(
                      controller: defendantCtrl,
                      decoration:
                          const InputDecoration(labelText: 'المدعى عليه *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    // الرأى القانونى
                    StatefulBuilder(
                      builder: (context, setFieldState) {
                        return DropdownButtonFormField<String>(
                          initialValue: legalOpinion?.isEmpty == true
                              ? null
                              : legalOpinion,
                          decoration: const InputDecoration(
                              labelText: 'الرأى القانونى'),
                          items: const [
                            DropdownMenuItem(
                              value: 'اقامة الدعوى / الطعن بموجب صحيفة',
                              child: Text('اقامة الدعوى / الطعن بموجب صحيفة'),
                            ),
                            DropdownMenuItem(
                              value: 'حفظ الملف وعدم اقامة الدعوى / الطعن',
                              child:
                                  Text('حفظ الملف وعدم اقامة الدعوى / الطعن'),
                            ),
                          ],
                          onChanged: (v) {
                            setFieldState(() {
                              legalOpinion = v;
                            });
                            legalOpinionNotifier.value = v;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // الحقول الإضافية عند اختيار اقامة الدعوى
                    ValueListenableBuilder<String?>(
                      valueListenable: legalOpinionNotifier,
                      builder: (context, currentValue, child) {
                        if (currentValue ==
                            'اقامة الدعوى / الطعن بموجب صحيفة') {
                          return Column(
                            children: [
                              // رقم الدعوى بعد القيد
                              TextFormField(
                                controller: caseNumberCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'رقم الدعوى بعد القيد'),
                              ),
                              const SizedBox(height: 12),
                              // سنة الدعوى بعد القيد
                              TextFormField(
                                controller: caseYearCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'سنة الدعوى بعد القيد'),
                              ),
                              const SizedBox(height: 12),
                              // بيانات الدائرة بعد القيد
                              TextFormField(
                                controller: circuitCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'بيانات الدائرة بعد القيد'),
                              ),
                              const SizedBox(height: 12),
                              // أول جلسة محددة لنظرها
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate:
                                        firstSessionDate ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    firstSessionDate = picked;
                                    (ctx as Element).markNeedsBuild();
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'أول جلسة محددة لنظرها',
                                    suffixIcon: Icon(Icons.calendar_today),
                                  ),
                                  child: Text(
                                    firstSessionDate != null
                                        ? firstSessionDate!
                                            .toIso8601String()
                                            .substring(0, 10)
                                        : 'اختر التاريخ',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    // ملاحظات
                    TextFormField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (receiptDate == null) {
                  _showMsg('اختر تاريخ الاستلام', isError: true);
                  return;
                }

                final record = PendingFileRecord(
                  id: existing?.id,
                  fileNumber: fileNumberCtrl.text.trim(),
                  fileYear: fileYearCtrl.text.trim(),
                  receiptDate: receiptDate!,
                  plaintiff: plaintiffCtrl.text.trim(),
                  defendant: defendantCtrl.text.trim(),
                  legalOpinion: legalOpinionNotifier.value ?? '',
                  caseNumberAfterFiling: legalOpinionNotifier.value ==
                          'اقامة الدعوى / الطعن بموجب صحيفة'
                      ? (caseNumberCtrl.text.trim().isNotEmpty
                          ? caseNumberCtrl.text.trim()
                          : null)
                      : null,
                  caseYearAfterFiling: legalOpinionNotifier.value ==
                          'اقامة الدعوى / الطعن بموجب صحيفة'
                      ? (caseYearCtrl.text.trim().isNotEmpty
                          ? caseYearCtrl.text.trim()
                          : null)
                      : null,
                  circuitAfterFiling: legalOpinionNotifier.value ==
                          'اقامة الدعوى / الطعن بموجب صحيفة'
                      ? (circuitCtrl.text.trim().isNotEmpty
                          ? circuitCtrl.text.trim()
                          : null)
                      : null,
                  firstSessionDate: legalOpinionNotifier.value ==
                          'اقامة الدعوى / الطعن بموجب صحيفة'
                      ? firstSessionDate
                      : null,
                  notes: notesCtrl.text.trim().isNotEmpty
                      ? notesCtrl.text.trim()
                      : null,
                );

                try {
                  if (existing == null) {
                    await _service.addPendingFile(record);
                    _showMsg('تمت الإضافة بنجاح');
                  } else {
                    await _service.updatePendingFile(record);
                    _showMsg('تم التحديث بنجاح');
                  }
                  Navigator.pop(ctx);
                  // إعادة تحميل البيانات
                  if (_showAll) {
                    _loadAllFiles();
                  } else {
                    _performSearch();
                  }
                } catch (e) {
                  _showMsg('خطأ: $e', isError: true);
                }
              },
              child: Text(existing == null ? 'إضافة' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFile(PendingFileRecord file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
              'هل تريد حذف ملف رقم ${file.fileNumber} لسنة ${file.fileYear}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await _service.deletePendingFile(file.id!);
        _showMsg('تم الحذف بنجاح');
        setState(() {
          _selected = null;
        });
        // إعادة تحميل البيانات
        if (_showAll) {
          _loadAllFiles();
        } else {
          _performSearch();
        }
      } catch (e) {
        _showMsg('خطأ أثناء الحذف: $e', isError: true);
      }
    }
  }

  void _printReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PendingFilesReportPage(files: _results),
      ),
    );
  }

  DataRow _buildRow(PendingFileRecord file, int index) {
    final theme = Theme.of(context);
    final selected = _selected?.id == file.id;

    return DataRow(
      color: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.primary.withValues(alpha: 0.2);
          }
          return null;
        },
      ),
      selected: selected,
      onSelectChanged: (_) {
        setState(() {
          _selected = file;
        });
      },
      cells: [
        DataCell(Text(index.toString())),
        DataCell(Text(file.fileNumber)),
        DataCell(Text(file.fileYear)),
        DataCell(Text(file.plaintiff)),
        DataCell(Text(file.defendant)),
        DataCell(Text(file.receiptDate.toIso8601String().substring(0, 10))),
        DataCell(Text(file.legalOpinion.isEmpty ? '-' : file.legalOpinion)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 200,
                          child: TextField(
                            controller: _fileNumberController,
                            decoration: const InputDecoration(
                                labelText: 'رقم الملف', isDense: true),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _fileYearController,
                            decoration: const InputDecoration(
                                labelText: 'السنة', isDense: true),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _plaintiffController,
                            decoration: const InputDecoration(
                                labelText: 'المدعى', isDense: true),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _defendantController,
                            decoration: const InputDecoration(
                                labelText: 'المدعى عليه', isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _performSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('بحث'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _loadAllFiles,
                          icon: const Icon(Icons.list),
                          label: const Text('عرض الكل'),
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              _loading ? null : () => _openAddEditDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة ملف تحت الرفع'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _results.isEmpty ? null : _printReport,
                          icon: const Icon(Icons.print),
                          label: const Text('طباعة تقرير'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 1,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? const Center(
                            child: Text('لا توجد نتائج',
                                style: TextStyle(fontSize: 16)))
                        : Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('م')),
                                      DataColumn(label: Text('رقم تحت الرفع')),
                                      DataColumn(label: Text('سنة تحت الرفع')),
                                      DataColumn(label: Text('المدعى')),
                                      DataColumn(label: Text('المدعى عليه')),
                                      DataColumn(label: Text('تاريخ الاستلام')),
                                      DataColumn(label: Text('الرأى القانونى')),
                                    ],
                                    rows: _results
                                        .asMap()
                                        .entries
                                        .map((entry) => _buildRow(
                                            entry.value, entry.key + 1))
                                        .toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    if (_selected != null) ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _openAddEditDialog(
                                            existing: _selected),
                                        icon: const Icon(Icons.edit),
                                        label: const Text('تعديل'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _deleteFile(_selected!),
                                        icon: const Icon(Icons.delete),
                                        label: const Text('حذف'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ] else ...[
                                      ElevatedButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.edit),
                                        label: const Text('تعديل'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
