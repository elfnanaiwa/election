import 'package:flutter/material.dart';
import '../services/mysql_service.dart';

// صفحة ملفات الشعبة (تصميم مبدئي – ربط قاعدة البيانات الفعلي لنقل/إرجاع القضايا يتم لاحقاً)
class DepartmentPage extends StatefulWidget {
  const DepartmentPage({super.key});

  @override
  State<DepartmentPage> createState() => _DepartmentPageState();
}

class _DepartmentPageState extends State<DepartmentPage> {
  final _numberCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _plaintiffCtrl = TextEditingController();
  final _defendantCtrl = TextEditingController();
  CircuitRecord? _selectedCircuit;

  final _service = MySqlService();

  bool _loading = false;
  bool _circuitsLoading = false;
  List<CircuitRecord> _circuits = [];

  // ملفات الشعبة (حالياً قائمة داخلية مؤقتة، لاحقاً يتم جلبها من جدول مستقل في قاعدة البيانات)
  List<CaseRecord> _departmentFiles = [];
  List<CaseRecord> _filtered = [];
  CaseRecord? _selectedCase;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _yearCtrl.dispose();
    _plaintiffCtrl.dispose();
    _defendantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _circuitsLoading = true;
    });
    try {
      final cir = await _service.getCircuits();
      final cases = await _service.getReservedCasesForDepartment();
      setState(() {
        _circuits = cir;
        _departmentFiles = cases;
        _filtered = List.from(_departmentFiles);
      });
    } catch (e) {
      _showMsg('فشل التحميل: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _circuitsLoading = false;
        });
      }
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _performSearch() async {
    final number = _numberCtrl.text.trim();
    final year = _yearCtrl.text.trim();
    final p = _plaintiffCtrl.text.trim();
    final d = _defendantCtrl.text.trim();
    final circuitName = _selectedCircuit?.name.trim();

    setState(() => _loading = true);
    try {
      final data = await _service.getReservedCasesForDepartment(
        number: (number.isNotEmpty && year.isNotEmpty) ? number : null,
        year: (number.isNotEmpty && year.isNotEmpty) ? year : null,
        plaintiff: p.isNotEmpty ? p : null,
        defendant: d.isNotEmpty ? d : null,
        circuit:
            circuitName != null && circuitName.isNotEmpty ? circuitName : null,
      );
      setState(() {
        _departmentFiles = data;
        _filtered = data;
        _selectedCase = null;
      });
    } catch (e) {
      _showMsg('فشل البحث: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetToPleadings() async {
    if (_selectedCase == null) return;
    final c = _selectedCase!;

    CircuitRecord? pickedCircuit;
    DateTime? nextDate = DateTime.now();
    final decisionCtrl = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              scrollable: true,
              title: const Text('إعادة الدعوى إلى المرافعة'),
              content: SizedBox(
                width: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // بيانات القضية
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'رقم الدعوى',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(c.number),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'سنة الدعوى',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(c.year),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'المدعى',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(c.plaintiff),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'المدعى عليه',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(c.defendant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // اختيار الدائرة الجديدة
                    DropdownButtonFormField<CircuitRecord>(
                      isExpanded: true,
                      initialValue: pickedCircuit,
                      items: _circuits
                          .map((ci) => DropdownMenuItem(
                                value: ci,
                                child: Text(ci.name),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setLocal(() => pickedCircuit = v),
                      decoration: const InputDecoration(
                        labelText: 'ترحيل إلى الدائرة *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (pickedCircuit != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.grey.shade50,
                        ),
                        child: Text(
                          'الدائرة ${pickedCircuit!.name} | رقم: ${pickedCircuit!.number} | اليوم: ${pickedCircuit!.meetingDay} | الموعد: ${pickedCircuit!.meetingTime}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // اختيار تاريخ الجلسة القادمة (مسموح بأي تاريخ)
                    FormField<DateTime?>(
                      initialValue: nextDate,
                      validator: (v) => v == null ? 'تاريخ الجلسة مطلوب' : null,
                      builder: (state) => Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'تاريخ الجلسة القادمة',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                errorText: state.errorText,
                              ),
                              child: Text(nextDate == null
                                  ? 'لم يتم التحديد'
                                  : nextDate!
                                      .toIso8601String()
                                      .substring(0, 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final now = DateTime.now();
                                      final p = await showDatePicker(
                                        context: ctx,
                                        firstDate: DateTime(now.year - 50),
                                        lastDate: DateTime(now.year + 5),
                                        initialDate: nextDate ?? now,
                                        builder: (c, ch) => Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: ch ?? const SizedBox(),
                                        ),
                                      );
                                      if (p != null) {
                                        setLocal(() => nextDate = p);
                                        state.didChange(p);
                                      }
                                    },
                              icon: const Icon(Icons.date_range),
                              label: const Text('اختر'))
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: decisionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'قرار الجلسة الجديدة *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (pickedCircuit == null) {
                            _showMsg('اختر الدائرة');
                            return;
                          }
                          if (nextDate == null) {
                            _showMsg('اختر تاريخ الجلسة');
                            return;
                          }
                          if (decisionCtrl.text.trim().isEmpty) {
                            _showMsg('أدخل قرار الجلسة');
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            await _service.repleadCaseToCircuit(
                              caseId: c.id!,
                              circuitName: pickedCircuit!.name,
                              sessionDate: nextDate!,
                              decision: decisionCtrl.text.trim(),
                            );
                            // Ensure the dialog context is still mounted before using it
                            if (!ctx.mounted) {
                              setLocal(() => saving = false);
                              return;
                            }
                            Navigator.of(ctx).pop();
                            // Ensure the page context is still mounted before continuing
                            if (!mounted) return;
                            await _performSearch();
                            _showMsg(
                                'تمت إعادة الدعوى إلى المرافعة وترحيلها إلى الدائرة المحددة');
                          } catch (e) {
                            _showMsg('خطأ: $e');
                            setLocal(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ وترحيل'),
                ),
              ],
            );
          },
        ),
      ),
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
            _buildSearchCard(),
            const SizedBox(height: 14),
            Expanded(child: _buildFilesCard()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('البحث في ملفات الشعبة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, cons) {
              final isWide = cons.maxWidth > 900;
              final w = isWide ? (cons.maxWidth - 40) / 3 : cons.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                      width: w,
                      child: _outlinedField('رقم الدعوى', _numberCtrl)),
                  SizedBox(
                      width: w,
                      child: _outlinedField('سنة الدعوى', _yearCtrl,
                          keyboardType: TextInputType.number)),
                  SizedBox(
                      width: w,
                      child: _outlinedField('المدعى', _plaintiffCtrl)),
                  SizedBox(
                      width: w,
                      child: _outlinedField('المدعى عليه', _defendantCtrl)),
                  SizedBox(
                    width: w,
                    child: _circuitsLoading
                        ? const Center(child: LinearProgressIndicator())
                        : DropdownButtonFormField<CircuitRecord>(
                            initialValue: _selectedCircuit,
                            decoration: const InputDecoration(
                                labelText: 'الدائرة',
                                border: OutlineInputBorder()),
                            items: _circuits
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c.name),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedCircuit = v),
                          ),
                  ),
                  if (_selectedCircuit != null)
                    SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.grey.shade50,
                        ),
                        child: Text(
                          'الدائرة ${_selectedCircuit!.name} | رقم: ${_selectedCircuit!.number} | اليوم: ${_selectedCircuit!.meetingDay} | الساعة: ${_selectedCircuit!.meetingTime}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _numberCtrl.clear();
                            _yearCtrl.clear();
                            _plaintiffCtrl.clear();
                            _defendantCtrl.clear();
                            _selectedCircuit = null;
                          });
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('استعادة خانات البحث'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _performSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('بحث في ملفات الشعبة'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFilesCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('ملفات الشعبة',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('لا توجد ملفات في الشعبة حالياً'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('رقم الدعوى')),
                          DataColumn(label: Text('سنة الدعوى')),
                          DataColumn(label: Text('المدعى')),
                          DataColumn(label: Text('المدعى عليه')),
                          DataColumn(label: Text('تاريخ آخر جلسة')),
                        ],
                        rows: _filtered.map((c) {
                          final selected = _selectedCase?.id == c.id;
                          return DataRow(
                            selected: selected,
                            onSelectChanged: (_) {
                              setState(() => _selectedCase = c);
                            },
                            cells: [
                              DataCell(Text(c.number)),
                              DataCell(Text(c.year)),
                              DataCell(Text(c.plaintiff)),
                              DataCell(Text(c.defendant)),
                              DataCell(Text(c.lastSessionDate == null
                                  ? '-'
                                  : c.lastSessionDate!
                                      .toIso8601String()
                                      .substring(0, 10))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _selectedCase == null ? null : _resetToPleadings,
                icon: const Icon(Icons.undo),
                label: const Text('إعادة الدعوى إلى المرافعة'),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _outlinedField(String label, TextEditingController c,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
