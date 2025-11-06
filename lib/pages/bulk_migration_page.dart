import 'package:flutter/material.dart';
import '../services/mysql_service.dart';

class BulkMigrationPage extends StatefulWidget {
  const BulkMigrationPage({super.key});

  @override
  State<BulkMigrationPage> createState() => _BulkMigrationPageState();
}

class _BulkMigrationPageState extends State<BulkMigrationPage> {
  DateTime? _sessionDate; // تاريخ الجلسة المطلوب البحث عليه
  CircuitRecord? _selectedCircuit;
  final _service = MySqlService();
  bool _loadingCircuits = false;
  bool _searching = false;
  List<CircuitRecord> _circuits = [];
  List<CaseRecord> _results = [];
  final _decisionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  Future<void> _pickSessionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDate: _sessionDate ?? now,
      builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
    );
    if (picked != null) setState(() => _sessionDate = picked);
  }

  Future<void> _loadCircuits() async {
    setState(() => _loadingCircuits = true);
    try {
      final list = await _service.getCircuits();
      setState(() => _circuits = list);
    } catch (e) {
      _showSnack('فشل تحميل الدوائر: $e');
    } finally {
      if (mounted) setState(() => _loadingCircuits = false);
    }
  }

  Future<void> _search() async {
    if (_sessionDate == null || _selectedCircuit == null) {
      _showSnack('اختر تاريخ الجلسة والدائرة أولاً');
      return;
    }
    setState(() {
      _searching = true;
      _results.clear();
    });
    try {
      final cases = await _service.getCasesBySessionDateAndCircuit(
        sessionDate: _sessionDate!,
        circuit: _selectedCircuit!.name,
      );
      setState(() => _results = cases);
      if (cases.isEmpty) _showSnack('لا توجد قضايا مطابقة');
    } catch (e) {
      _showSnack('فشل البحث: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openBulkMigrateDialog() async {
    if (_results.isEmpty) {
      _showSnack('لا توجد نتائج لترحيلها');
      return;
    }
    // استبعاد القضايا ذات الحكم النهائي قبل المتابعة
    try {
      final ids =
          _results.where((c) => c.id != null).map((c) => c.id!).toList();
      final mapTypes = await _service.getLatestJudgmentTypesForCases(ids);
      final finals = mapTypes.entries
          .where((e) => e.value.trim() == 'حكم نهائي')
          .map((e) => e.key)
          .toSet();
      if (finals.isNotEmpty) {
        setState(() {
          _results = _results.where((c) => !finals.contains(c.id)).toList();
        });
        _showSnack(
            'تم استبعاد ${finals.length} قضية بحكم نهائي ولا يجوز ترحيلها');
        if (_results.isEmpty) return; // بعد التصفية لا شيء
      }
    } catch (e) {
      _showSnack('تعذر فحص الأحكام النهائية: $e');
      return;
    }
    DateTime? newDate;
    final decisionCtrl = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: const Text('ترحيل مجمع للجلسات'),
          content: StatefulBuilder(
            builder: (context, setLocal) => SizedBox(
              width: 500,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'تاريخ الجلسة الجديدة *',
                                border: OutlineInputBorder()),
                            child: Text(
                              newDate == null
                                  ? 'لم يتم التحديد'
                                  : _fmt(newDate),
                              style: TextStyle(
                                color: newDate == null
                                    ? Colors.redAccent
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final p = await showDatePicker(
                              context: context,
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 5),
                              initialDate: newDate ?? now,
                              builder: (context, child) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: child ?? const SizedBox()),
                            );
                            if (p != null) setLocal(() => newDate = p);
                          },
                          icon: const Icon(Icons.date_range),
                          label: const Text('اختر'),
                        )
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: decisionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'القرار الجديد *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () async {
                            if (newDate == null) {
                              _showSnack('تاريخ الجلسة الجديدة مطلوب');
                              return;
                            }
                            final decision = decisionCtrl.text.trim();
                            if (decision.isEmpty) {
                              _showSnack('القرار الجديد مطلوب');
                              return;
                            }
                            Navigator.of(ctx).pop();
                            await _executeBulkMigration(newDate!, decision);
                          },
                          icon: const Icon(Icons.send),
                          label: const Text('ترحيل مجمع'),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء')),
          ],
        ),
      ),
    );
  }

  Future<void> _executeBulkMigration(DateTime newDate, String? decision) async {
    final ids = _results.map((c) => c.id!).toList();
    try {
      final res = await _service.bulkAddSessionForCases(
          caseIds: ids, newDate: newDate, decision: decision);
      _showSnack(
          'تم ترحيل ${res.success}/${res.total}. فشل ${res.failedCaseIds.length}');
      // refresh search to show updated last_session_date mismatch so they disappear unless date matched newDate
      await _search();
    } catch (e) {
      _showSnack('فشل الترحيل المجمع: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // Removed unused _showError helper (kept _showSnack for feedback)

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _decisionCtrl.dispose();
    super.dispose();
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
            const SizedBox(height: 16),
            Expanded(child: _buildResultsCard()),
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
            Text('بحث عن القضايا حسب تاريخ الجلسة والدائرة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 280,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'تاريخ الجلسة',
                        border: OutlineInputBorder()),
                    child: Text(_sessionDate == null
                        ? 'لم يتم التحديد'
                        : _fmt(_sessionDate)),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: FilledButton.icon(
                    onPressed: _pickSessionDate,
                    icon: const Icon(Icons.date_range),
                    label: const Text('اختر'),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: _loadingCircuits
                      ? const LinearProgressIndicator()
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
                SizedBox(
                  width: 140,
                  child: ElevatedButton.icon(
                    onPressed: _searching ? null : _search,
                    icon: const Icon(Icons.search),
                    label: const Text('بحث'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('نتائج البحث (${_results.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_searching)
                  const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('رقم الدعوى')),
                          DataColumn(label: Text('سنة الدعوى')),
                          DataColumn(label: Text('المدعى')),
                          DataColumn(label: Text('المدعى عليه')),
                          DataColumn(label: Text('تاريخ الجلسة')),
                        ],
                        rows: _results
                            .map((c) => DataRow(cells: [
                                  DataCell(Text(c.number)),
                                  DataCell(Text(c.year)),
                                  DataCell(Text(c.plaintiff)),
                                  DataCell(Text(c.defendant)),
                                  DataCell(Text(_fmt(c.lastSessionDate))),
                                ]))
                            .toList(),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _results.isEmpty ? null : _openBulkMigrateDialog,
                icon: const Icon(Icons.fast_forward),
                label: const Text('ترحيل مجمع للقضايا'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
