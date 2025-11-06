import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import '../services/mysql_service.dart';
import 'case_roll_report_page.dart';
import 'agenda_session_report_page.dart';

class CaseDetailsPage extends StatefulWidget {
  final int? openTransferForCaseId;
  const CaseDetailsPage({super.key, this.openTransferForCaseId});
  @override
  State<CaseDetailsPage> createState() => _CaseDetailsPageState();
}

class _CaseDetailsPageState extends State<CaseDetailsPage> {
  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  final _numberCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _plaintiffCtrl = TextEditingController();
  final _defendantCtrl = TextEditingController();
  final _circuitCtrl = TextEditingController();
  final _decisionCtrl = TextEditingController();

  DateTime? _firstSessionDate;

  final List<_CaseRow> _cases = [];
  int? _selectedCaseId;

  List<CircuitRecord> _circuits = [];
  int? _selectedCircuitId;

  @override
  void initState() {
    super.initState();
    _initAndMaybeOpen();
  }

  Future<void> _initAndMaybeOpen() async {
    await _loadCircuits();
    await _loadCases();
    final targetId = widget.openTransferForCaseId;
    if (targetId != null && mounted) {
      if (_cases.any((c) => c.id == targetId)) {
        setState(() => _selectedCaseId = targetId);
        // Open transfer dialog
        await _transferSessionDialog();
      }
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _numberCtrl.dispose();
    _yearCtrl.dispose();
    _plaintiffCtrl.dispose();
    _defendantCtrl.dispose();
    _circuitCtrl.dispose();
    _decisionCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? theme.colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _sessionStatus(DateTime? d) {
    if (d == null) return '-';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff < 0) return 'انتهت';
    if (diff == 0) return 'اليوم';
    return 'متبقي $diff يوم';
  }

  String _casesCountLabel(int n) {
    if (n == 0) return 'لا قضايا';
    if (n == 1) return 'قضية واحدة';
    if (n == 2) return 'قضيتان';
    if (n <= 10) return '$n قضايا';
    return '$n قضية';
  }

  Future<void> _loadCircuits() async {
    try {
      final list = await MySqlService().getCircuits();
      if (!mounted) return;
      setState(() => _circuits = list);
    } catch (_) {}
  }

  Future<void> _loadCases() async {
    try {
      final list = await MySqlService().getCases();
      if (!mounted) return;
      setState(() {
        _cases
          ..clear()
          ..addAll(list.map((e) => _CaseRow(
                id: e.id,
                tradedNumber: e.tradedNumber,
                rollNumber: e.rollNumber,
                number: e.number,
                year: e.year,
                circuit: e.circuit,
                plaintiff: e.plaintiff,
                defendant: e.defendant,
                decision: e.decision,
                lastSessionDate: e.lastSessionDate,
                prevSessionDate: e.prevSessionDate,
                subject: e.subject,
              )));
        // ترتيب حسب أقدم تاريخ جلسة أولاً، مع وضع غير المحدد في الأسفل
        _cases.sort((a, b) {
          final da = a.lastSessionDate;
          final db = b.lastSessionDate;
          if (da == null && db == null) return (a.id ?? 0).compareTo(b.id ?? 0);
          if (da == null) return 1; // غير محدد في الأسفل
          if (db == null) return -1;
          final c = da.compareTo(db);
          return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
        });
        if (_selectedCaseId != null &&
            !_cases.any((c) => c.id == _selectedCaseId)) {
          _selectedCaseId = null;
        }
      });
    } catch (e) {
      _snack('تعذر تحميل القضايا: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildSearchAddCard(),
          const SizedBox(height: 16),
          _buildCasesCard(),
        ],
      ),
    );
  }

