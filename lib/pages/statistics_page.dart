import 'package:flutter/material.dart';
// (PDF generation moved to statistics_report_page.dart)
import 'statistics_report_page.dart';
import '../services/mysql_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final _service = MySqlService();
  bool _loading = false;
  bool _loadingMore = false; // أثناء تحميل جميع السجلات لاحقاً
  List<CaseRecord> _allCases = [];
  List<CaseRecord> _filtered = [];
  late _CaseDataSource _caseDataSource; // data source for paginated table
  int _rowsPerPage =
      PaginatedDataTable.defaultRowsPerPage; // configurable page size
  int _totalCount = 0; // العدد الكامل للقضايا في قاعدة البيانات
  bool _loadedAll = false; // هل تم تحميل كل القضايا
  static const int _initialLimit =
      200; // عدد السجلات في التحميل الأولي لتخفيف التهنيج
  // أزلنا ScrollController الأفقي لتبسيط الجدول لأن شريط التمرير سبب خطأ hit test عند عدم وجود مساحة

  DateTime? _fromDate; // من تاريخ
  DateTime? _toDate; // إلى تاريخ
  bool _filterDefenseMemos = false; // تقرير مذكرات الدفاع
  bool _filterFinalJudgments = false; // تقرير الأحكام النهائية
  String? _finalJudgmentNatureFilter; // 'صالح' أو 'ضد' لفرز إضافي
  bool _showOnlyFiltered = false; // عرض النتائج المفلترة فقط

  @override
  void initState() {
    super.initState();
    _caseDataSource = _CaseDataSource(const []);
    _loadCases();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() => _loading = true);
    try {
      // اجلب العدد أولاً
      final count = await _service.getCasesCount();
      // اجلب جزء محدود فقط
      final cases = await _service.getCasesLimited(_initialLimit);
      setState(() {
        _totalCount = count;
        _allCases = cases;
        _applyFilters();
        _refreshDataSource();
        _loadedAll = cases.length >=
            count; // لو كل النتائج أقل من أو تساوي الحد إذن حملنا الكل
      });
    } catch (e) {
      _showSnack('تعذر تحميل القضايا: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAllCases() async {
    if (_loadedAll || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final full = await _service.getCases();
      setState(() {
        _allCases = full;
        _applyFilters();
        _refreshDataSource();
        _loadedAll = true;
      });
    } catch (e) {
      _showSnack('تعذر تحميل كل القضايا: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _applyFilters() {
    List<CaseRecord> list = List.from(_allCases);
    // Placeholder filters (since attachments + judgments in separate tables, we will fetch lazily if needed later)
    // 1. Filter Defense Memos by date range on attachments (type == مذكرة دفاع) copy_date within range
    // 2. Filter Final Judgments by existence of final judgment.
    // For now: we simulate by leaving list unchanged and only mark when filter toggles; later can expand with joins.
    // Enhancement: lazy evaluation when filter buttons pressed.
    _filtered = list;
  }

  void _refreshDataSource() {
    final visible = _showOnlyFiltered ? _filtered : _allCases;
    _caseDataSource = _CaseDataSource(visible);
    // Ensure rowsPerPage always one of allowed values (keep previous if valid even if list shorter)
    const allowed = [10, 20, 30, 50];
    if (!allowed.contains(_rowsPerPage)) {
      _rowsPerPage = allowed.first;
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDate: _fromDate ?? now,
      builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
    );
    if (picked != null) setState(() => _fromDate = picked);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDate: _toDate ?? now,
      builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
    );
    if (picked != null) setState(() => _toDate = picked);
  }

  Future<void> _runDefenseMemoReport() async {
    if (_fromDate == null || _toDate == null) {
      _showSnack('اختر من تاريخ وإلى تاريخ أولاً');
      return;
    }
    setState(() => _loading = true);
    try {
      final cases =
          await _service.getCasesWithDefenseMemosBetween(_fromDate!, _toDate!);
      setState(() {
        _filterDefenseMemos = true;
        _filterFinalJudgments = false;
        _showOnlyFiltered = true;
        _filtered = cases;
        _caseDataSource = _CaseDataSource(_filtered);
      });
    } catch (e) {
      _showSnack('فشل تحميل تقرير مذكرات الدفاع: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runFinalJudgmentsReport() async {
    if (_fromDate == null || _toDate == null) {
      _showSnack('اختر من تاريخ وإلى تاريخ أولاً');
      return;
    }
    setState(() => _loading = true);
    try {
      final cases = await _service.getCasesWithFinalJudgmentsBetween(
          _fromDate!, _toDate!);
      setState(() {
        _filterFinalJudgments = true;
        _filterDefenseMemos = false;
        _finalJudgmentNatureFilter = null;
        _showOnlyFiltered = true;
        _filtered = cases;
        _caseDataSource = _CaseDataSource(_filtered);
      });
    } catch (e) {
      _showSnack('فشل تحميل تقرير الأحكام النهائية: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runFinalJudgmentsByNature(String nature) async {
    if (_fromDate == null || _toDate == null) {
      _showSnack('اختر من تاريخ وإلى تاريخ أولاً');
      return;
    }
    setState(() => _loading = true);
    try {
      final cases = await _service.getCasesWithFinalJudgmentsByNatureBetween(
          _fromDate!, _toDate!, nature);
      setState(() {
        _filterFinalJudgments = true;
        _filterDefenseMemos = false;
        _finalJudgmentNatureFilter = nature;
        _showOnlyFiltered = true;
        _filtered = cases;
        _caseDataSource = _CaseDataSource(_filtered);
      });
    } catch (e) {
      _showSnack('فشل تحميل تقرير أحكام $nature: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetFilters() {
    setState(() {
      _filterDefenseMemos = false;
      _filterFinalJudgments = false;
      _showOnlyFiltered = false;
      _applyFilters();
      _refreshDataSource();
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final visibleList = _showOnlyFiltered
        ? _filtered
        : _allCases; // still used for header count
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildCasesCard(visibleList),
                  const SizedBox(height: 16),
                  _buildFilterCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCasesCard(List<CaseRecord> list) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('جميع القضايا',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 12),
                Chip(
                    label: Text(
                        'العدد: ${list.length}${_loadedAll ? '' : ' / $_totalCount'}')),
                const Spacer(),
                if (_showOnlyFiltered &&
                    (_filterDefenseMemos || _filterFinalJudgments))
                  Tooltip(
                    message: 'طباعة الإحصائية الحالية',
                    child: FilledButton.icon(
                      onPressed: _printStatisticsReport,
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة الإحصائية'),
                    ),
                  ),
                if (!_loadedAll && !_loadingMore)
                  TextButton.icon(
                    onPressed: _loadAllCases,
                    icon: const Icon(Icons.download),
                    label: const Text('تحميل الكل'),
                  ),
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (_loading)
                  const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                if (!_loading)
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: _loadCases,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const SizedBox(
                  height: 80, child: Center(child: Text('لا توجد قضايا')))
            else
              // أستخدم PaginatedDataTable لتقليل إنشاء كل الصفوف دفعة واحدة
              LayoutBuilder(
                builder: (context, constraints) {
                  final table = PaginatedDataTable(
                    header: const Text('جدول القضايا (صفحات)'),
                    showCheckboxColumn: false,
                    rowsPerPage: _rowsPerPage,
                    onRowsPerPageChanged: (val) {
                      if (val != null) {
                        setState(() => _rowsPerPage = val);
                      }
                    },
                    availableRowsPerPage: () {
                      const base = [10, 20, 30, 50];
                      final visibleCount = list.length;
                      if (visibleCount <= 0) return base;
                      final filtered =
                          base.where((v) => v <= visibleCount).toList();
                      return filtered.isEmpty ? [base.first] : filtered;
                    }(),
                    columns: const [
                      DataColumn(label: Text('رقم الدعوى')),
                      DataColumn(label: Text('سنة الدعوى')),
                      DataColumn(label: Text('المدعى')),
                      DataColumn(label: Text('المدعى عليه')),
                      DataColumn(label: Text('تاريخ اخر جلسة')),
                    ],
                    source: _caseDataSource,
                  );
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      maxWidth: constraints.maxWidth,
                    ),
                    child: table,
                  );
                },
              ),
            if (_filterDefenseMemos || _filterFinalJudgments) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('إلغاء التصفية'),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _printStatisticsReport() async {
    if (_filtered.isEmpty) {
      _showSnack('لا توجد نتائج للطباعة');
      return;
    }
    if (!mounted) return;
    final type = _filterDefenseMemos
        ? StatisticsReportType.defenseMemos
        : StatisticsReportType.finalJudgments;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatisticsReportPage(
          type: type,
          fromDate: _fromDate!,
          toDate: _toDate!,
          cases: _filtered,
          nature: _finalJudgmentNatureFilter,
        ),
      ),
    );
  }

  // placeholder import trigger
  void importForStatisticsPrinting() {}

  // تم استبدال توليد الـ PDF الفردي بصفحة عرض منفصلة

  Widget _buildFilterCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تخصيص البحث (الفترة التفتيشية)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 250,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'من تاريخ', border: OutlineInputBorder()),
                    child: Text(
                        _fromDate == null ? 'لم يتم التحديد' : _fmt(_fromDate)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: const Text('اختر'),
                ),
                SizedBox(
                  width: 250,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'إلى تاريخ', border: OutlineInputBorder()),
                    child: Text(
                        _toDate == null ? 'لم يتم التحديد' : _fmt(_toDate)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.date_range),
                  label: const Text('اختر'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: (_fromDate != null && _toDate != null)
                      ? _runDefenseMemoReport
                      : null,
                  icon: const Icon(Icons.description),
                  label: const Text('تقرير بمذكرات الدفاع خلال الفترة'),
                ),
                ElevatedButton.icon(
                  onPressed: (_fromDate != null && _toDate != null)
                      ? _runFinalJudgmentsReport
                      : null,
                  icon: const Icon(Icons.gavel),
                  label: const Text('تقرير بالأحكام النهائية'),
                ),
                ElevatedButton.icon(
                  onPressed: (_fromDate != null && _toDate != null)
                      ? () => _runFinalJudgmentsByNature('صالح')
                      : null,
                  icon: const Icon(Icons.thumb_up_alt),
                  label: const Text('تقرير بأحكام الصالح'),
                ),
                ElevatedButton.icon(
                  onPressed: (_fromDate != null && _toDate != null)
                      ? () => _runFinalJudgmentsByNature('ضد')
                      : null,
                  icon: const Icon(Icons.thumb_down_alt),
                  label: const Text('تقرير بأحكام الضد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

// مصدر البيانات المصفح (يحسّن الأداء بعدم بناء كل الصفوف مرة واحدة)
class _CaseDataSource extends DataTableSource {
  final List<CaseRecord> _cases;
  _CaseDataSource(this._cases);

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _cases.length) return null;
    final c = _cases[index];
    return DataRow.byIndex(index: index, cells: [
      DataCell(Text(c.number)),
      DataCell(Text(c.year)),
      DataCell(Text(c.plaintiff)),
      DataCell(Text(c.defendant)),
      DataCell(Text(_fmt(c.lastSessionDate))),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _cases.length;

  @override
  int get selectedRowCount => 0;
}