  Widget _buildSearchAddCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('خيارات الإضافة والبحث',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final w =
                  wide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: w, child: _field('رقم القضية', _numberCtrl)),
                  SizedBox(width: w, child: _field('سنة القضية', _yearCtrl)),
                  SizedBox(
                    width: w,
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedCircuitId,
                      items: _circuits
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedCircuitId = v;
                          final sel = (v == null)
                              ? null
                              : _circuits.firstWhere(
                                  (c) => c.id == v,
                                  orElse: () => CircuitRecord(
                                      id: null,
                                      name: '',
                                      number: '',
                                      meetingDay: '',
                                      meetingTime: ''),
                                );
                          _circuitCtrl.text = sel?.name ?? '';
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'الدائرة',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_selectedCircuitId != null)
                    SizedBox(
                      width: w,
                      child: Builder(builder: (context) {
                        final c = _circuits.firstWhere(
                          (cc) => cc.id == _selectedCircuitId,
                          orElse: () => CircuitRecord(
                              id: null,
                              name: '',
                              number: '',
                              meetingDay: '',
                              meetingTime: ''),
                        );
                        final number = c.number.isEmpty ? '-' : c.number;
                        final day = c.meetingDay.isEmpty ? '-' : c.meetingDay;
                        final time =
                            c.meetingTime.isEmpty ? '-' : c.meetingTime;
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(top: 4),
                          child: Text(
                            'الدائرة: رقم $number | يوم $day | موعد $time',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        );
                      }),
                    ),
                  SizedBox(width: w, child: _field('المدعى', _plaintiffCtrl)),
                  SizedBox(
                      width: w, child: _field('المدعى عليه', _defendantCtrl)),
                  SizedBox(width: w, child: _field('القرار', _decisionCtrl)),
                  SizedBox(
                    width: w,
                    child: Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'تاريخ الجلسة',
                                border: OutlineInputBorder()),
                            child: Text(_firstSessionDate == null
                                ? 'لم يتم التحديد'
                                : _fmt(_firstSessionDate)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _pickFirstSessionDate,
                          icon: const Icon(Icons.date_range),
                          label: const Text('اختر'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _addCaseDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة قضية جديدة'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                  label: const Text('بحث في الأجندة'),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'تحديث الدوائر',
                  onPressed: _resetSearchAndCircuits,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCasesCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('بيانات القضايا', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openStruckOffRegister,
                  icon: const Icon(Icons.backup_table_outlined),
                  label: const Text('سجل بيانات القضايا المشطوبة'),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.countertops, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _casesCountLabel(_cases.length),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 400,
              child: Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  child: Scrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('مسلسل')),
                          DataColumn(label: Text('تاريخ آخر جلسة')),
                          DataColumn(label: Text('رقم الدعوى')),
                          DataColumn(label: Text('سنة الدعوى')),
                          DataColumn(label: Text('الدائرة')),
                          DataColumn(label: Text('المدعى')),
                          DataColumn(label: Text('المدعى عليه')),
                          DataColumn(label: Text('الجلسة السابقة')),
                          DataColumn(label: Text('القرار')),
                        ],
                        rows: List.generate(_cases.length, (i) {
                          final c = _cases[i];
                          final sel = c.id != null && c.id == _selectedCaseId;
                          return DataRow(
                            selected: sel,
                            onSelectChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedCaseId = c.id;
                                } else if (_selectedCaseId == c.id) {
                                  _selectedCaseId = null;
                                }
                              });
                              // (تمت إزالة استدعاء دالة غير معرفة _finalJudgmentCheck)
                            },
                            cells: [
                              DataCell(Text('${i + 1}')),
                              DataCell(Text(_fmt(c.lastSessionDate))),
                              DataCell(Text(c.number)),
                              DataCell(Text(c.year)),
                              DataCell(Text(c.circuit)),
                              DataCell(Text(c.plaintiff)),
                              DataCell(Text(c.defendant)),
                              DataCell(Text(_fmt(c.prevSessionDate))),
                              DataCell(Text(c.decision)),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                    onPressed: _selectedCaseId == null ? null : _reserve,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text(' حجز للتقرير')),
                OutlinedButton.icon(
                    onPressed: _selectedCaseId == null ? null : _editCaseDialog,
                    icon: const Icon(Icons.edit),
                    label: const Text('تعديل')),
                OutlinedButton.icon(
                    onPressed: _selectedCaseId == null ? null : _deleteCase,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف')),
                OutlinedButton.icon(
                    onPressed:
                        _selectedCaseId == null ? null : _attachmentsDialog,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('مرفقات')),
                OutlinedButton.icon(
                    onPressed:
                        _selectedCaseId == null ? null : _transferSessionDialog,
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('ترحيل')),
                OutlinedButton.icon(
                  onPressed: _selectedCaseId == null
                      ? null
                      : _openCorrespondenceDialog,
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('خطابات واستعجالات'),
                ),
                OutlinedButton.icon(
                  onPressed: _openAgendaSessionReport,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة جلسة الأجندة'),
                ),
                OutlinedButton.icon(
                  onPressed: _openRollReport,
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة الرول'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== Search / reset =====
  void _resetSearchAndCircuits() async {
    setState(() {
      _numberCtrl.clear();
      _yearCtrl.clear();
      _plaintiffCtrl.clear();
      _defendantCtrl.clear();
      _circuitCtrl.clear();
      _decisionCtrl.clear();
      _firstSessionDate = null;
      _selectedCircuitId = null;
      _cases.clear();
      _selectedCaseId = null;
    });
    await _loadCircuits();
    await _loadCases();
    _snack('تمت تهيئة حقول البحث');
  }

  Future<void> _pickFirstSessionDate() async {
    final now = DateTime.now();
    final p = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDate: _firstSessionDate ?? now,
      builder: (c, ch) => Directionality(
        textDirection: TextDirection.rtl,
        child: ch ?? const SizedBox(),
      ),
    );
    if (p != null) setState(() => _firstSessionDate = p);
  }

  Future<void> _search() async {
    final n = _numberCtrl.text.trim();
    final y = _yearCtrl.text.trim();
    final pl = _plaintiffCtrl.text.trim();
    final df = _defendantCtrl.text.trim();
    final cir = _circuitCtrl.text.trim();
    final dc = _decisionCtrl.text.trim();
    final sd = _firstSessionDate;
    final pair = n.isNotEmpty && y.isNotEmpty;
    final other = [pl, df, cir, dc].any((v) => v.isNotEmpty) || sd != null;
    if (!pair && !other) {
      _snack('أدخل (رقم وسنة) أو أي حقل آخر للبحث');
      return;
    }
    try {
      final res = await MySqlService().searchCases(
        number: pair ? n : null,
        year: pair ? y : null,
        plaintiff: pl.isNotEmpty ? pl : null,
        defendant: df.isNotEmpty ? df : null,
        circuit: cir.isNotEmpty ? cir : null,
        decision: dc.isNotEmpty ? dc : null,
        sessionDate: sd,
      );
      if (!mounted) return;
      setState(() {
        _cases
          ..clear()
          ..addAll(res.map((e) => _CaseRow(
                id: e.id,
                tradedNumber: e.tradedNumber,
                rollNumber: e.rollNumber,
                number: e.number,
                year: e.year,
                circuit: e.circuit,
                plaintiff: e.plaintiff,
                defendant: e.defendant,
                decision: e.decision,
                lastSessionDate: e.lastSessionDate,
                prevSessionDate: e.prevSessionDate,
              )));
        // ترتيب حسب أقدم تاريخ جلسة أولاً، مع وضع غير المحدد في الأسفل
        _cases.sort((a, b) {
          final da = a.lastSessionDate;
          final db = b.lastSessionDate;
          if (da == null && db == null) return (a.id ?? 0).compareTo(b.id ?? 0);
          if (da == null) return 1; // غير محدد في الأسفل
          if (db == null) return -1;
          final c = da.compareTo(db);
          return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
        });
        if (_selectedCaseId != null &&
            !_cases.any((c) => c.id == _selectedCaseId)) {
          _selectedCaseId = null;
        }
      });
      if (_cases.isEmpty) _snack('لا نتائج');
    } catch (e) {
      _snack('فشل البحث: $e');
    }
  }

  // ===== Add/Edit/Delete/Reserve =====
  Future<void> _addCaseDialog() async {
    final formKey = GlobalKey<FormState>();
    String tradedNumber = '';
    String rollNumber = '';
    String number = _numberCtrl.text.trim();
    String year = _yearCtrl.text.trim();
    String plaintiff = _plaintiffCtrl.text.trim();
    String defendant = _defendantCtrl.text.trim();
    String decision = _decisionCtrl.text.trim();
    String subject = '';
    int? selectedCircuitId = _selectedCircuitId;
    DateTime? firstSession = _firstSessionDate;

    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Widget circuitDetails() {
                if (selectedCircuitId == null) return const SizedBox.shrink();
                final c = _circuits.firstWhere(
                  (cc) => cc.id == selectedCircuitId,
                  orElse: () => CircuitRecord(
                      id: null,
                      name: '',
                      number: '-',
                      meetingDay: '-',
                      meetingTime: '-'),
                );
                final numberTxt = c.number.isEmpty ? '-' : c.number;
                final dayTxt = c.meetingDay.isEmpty ? '-' : c.meetingDay;
                final timeTxt = c.meetingTime.isEmpty ? '-' : c.meetingTime;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6),
                  child: Text(
                    'رقم الدائرة: $numberTxt | يوم الانعقاد: $dayTxt | موعد الانعقاد: $timeTxt',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('إضافة قضية جديدة'),
                content: SizedBox(
                  width: 520,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Optional fields first: traded and roll numbers
                          TextFormField(
                            initialValue: tradedNumber,
                            decoration: const InputDecoration(
                              labelText: 'رقم المتداول (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => tradedNumber = v.trim(),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: rollNumber,
                            decoration: const InputDecoration(
                              labelText: 'رقم الرول (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => rollNumber = v.trim(),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: number,
                            decoration: const InputDecoration(
                              labelText: 'رقم القضية',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => number = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: year,
                            decoration: const InputDecoration(
                              labelText: 'سنة القضية',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => year = v.trim(),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'الحقل مطلوب';
                              }
                              final t = v.trim();
                              if (t.length > 4 || int.tryParse(t) == null) {
                                return 'أدخل سنة صحيحة';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            initialValue: selectedCircuitId,
                            items: _circuits
                                .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) => setLocal(() => selectedCircuitId = v),
                            decoration: const InputDecoration(
                              labelText: 'الدائرة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null ? 'الحقل مطلوب' : null,
                          ),
                          circuitDetails(),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: plaintiff,
                            decoration: const InputDecoration(
                              labelText: 'المدعى',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => plaintiff = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: defendant,
                            decoration: const InputDecoration(
                              labelText: 'المدعى عليه',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => defendant = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: decision,
                            decoration: const InputDecoration(
                              labelText: 'القرار',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => decision = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          FormField<DateTime?>(
                            initialValue: firstSession,
                            validator: (v) => v == null ? 'الحقل مطلوب' : null,
                            builder: (state) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'تاريخ آخر جلسة',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        errorText: state.errorText,
                                      ),
                                      child: Text(firstSession == null
                                          ? 'لم يتم التحديد'
                                          : _fmt(firstSession)),
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
                                              firstDate: DateTime(now.year - 5),
                                              lastDate: DateTime(now.year + 5),
                                              initialDate: firstSession ?? now,
                                              builder: (c, ch) =>
                                                  Directionality(
                                                textDirection:
                                                    TextDirection.rtl,
                                                child: ch ?? const SizedBox(),
                                              ),
                                            );
                                            if (p != null) {
                                              setLocal(() => firstSession = p);
                                              state.didChange(p);
                                            }
                                          },
                                    icon: const Icon(Icons.date_range),
                                    label: const Text('اختر'),
                                  )
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: subject,
                            decoration: const InputDecoration(
                              labelText: 'موضوع الدعوى (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                            onChanged: (v) => subject = v.trim(),
                          ),
                        ],
                      ),
                    ),
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
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            setLocal(() => saving = true);
                            try {
                              final circuitName = selectedCircuitId == null
                                  ? ''
                                  : (_circuits
                                      .firstWhere(
                                          (c) => c.id == selectedCircuitId,
                                          orElse: () => CircuitRecord(
                                              id: null,
                                              name: '',
                                              number: '',
                                              meetingDay: '',
                                              meetingTime: ''))
                                      .name);

                              // فحص التكرار قبل الإضافة
                              final exists = await MySqlService().caseExists(
                                number: number,
                                year: year,
                                circuit: circuitName,
                              );

                              if (exists) {
                                setLocal(() => saving = false);
                                if (!mounted) return;
                                await showDialog(
                                  context: ctx,
                                  builder: (alertCtx) => Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: AlertDialog(
                                      title: const Text('تنبيه'),
                                      content: const Text(
                                          'القضية تم تسجيلها مسبقاً\n\nيوجد قضية بنفس رقم الدعوى وسنة الدعوى والدائرة.'),
                                      actions: [
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(alertCtx).pop(),
                                          child: const Text('حسناً'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                return;
                              }

                              final rec = CaseRecord(
                                tradedNumber:
                                    tradedNumber.isEmpty ? null : tradedNumber,
                                rollNumber:
                                    rollNumber.isEmpty ? null : rollNumber,
                                number: number,
                                year: year,
                                circuit: circuitName,
                                plaintiff: plaintiff,
                                defendant: defendant,
                                decision: decision,
                                lastSessionDate: firstSession,
                                subject: subject.isEmpty ? null : subject,
                              );
                              final navigator = Navigator.of(ctx);
                              final newId =
                                  await MySqlService().createCase(rec);
                              if (!mounted) return;
                              navigator.pop();
                              if (!mounted) return;
                              setState(() =>
                                  _selectedCaseId = newId > 0 ? newId : null);
                              await _loadCases();
                              _snack('تمت إضافة القضية بنجاح');
                            } catch (e) {
                              setLocal(() => saving = false);
                              if (mounted) {
                                _snack('فشل إضافة القضية: $e', isError: true);
                              }
                            }
                          },
                    icon: const Icon(Icons.save),
                    label: saving
                        ? const Text('جارٍ الحفظ...')
                        : const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editCaseDialog() async {
    if (_selectedCaseId == null) {
      _snack('اختر قضية من الجدول أولاً', isError: true);
      return;
    }
    // منع التعديل على القضايا ذات الحكم النهائي
    try {
      final types = await MySqlService()
          .getLatestJudgmentTypesForCases([_selectedCaseId!]);
      final jt = types[_selectedCaseId!];
      if (jt != null && jt.trim() == 'حكم نهائي') {
        await _showError(
            'القضية المحددة صدر فيها حكم نهائى ولا يمكن التعديل عليها');
        return;
      }
    } catch (_) {}
    final row = _cases.firstWhere((c) => c.id == _selectedCaseId);
    final formKey = GlobalKey<FormState>();
    String tradedNumber = row.tradedNumber ?? '';
    String rollNumber = row.rollNumber ?? '';
    String number = row.number;
    String year = row.year;
    String plaintiff = row.plaintiff;
    String defendant = row.defendant;
    String decision = row.decision;
    String subject = row.subject ?? '';
    // تطابق الدائرة بالاسم إلى id إن وجد
    int? selectedCircuitId = _circuits
        .firstWhere((c) => c.name == row.circuit,
            orElse: () => CircuitRecord(
                id: null,
                name: '',
                number: '',
                meetingDay: '',
                meetingTime: ''))
        .id;
    DateTime? firstSession = row.lastSessionDate;

    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Widget circuitDetails() {
                if (selectedCircuitId == null) return const SizedBox.shrink();
                final c = _circuits.firstWhere(
                  (cc) => cc.id == selectedCircuitId,
                  orElse: () => CircuitRecord(
                      id: null,
                      name: '',
                      number: '-',
                      meetingDay: '-',
                      meetingTime: '-'),
                );
                final numberTxt = c.number.isEmpty ? '-' : c.number;
                final dayTxt = c.meetingDay.isEmpty ? '-' : c.meetingDay;
                final timeTxt = c.meetingTime.isEmpty ? '-' : c.meetingTime;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6),
                  child: Text(
                    'رقم الدائرة: $numberTxt | يوم الانعقاد: $dayTxt | موعد الانعقاد: $timeTxt',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('تعديل قضية'),
                content: SizedBox(
                  width: 520,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            initialValue: tradedNumber,
                            decoration: const InputDecoration(
                              labelText: 'رقم المتداول (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => tradedNumber = v.trim(),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: rollNumber,
                            decoration: const InputDecoration(
                              labelText: 'رقم الرول (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => rollNumber = v.trim(),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: number,
                            decoration: const InputDecoration(
                              labelText: 'رقم القضية',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => number = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: year,
                            decoration: const InputDecoration(
                              labelText: 'سنة القضية',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => year = v.trim(),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'الحقل مطلوب';
                              }
                              final t = v.trim();
                              if (t.length > 4 || int.tryParse(t) == null) {
                                return 'أدخل سنة صحيحة';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            initialValue: selectedCircuitId,
                            items: _circuits
                                .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) => setLocal(() => selectedCircuitId = v),
                            decoration: const InputDecoration(
                              labelText: 'الدائرة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null ? 'الحقل مطلوب' : null,
                          ),
                          circuitDetails(),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: plaintiff,
                            decoration: const InputDecoration(
                              labelText: 'المدعى',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => plaintiff = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: defendant,
                            decoration: const InputDecoration(
                              labelText: 'المدعى عليه',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => defendant = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: decision,
                            decoration: const InputDecoration(
                              labelText: 'القرار',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => decision = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'الحقل مطلوب'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          FormField<DateTime?>(
                            initialValue: firstSession,
                            validator: (v) => v == null ? 'الحقل مطلوب' : null,
                            builder: (state) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'تاريخ الجلسة',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        errorText: state.errorText,
                                      ),
                                      child: Text(firstSession == null
                                          ? 'لم يتم التحديد'
                                          : _fmt(firstSession)),
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
                                              firstDate: DateTime(now.year - 5),
                                              lastDate: DateTime(now.year + 5),
                                              initialDate: firstSession ?? now,
                                              builder: (c, ch) =>
                                                  Directionality(
                                                textDirection:
                                                    TextDirection.rtl,
                                                child: ch ?? const SizedBox(),
                                              ),
                                            );
                                            if (p != null) {
                                              setLocal(() => firstSession = p);
                                              state.didChange(p);
                                            }
                                          },
                                    icon: const Icon(Icons.date_range),
                                    label: const Text('اختر'),
                                  )
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          // موضوع الدعوى (اختياري) — تحت تاريخ أول جلسة
                          TextFormField(
                            initialValue: subject,
                            decoration: const InputDecoration(
                              labelText: 'موضوع الدعوى (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            maxLines: 3,
                            onChanged: (v) => subject = v.trim(),
                          ),
                        ],
                      ),
                    ),
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
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            setLocal(() => saving = true);
                            try {
                              final circuitName = selectedCircuitId == null
                                  ? ''
                                  : (_circuits
                                      .firstWhere(
                                          (c) => c.id == selectedCircuitId,
                                          orElse: () => CircuitRecord(
                                              id: null,
                                              name: '',
                                              number: '',
                                              meetingDay: '',
                                              meetingTime: ''))
                                      .name);
                              final rec = CaseRecord(
                                id: row.id,
                                tradedNumber:
                                    tradedNumber.isEmpty ? null : tradedNumber,
                                rollNumber:
                                    rollNumber.isEmpty ? null : rollNumber,
                                number: number,
                                year: year,
                                circuit: circuitName,
                                plaintiff: plaintiff,
                                defendant: defendant,
                                decision: decision,
                                lastSessionDate: firstSession,
                                subject: subject.isEmpty ? null : subject,
                              );
                              final navigator = Navigator.of(ctx);
                              final affected =
                                  await MySqlService().updateCase(rec);
                              if (!mounted) return;
                              navigator.pop();
                              if (!mounted) return;
                              await _loadCases();
                              _selectedCaseId = row.id;
                              _snack(affected > 0
                                  ? 'تم التعديل'
                                  : 'لم يتم التعديل');
                            } catch (e) {
                              setLocal(() => saving = false);
                              if (mounted) {
                                _snack('فشل تعديل القضية: $e', isError: true);
                              }
                            }
                          },
                    icon: const Icon(Icons.save),
                    label: saving
                        ? const Text('جارٍ الحفظ...')
                        : const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _deleteCase() async {
    if (_selectedCaseId == null) {
      _snack('اختر قضية من الجدول أولاً', isError: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text('هل تريد حذف القضية المحددة؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('نعم')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      final rows = await MySqlService().deleteCase(_selectedCaseId!);
      if (rows > 0) {
        await _loadCases();
        if (!mounted) return;
        setState(() => _selectedCaseId = null);
        _snack('تم الحذف');
      } else {
        _snack('لم يتم الحذف', isError: true);
      }
    } catch (e) {
      _snack('فشل الحذف: $e', isError: true);
    }
  }

  Future<void> _reserve() async {
    if (_selectedCaseId == null) {
      _snack('اختر قضية أولاً', isError: true);
      return;
    }
    try {
      final types = await MySqlService()
          .getLatestJudgmentTypesForCases([_selectedCaseId!]);
      final jt = types[_selectedCaseId!];
      if (jt != null && jt.trim() == 'حكم نهائي') {
        await _showError(
            'القضية المحددة صدر فيها حكم نهائى ولا يمكن حجزها للتقرير');
        return;
      }
    } catch (_) {}
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حجز الدعوى للتقرير'),
          content:
              const Text('سيتم حجز الدعوى ولن تظهر في الجدول العادي. متابعة؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      final rows = await MySqlService().reserveCaseForReport(_selectedCaseId!);
      if (rows > 0) {
        await _loadCases();
        _snack('تم الحجز');
      } else {
        _snack('لم يتم الحجز', isError: true);
      }
    } catch (e) {
      _snack('خطأ: $e', isError: true);
    }
  }

  // ===== Correspondence Dialog (خطابات واستعجالات) =====
  Future<void> _openCorrespondenceDialog() async {
    if (_selectedCaseId == null) return;

    final selectedCase = _cases.firstWhere((c) => c.id == _selectedCaseId);

    // جلب جلسات القضية
    List<SessionRecord> sessions = [];
    try {
      sessions = await MySqlService().getSessionsForCase(_selectedCaseId!);
      // ترتيب الجلسات من الأقدم إلى الأحدث
      sessions.sort((a, b) {
        if (a.sessionDate == null && b.sessionDate == null) return 0;
        if (a.sessionDate == null) return 1;
        if (b.sessionDate == null) return -1;
        return a.sessionDate!.compareTo(b.sessionDate!);
      });
    } catch (e) {
      _snack('فشل تحميل الجلسات: $e', isError: true);
      return;
    }

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    DateTime? selectedSessionDate;
    String? correspondenceType; // خطاب أو استعجال
    String? correspondenceNature; // يعتمد على النوع
    String recipientEntity = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              // تحديث قائمة طبيعة المخاطبة بناءً على النوع
              List<String> getNatureOptions() {
                if (correspondenceType == 'خطاب') {
                  return ['طلب معلومات', 'طلب تحرى'];
                } else if (correspondenceType == 'استعجال') {
                  return ['استعجال معلومات', 'استعجال تحرى'];
                }
                return [];
              }

              return AlertDialog(
                title: const Text('خطابات واستعجالات'),
                content: SizedBox(
                  width: 600,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // بيانات القضية (للعرض فقط)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('بيانات القضية',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(
                                    'رقم الدعوى: ${selectedCase.number} لسنة ${selectedCase.year}'),
                                Text('المدعى: ${selectedCase.plaintiff}'),
                                Text('المدعى عليه: ${selectedCase.defendant}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // تاريخ الجلسة (Dropdown من جلسات القضية)
                          DropdownButtonFormField<DateTime>(
                            decoration: const InputDecoration(
                              labelText: 'تاريخ الجلسة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null ? 'اختر التاريخ' : null,
                            items: sessions.map((s) {
                              return DropdownMenuItem<DateTime>(
                                value: s.sessionDate,
                                child: Text(_fmt(s.sessionDate)),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setLocal(() => selectedSessionDate = v);
                            },
                          ),
                          const SizedBox(height: 12),

                          // نوع المخاطبة
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'نوع المخاطبة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'اختر النوع' : null,
                            items: const [
                              DropdownMenuItem(
                                  value: 'خطاب', child: Text('خطاب')),
                              DropdownMenuItem(
                                  value: 'استعجال', child: Text('استعجال')),
                            ],
                            onChanged: (v) {
                              setLocal(() {
                                correspondenceType = v;
                                correspondenceNature =
                                    null; // إعادة تعيين الطبيعة
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // طبيعة المخاطبة (تعتمد على النوع)
                          if (correspondenceType != null)
                            DropdownButtonFormField<String>(
                              key: ValueKey(correspondenceType),
                              decoration: const InputDecoration(
                                labelText: 'طبيعة المخاطبة',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'اختر الطبيعة'
                                  : null,
                              items: getNatureOptions()
                                  .map((n) => DropdownMenuItem(
                                      value: n, child: Text(n)))
                                  .toList(),
                              onChanged: (v) {
                                setLocal(() => correspondenceNature = v);
                              },
                            ),
                          if (correspondenceType != null)
                            const SizedBox(height: 12),

                          // اسم الجهة المخاطبة
                          TextFormField(
                            initialValue: recipientEntity,
                            decoration: const InputDecoration(
                              labelText: 'اسم الجهة المخاطبة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'أدخل اسم الجهة'
                                : null,
                            onChanged: (v) => recipientEntity = v,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (formKey.currentState?.validate() == true) {
                        Navigator.of(ctx).pop();
                        // TODO: هنا سيتم طباعة المخاطبة
                        _printCorrespondence(
                          caseData: selectedCase,
                          sessionDate: selectedSessionDate!,
                          type: correspondenceType!,
                          nature: correspondenceNature!,
                          recipient: recipientEntity.trim(),
                        );
                      }
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة المخاطبة'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _printCorrespondence({
    required _CaseRow caseData,
    required DateTime sessionDate,
    required String type,
    required String nature,
    required String recipient,
  }) {
    // TODO: تنفيذ طباعة المخاطبة لاحقاً
    _snack(
        'سيتم طباعة $type - $nature\nالجهة: $recipient\nالجلسة: ${_fmt(sessionDate)}');
  }

  Future<void> _attachmentsDialog() async {
    if (_selectedCaseId == null) {
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تنبيه'),
            content: const Text('اختر قضية أولاً'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // بيانات القضية للمعلومات أعلى الحوار
    final caseRow = _cases.firstWhere((c) => c.id == _selectedCaseId);

    List<SessionRecord> caseSessions = [];

    Future<void> refresh() async {
      try {
        caseSessions =
            await MySqlService().getSessionsForCase(_selectedCaseId!);
        caseSessions.sort((a, b) {
          final da = a.sessionDate;
          final db = b.sessionDate;
          if (da == null && db == null) return 0;
          if (da == null) return -1;
          if (db == null) return 1;
          return da.compareTo(db);
        });
      } catch (e) {
        _snack('فشل تحميل بيانات الجلسات: $e', isError: true);
      }
    }

    // حوار جدول المرفقات (يُستدعى بعد الحفظ)
    Future<void> showAttachmentsTable() async {
      List<AttachmentRecord> attachments = [];
      final hCtrl = ScrollController();

      Future<void> reload() async {
        attachments =
            await MySqlService().getAttachmentsForCase(_selectedCaseId!);
      }

      Future<void> openAttachment(AttachmentRecord a) async {
        if (a.filePath.isEmpty) {
          _snack('لا يوجد مسار ملف', isError: true);
          return;
        }
        await OpenFilex.open(a.filePath);
      }

      Future<void> deleteAttachment(
          AttachmentRecord a, void Function(void Function()) setLocal) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تأكيد حذف'),
              content: const Text('هل تريد حذف هذا المرفق؟'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('حذف'),
                ),
              ],
            ),
          ),
        );
        if (ok == true && a.id != null) {
          try {
            await MySqlService().deleteAttachment(a.id!);
            await reload();
            setLocal(() {});
            _snack('تم الحذف');
          } catch (e) {
            _snack('فشل الحذف: $e', isError: true);
          }
        }
      }

      await reload();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('مرفقات القضية'),
                content: SizedBox(
                  width: 900,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // معلومات القضية أعلى الحوار
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'رقم الدعوى',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(caseRow.number),
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
                              child: Text(caseRow.year),
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
                              child: Text(caseRow.plaintiff),
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
                              child: Text(caseRow.defendant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'جميع المرفقات',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: attachments.isEmpty
                            ? const Align(
                                alignment: Alignment.centerRight,
                                child: Text('لا توجد مرفقات'),
                              )
                            : Scrollbar(
                                controller: hCtrl,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: hCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('الملف')),
                                      DataColumn(label: Text('نوع')),
                                      DataColumn(label: Text('تاريخ الإضافة')),
                                      DataColumn(label: Text('تاريخ النسخ')),
                                      DataColumn(label: Text('رقم قيد النسخ')),
                                      DataColumn(label: Text('جلسة التقديم')),
                                      DataColumn(label: Text('إجراءات')),
                                    ],
                                    rows: attachments.map((a) {
                                      final fileName = a.filePath
                                          .split('\\')
                                          .last
                                          .split('/')
                                          .last;
                                      return DataRow(cells: [
                                        DataCell(Text(fileName)),
                                        DataCell(Text(a.type)),
                                        DataCell(Text(a.createdAt == null
                                            ? '-'
                                            : _fmt(a.createdAt))),
                                        DataCell(Text(a.copyDate == null
                                            ? '-'
                                            : _fmt(a.copyDate))),
                                        DataCell(Text(a.copyRegisterNumber ==
                                                    null ||
                                                a.copyRegisterNumber!.isEmpty
                                            ? '-'
                                            : a.copyRegisterNumber!)),
                                        DataCell(Text(a.submitDate == null
                                            ? '-'
                                            : _fmt(a.submitDate))),
                                        DataCell(Row(
                                          children: [
                                            IconButton(
                                              tooltip: 'فتح الملف',
                                              onPressed: () =>
                                                  openAttachment(a),
                                              icon:
                                                  const Icon(Icons.open_in_new),
                                            ),
                                            IconButton(
                                              tooltip: 'حذف',
                                              onPressed: a.id == null
                                                  ? null
                                                  : () => deleteAttachment(
                                                      a, setLocal),
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                            ),
                                          ],
                                        )),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _attachmentsDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مرفق'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('إغلاق'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    await refresh();

    // مباشرة افتح نافذة إضافة مرفق بدل قائمة المرفقات
    final formKey = GlobalKey<FormState>();
    String? type;
    XFile? picked;
    DateTime? copyDate;
    SessionRecord? selectedSession;
    final copyRegisterCtrl = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (subCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (subCtx, setSub) {
            return AlertDialog(
              title: const Text('إضافة مرفق'),
              content: SizedBox(
                width: 640,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'رقم الدعوى',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(caseRow.number),
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
                                child: Text(caseRow.year),
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
                                child: Text(caseRow.plaintiff),
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
                                child: Text(caseRow.defendant),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          items: const [
                            'مذكرة دفاع',
                            'مذكرة رأى',
                            'صحيفة الدعوى',
                            'مستندات الدعوى',
                            'الحكم الصادر فى الدعوى',
                          ]
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged:
                              saving ? null : (v) => setSub(() => type = v),
                          decoration: const InputDecoration(
                            labelText: 'نوع المرفق',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'نوع المرفق مطلوب'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<SessionRecord>(
                          initialValue: selectedSession,
                          items: caseSessions.map((s) {
                            final d = s.sessionDate;
                            final label =
                                '${d == null ? '-' : _fmt(d)} - ${s.decision.isEmpty ? '-' : s.decision}';
                            return DropdownMenuItem(
                                value: s, child: Text(label));
                          }).toList(),
                          onChanged: saving
                              ? null
                              : (v) => setSub(() => selectedSession = v),
                          decoration: const InputDecoration(
                            labelText: 'جلسة تقديم الملف',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) =>
                              v == null ? 'جلسة التقديم مطلوبة' : null,
                        ),
                        const SizedBox(height: 10),
                        if (type == 'مذكرة دفاع' || type == 'مذكرة رأى')
                          FormField<DateTime?>(
                            initialValue: copyDate,
                            validator: (v) =>
                                v == null ? 'تاريخ النسخ مطلوب' : null,
                            builder: (state) => Row(
                              children: [
                                Expanded(
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'تاريخ نسخ المذكرة',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      errorText: state.errorText,
                                    ),
                                    child: Text(copyDate == null
                                        ? 'لم يتم التحديد'
                                        : _fmt(copyDate)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          final now = DateTime.now();
                                          final p = await showDatePicker(
                                            context: subCtx,
                                            firstDate: DateTime(now.year - 5),
                                            lastDate: DateTime(now.year + 5),
                                            initialDate: copyDate ?? now,
                                            builder: (c, ch) => Directionality(
                                              textDirection: TextDirection.rtl,
                                              child: ch ?? const SizedBox(),
                                            ),
                                          );
                                          if (p != null) {
                                            setSub(() => copyDate = p);
                                            state.didChange(p);
                                          }
                                        },
                                  icon: const Icon(Icons.date_range),
                                  label: const Text('اختر'),
                                ),
                              ],
                            ),
                          ),
                        if (type == 'مذكرة دفاع' || type == 'مذكرة رأى')
                          const SizedBox(height: 10),
                        if (type == 'مذكرة دفاع') ...[
                          TextField(
                            controller: copyRegisterCtrl,
                            decoration: const InputDecoration(
                              labelText: 'رقم القيد فى سجل النسخ (اختياري)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'الملف',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(
                                  picked?.name ?? 'لم يتم اختيار ملف',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final file =
                                          await openFile(acceptedTypeGroups: [
                                        const XTypeGroup(label: 'any'),
                                      ]);
                                      if (file != null) {
                                        setSub(() => picked = file);
                                      }
                                    },
                              icon: const Icon(Icons.attach_file),
                              label: const Text('اختيار'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          Navigator.of(subCtx).pop();
                          await showAttachmentsTable();
                        },
                  icon: const Icon(Icons.list),
                  label: const Text('عرض المرفقات المحفوظة'),
                ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(subCtx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          if (picked == null) {
                            _snack('اختر ملف المرفق', isError: true);
                            return;
                          }
                          setSub(() => saving = true);
                          try {
                            final a = AttachmentRecord(
                              caseId: _selectedCaseId!,
                              type: type ?? '',
                              filePath: picked!.path,
                              copyDate:
                                  (type == 'مذكرة دفاع' || type == 'مذكرة رأى')
                                      ? copyDate
                                      : null,
                              copyRegisterNumber: (type == 'مذكرة دفاع' &&
                                      copyRegisterCtrl.text.trim().isNotEmpty)
                                  ? copyRegisterCtrl.text.trim()
                                  : null,
                              submitDate: selectedSession?.sessionDate,
                            );
                            final navigator = Navigator.of(subCtx);
                            await MySqlService().addAttachment(a);
                            if (!mounted) return;
                            navigator.pop();
                            // بعد الحفظ، اعرض جدول المرفقات كما طُلب
                            await showAttachmentsTable();
                            _snack('تم إضافة المرفق');
                          } catch (e) {
                            _snack('فشل الحفظ: $e', isError: true);
                            setSub(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _transferSessionDialog() async {
    if (_selectedCaseId == null) {
      await _showError('اختر قضية أولاً');
      return;
    }
    // لا تسمح بترحيل القضايا التي صدر فيها حكم نهائي
    try {
      final types = await MySqlService()
          .getLatestJudgmentTypesForCases([_selectedCaseId!]);
      final jt = types[_selectedCaseId!];
      if (jt != null && jt.trim() == 'حكم نهائي') {
        await _showError('القضية المحددة تم الحكم فيها ولا يجوز ترحيلها');
        return;
      }
    } catch (_) {}
    List<SessionRecord> sessions = [];
    try {
      sessions = await MySqlService().getSessionsForCase(_selectedCaseId!);
      sessions.sort((a, b) {
        final da = a.sessionDate;
        final db = b.sessionDate;
        if (da == null && db == null) return 0;
        if (da == null) return -1;
        if (db == null) return 1;
        return da.compareTo(db);
      });
    } catch (_) {}
    final formKey = GlobalKey<FormState>();
    DateTime? nextDate;
    String nextDecision = '';
    bool strikeOff = false;
    bool saving = false;
    // بيانات القضية للعرض فقط
    final caseRow = _cases.firstWhere((c) => c.id == _selectedCaseId);
    // اختيار دائرة جديدة (اختياري) مع افتراض الدائرة الحالية
    int? selectedCircuitId = _circuits
        .firstWhere((c) => c.name.trim() == caseRow.circuit.trim(),
            orElse: () => CircuitRecord(
                id: null,
                name: '',
                number: '',
                meetingDay: '',
                meetingTime: ''))
        .id;
    // التاريخ مطلوب من المستخدم: اتركه فارغاً حتى يتم اختياره صراحة
    nextDate = null;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('ترحيل جلسة'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // اختيار دائرة جديدة (اختياري)
                        DropdownButtonFormField<int>(
                          initialValue: selectedCircuitId,
                          items: _circuits
                              .map((c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ))
                              .toList(),
                          onChanged: saving
                              ? null
                              : (v) => setLocal(() => selectedCircuitId = v),
                          decoration: const InputDecoration(
                            labelText: 'ترحيل إلى دائرة (اختياري)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'يمكن ترك الدائرة الحالية كما هي. عند اختيار دائرة جديدة سيتم نقل القضية إلى الدائرة المحددة مع ترحيل الجلسة.',
                            style:
                                TextStyle(color: Colors.black54, fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // بيانات القضية للعرض فقط
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'رقم الدعوى',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(caseRow.number),
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
                                child: Text(caseRow.year),
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
                                child: Text(caseRow.plaintiff),
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
                                child: Text(caseRow.defendant),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!strikeOff)
                          FormField<DateTime?>(
                            initialValue: nextDate,
                            validator: (v) {
                              if (v == null) return 'تاريخ الجلسة مطلوب';
                              return null;
                            },
                            builder: (state) {
                              return Row(
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
                                          : _fmt(nextDate)),
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
                                              firstDate:
                                                  DateTime(now.year - 50),
                                              lastDate: DateTime(now.year + 5),
                                              initialDate: nextDate ?? now,
                                              builder: (c, ch) =>
                                                  Directionality(
                                                textDirection:
                                                    TextDirection.rtl,
                                                child: ch ?? const SizedBox(),
                                              ),
                                            );
                                            if (p != null) {
                                              setLocal(() => nextDate = p);
                                              state.didChange(p);
                                            }
                                          },
                                    icon: const Icon(Icons.date_range),
                                    label: const Text('اختر'),
                                  )
                                ],
                              );
                            },
                          ),
                        if (!strikeOff) const SizedBox(height: 10),
                        if (!strikeOff)
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'قرار الجلسة',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => nextDecision = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'قرار الجلسة مطلوب'
                                : null,
                          ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: strikeOff,
                          onChanged: (v) =>
                              setLocal(() => strikeOff = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('شطب الدعوى'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'جلسات القضية',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: sessions.isEmpty
                              ? const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('لا توجد جلسات سابقة'),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: sessions.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 8),
                                  itemBuilder: (_, i) {
                                    final s = sessions[i];
                                    final d = s.sessionDate;
                                    final st = _sessionStatus(d);
                                    final stColor = st == 'انتهت'
                                        ? Colors.red
                                        : (st == 'اليوم'
                                            ? Colors.orange
                                            : Colors.green);
                                    return Row(
                                      children: [
                                        Expanded(
                                            flex: 2,
                                            child: Text(
                                                d == null ? '-' : _fmt(d))),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            flex: 3, child: Text(s.decision)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            st,
                                            textAlign: TextAlign.start,
                                            style: TextStyle(color: stColor),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
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
                          if (!strikeOff &&
                              !(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            final navigator = Navigator.of(ctx);
                            if (strikeOff) {
                              await MySqlService()
                                  .strikeOffCase(caseId: _selectedCaseId!);
                            } else {
                              // تحقق من تغيير الدائرة
                              String? selectedCircuitName;
                              if (selectedCircuitId != null) {
                                final c = _circuits.firstWhere(
                                    (cc) => cc.id == selectedCircuitId,
                                    orElse: () => CircuitRecord(
                                        id: null,
                                        name: '',
                                        number: '',
                                        meetingDay: '',
                                        meetingTime: ''));
                                selectedCircuitName =
                                    c.name.isEmpty ? null : c.name;
                              }
                              final currentCircuit = caseRow.circuit.trim();
                              final willChangeCircuit = selectedCircuitName !=
                                      null &&
                                  selectedCircuitName.trim().isNotEmpty &&
                                  selectedCircuitName.trim() != currentCircuit;

                              if (willChangeCircuit) {
                                await MySqlService().repleadCaseToCircuit(
                                  caseId: _selectedCaseId!,
                                  circuitName: selectedCircuitName,
                                  sessionDate: nextDate!,
                                  decision: nextDecision,
                                );
                                // إذا كانت القضية مشطوبة سابقاً، قم بإزالتها من السجل
                                try {
                                  await MySqlService().restoreCaseFromStruckOff(
                                      _selectedCaseId!);
                                } catch (_) {}
                              } else {
                                await MySqlService().addSession(
                                  caseId: _selectedCaseId!,
                                  date: nextDate!,
                                  decision: nextDecision,
                                );
                                // Ensure removal from سجل القضايا المشطوبة إن وجدت
                                try {
                                  await MySqlService().restoreCaseFromStruckOff(
                                      _selectedCaseId!);
                                } catch (_) {}
                              }
                            }
                            if (!mounted) return;
                            navigator.pop();
                            _snack(strikeOff
                                ? 'تم شطب الدعوى ونقلها إلى سجل القضايا المشطوبة'
                                : 'تم ترحيل الجلسة');
                            await _loadCases();
                          } catch (e) {
                            _snack('فشل الترحيل: $e', isError: true);
                            setLocal(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===== طباعة رول الجلسة =====
  void _openRollReport() {
    // المتطلبات: اختيار تاريخ جلسة ( _firstSessionDate ) + اختيار دائرة فقط بدون حقول أخرى
    final hasSession = _firstSessionDate != null;
    final circuit = (_selectedCircuitId != null)
        ? _circuits.firstWhere(
            (c) => c.id == _selectedCircuitId,
            orElse: () => CircuitRecord(
                id: null,
                name: '',
                number: '',
                meetingDay: '',
                meetingTime: ''),
          )
        : null;
    final otherFilled = _numberCtrl.text.trim().isNotEmpty ||
        _yearCtrl.text.trim().isNotEmpty ||
        _plaintiffCtrl.text.trim().isNotEmpty ||
        _defendantCtrl.text.trim().isNotEmpty ||
        _decisionCtrl.text.trim().isNotEmpty;
    if (!hasSession) {
      _snack('اختر تاريخ الجلسة في البحث بالأعلى', isError: true);
      return;
    }
    if (circuit == null || circuit.name.isEmpty) {
      _snack('اختر الدائرة فقط (يجب تحديد الدائرة)', isError: true);
      return;
    }
    if (otherFilled) {
      _snack(
          'يجب أن يكون البحث محتويًا على (تاريخ جلسة + دائرة) فقط بدون حقول أخرى',
          isError: true);
      return;
    }
    if (_cases.isEmpty) {
      _snack('لا توجد قضايا لعرضها في الرول', isError: true);
      return;
    }
    // انتقل لصفحة التقرير وتمرير البيانات الحالية الظاهرة
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaseRollReportPage(
          sessionDate: _firstSessionDate!,
          circuit: circuit,
          cases: _cases
              .map((c) => CaseRecord(
                    id: c.id,
                    number: c.number,
                    year: c.year,
                    circuit: c.circuit,
                    plaintiff: c.plaintiff,
                    defendant: c.defendant,
                    decision: c.decision,
                    lastSessionDate: c.lastSessionDate,
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ===== طباعة جلسة الأجندة =====
  void _openAgendaSessionReport() {
    final hasSession = _firstSessionDate != null;
    final circuit = (_selectedCircuitId != null)
        ? _circuits.firstWhere(
            (c) => c.id == _selectedCircuitId,
            orElse: () => CircuitRecord(
                id: null,
                name: '',
                number: '',
                meetingDay: '',
                meetingTime: ''),
          )
        : null;
    final otherFilled = _numberCtrl.text.trim().isNotEmpty ||
        _yearCtrl.text.trim().isNotEmpty ||
        _plaintiffCtrl.text.trim().isNotEmpty ||
        _defendantCtrl.text.trim().isNotEmpty ||
        _decisionCtrl.text.trim().isNotEmpty;
    if (!hasSession) {
      _snack('اختر تاريخ الجلسة في البحث بالأعلى', isError: true);
      return;
    }
    if (circuit == null || circuit.name.isEmpty) {
      _snack('اختر الدائرة فقط (يجب تحديد الدائرة)', isError: true);
      return;
    }
    if (otherFilled) {
      _snack(
          'يجب أن يكون البحث محتويًا على (تاريخ جلسة + دائرة) فقط بدون حقول أخرى',
          isError: true);
      return;
    }
    if (_cases.isEmpty) {
      _snack('لا توجد قضايا لعرضها', isError: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgendaSessionReportPage(
          sessionDate: _firstSessionDate!,
          circuit: circuit,
          cases: _cases
              .map((c) => CaseRecord(
                    id: c.id,
                    tradedNumber: c.tradedNumber,
                    rollNumber: c.rollNumber,
                    number: c.number,
                    year: c.year,
                    circuit: c.circuit,
                    plaintiff: c.plaintiff,
                    defendant: c.defendant,
                    decision: c.decision,
                    lastSessionDate: c.lastSessionDate,
                    prevSessionDate: c.prevSessionDate,
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ===== Small UI helpers =====
  Widget _field(String label, TextEditingController c,
          {TextInputType? keyboardType, VoidCallback? onChanged}) =>
      TextField(
        controller: c,
        keyboardType: keyboardType,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  // Placeholder removed: _ro helper no longer used after simplification

  Future<void> _showError(String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تنبيه', style: TextStyle(color: Colors.redAccent)),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('حسناً'))
          ],
        ),
      ),
    );
  }

  Future<void> _openStruckOffRegister() async {
    final service = MySqlService();
    List<StruckOffCaseRecord> list = [];
    bool loading = true;
    StruckOffCaseRecord? selected;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setLocal) {
          Future<void> refresh() async {
            setLocal(() => loading = true);
            try {
              list = await service.getStruckOffCases();
            } catch (_) {}
            setLocal(() => loading = false);
          }

          if (loading) {
            Future.microtask(refresh);
          }

          Future<void> renewFromStruckOff(StruckOffCaseRecord r) async {
            final changed = await _openStrikeRenewDialogFor(r);
            if (changed == true) {
              await refresh();
              await _loadCases();
            }
          }

          String fmt(DateTime? d) => d == null
              ? '-'
              : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

          return AlertDialog(
            title: const Text('سجل بيانات القضايا المشطوبة'),
            content: SizedBox(
              width: 920,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (list.isEmpty
                      ? const Text('لا يوجد قضايا مشطوبة')
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            showCheckboxColumn: true,
                            columns: const [
                              DataColumn(label: Text('رقم الدعوى')),
                              DataColumn(label: Text('سنة الدعوى')),
                              DataColumn(label: Text('الدائرة')),
                              DataColumn(label: Text('المدعى')),
                              DataColumn(label: Text('المدعى عليه')),
                              DataColumn(label: Text('تاريخ آخر جلسة')),
                              DataColumn(label: Text('تاريخ الشطب')),
                            ],
                            rows: list.map((r) {
                              final isSel = selected?.caseId == r.caseId;
                              return DataRow(
                                selected: isSel,
                                onSelectChanged: (v) => setLocal(() {
                                  selected = v == true ? r : null;
                                }),
                                cells: [
                                  DataCell(Text(r.number)),
                                  DataCell(Text(r.year)),
                                  DataCell(Text(r.circuit)),
                                  DataCell(Text(r.plaintiff)),
                                  DataCell(Text(r.defendant)),
                                  DataCell(Text(fmt(r.lastSessionDate))),
                                  DataCell(Text(fmt(r.struckOffDate))),
                                ],
                              );
                            }).toList(),
                          ),
                        )),
            ),
            actions: [
              TextButton.icon(
                onPressed: selected == null
                    ? null
                    : () => renewFromStruckOff(selected!),
                icon: const Icon(Icons.replay_circle_filled_outlined),
                label: const Text('تجديد من الشطب'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              )
            ],
          );
        }),
      ),
    );
  }

  /// يفتح حوار تجديد من الشطب: نفس بيانات الترحيل لكن بدون خيار "شطب الدعوى"
  /// يعرض سجل الجلسات، وعند الحفظ يضيف جلسة جديدة ثم يعيد القضية للمتداولة.
  Future<bool?> _openStrikeRenewDialogFor(StruckOffCaseRecord rec) async {
    final service = MySqlService();
    List<SessionRecord> sessions = [];
    try {
      sessions = await service.getSessionsForCase(rec.caseId);
      sessions.sort((a, b) {
        final da = a.sessionDate;
        final db = b.sessionDate;
        if (da == null && db == null) return 0;
        if (da == null) return -1;
        if (db == null) return 1;
        return da.compareTo(db);
      });
    } catch (_) {}

    final formKey = GlobalKey<FormState>();
    DateTime? nextDate;
    String nextDecision = '';
    bool saving = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('تجديد من الشطب'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'رقم الدعوى',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(rec.number),
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
                                child: Text(rec.year),
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
                                child: Text(rec.plaintiff),
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
                                child: Text(rec.defendant),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FormField<DateTime?>(
                          initialValue: nextDate,
                          validator: (v) =>
                              v == null ? 'تاريخ الجلسة مطلوب' : null,
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
                                      : _fmt(nextDate)),
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
                                label: const Text('اختر'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'قرار الجلسة',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => nextDecision = v.trim(),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'قرار الجلسة مطلوب'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'سجل جلسات القضية',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: sessions.isEmpty
                              ? const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('لا توجد جلسات سابقة'),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: sessions.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 8),
                                  itemBuilder: (_, i) {
                                    final s = sessions[i];
                                    final d = s.sessionDate;
                                    final st = _sessionStatus(d);
                                    final stColor = st == 'انتهت'
                                        ? Colors.red
                                        : (st == 'اليوم'
                                            ? Colors.orange
                                            : Colors.green);
                                    return Row(
                                      children: [
                                        Expanded(
                                            flex: 2,
                                            child: Text(
                                                d == null ? '-' : _fmt(d))),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            flex: 3, child: Text(s.decision)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            st,
                                            style: TextStyle(color: stColor),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            await service.addSession(
                              caseId: rec.caseId,
                              date: nextDate!,
                              decision: nextDecision,
                            );
                            await service.restoreCaseFromStruckOff(rec.caseId);
                            if (!mounted) return;
                            Navigator.of(ctx).pop(true);
                            _snack('تم ترحيل الجلسة واستعادة القضية للمتداولة');
                          } catch (e) {
                            _snack('فشل العملية: $e', isError: true);
                            setLocal(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CaseRow {
  final int? id;
  final String? tradedNumber;
  final String? rollNumber;
  final String number;
  final String year;
  final String circuit;
  final String plaintiff;
  final String defendant;
  final String decision;
  final DateTime? lastSessionDate;
  final DateTime? prevSessionDate;
  final String? subject;
  _CaseRow({
    this.id,
    this.tradedNumber,
    this.rollNumber,
    required this.number,
    required this.year,
    required this.circuit,
    required this.plaintiff,
    required this.defendant,
    required this.decision,
    this.lastSessionDate,
    this.prevSessionDate,
    this.subject,
  });
}
