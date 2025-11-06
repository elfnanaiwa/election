import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mysql_service.dart';

class _MonthInfo {
  final int year;
  final int month;
  const _MonthInfo({required this.year, required this.month});

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  static const List<String> _names = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  String get label => _names[month - 1];
  String get labelWithYear => '$label $year';
}

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({super.key});

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  final _service = MySqlService();
  bool _loadingStats = false;
  int _activeCount = 0; // القضايا المتداولة (لم يصدر حكم نهائي)
  int _finalCount = 0; // القضايا المحفوظة (لديها حكم نهائي)
  int _reservedCount = 0; // القضايا داخل الشعبة (محجوزة للتقرير)
  int _struckOffCount = 0; // القضايا المشطوبة
  int _pendingFilesCount = 0; // القضايا تحت الرفع
  bool _loadingMonth = false;
  // أزلنا الكاش لتحقيق التحديث اللحظي حسب الطلب
  // Map<String, List<MonthlyCaseSessionRecord>> _monthlyCache = {};
  final Map<String, List<MonthlyCaseSessionRecord>> _monthData = {};
  // تتبع التحميل لكل شهر لتفادي التحميل المكرر والتجميد
  final Set<String> _loadingMonths = <String>{};
  bool _loadingAppealSoon = false;
  List<JudgmentAppealDueRecord> _appealDueSoon = const [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAppealDueSoon();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final active = await _service.getActiveCasesCount();
      final finals = await _service.getFinalJudgmentCasesCount();
      final reserved = await _service.getReservedCasesCount();
      final struck = await _service.getStruckOffCasesCount();
      final pendingFiles = await _service.getPendingFilesCount();
      if (!mounted) return;
      setState(() {
        _activeCount = active;
        _finalCount = finals;
        _reservedCount = reserved;
        _struckOffCount = struck;
        _pendingFilesCount = pendingFiles;
      });
    } catch (e) {
      _showSnack('تعذر تحميل الإحصائيات: $e');
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadAppealDueSoon() async {
    setState(() => _loadingAppealSoon = true);
    try {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day);
      final to = from.add(const Duration(days: 10));
      final data =
          await _service.getJudgmentsAppealEndingSoon(from: from, to: to);
      if (!mounted) return;
      setState(() => _appealDueSoon = data);
    } catch (e) {
      _showSnack('تعذر تحميل أحكام قاربت انتهاء الطعن: $e');
    } finally {
      if (mounted) setState(() => _loadingAppealSoon = false);
    }
  }

  List<_MonthInfo> _generateMonths() {
    // نطاق ثابت حسب الطلب: من أكتوبر 2025 إلى سبتمبر 2026
    final startYear = 2025;
    final startMonth = 10; // أكتوبر 2025
    final months = <_MonthInfo>[];
    int y = startYear;
    int m = startMonth;
    for (int i = 0; i < 12; i++) {
      months.add(_MonthInfo(year: y, month: m));
      m++;
      if (m == 13) {
        m = 1;
        y++;
      }
    }
    return months;
  }

  Future<void> _loadMonthData(_MonthInfo info, {bool force = false}) async {
    final key = info.key;
    if (_loadingMonths.contains(key)) {
      return; // تجاهل طلبات مكررة لنفس الشهر أثناء التحميل
    }
    if (!force && _monthData.containsKey(key) && _monthData[key]!.isNotEmpty) {
      // سنعيد التحميل دائماً لتحقيق "لحظي" لكن نسمح بعدم التحميل إذا قائمة غير فارغة وforce=false
    }
    _loadingMonths.add(key);
    setState(() => _loadingMonth = true);
    try {
      // تنفيذ متوازي مع مهلات مستقلة لكل استعلام
      final fSessions =
          _service.getMonthlySessions(year: info.year, month: info.month);
      final fLast = _service.getMonthlyCasesFromCaseTable(
          year: info.year, month: info.month);

      List<MonthlyCaseSessionRecord> sessions = const [];
      List<MonthlyCaseSessionRecord> lastSessions = const [];
      bool sessionsTimedOut = false;
      bool lastTimedOut = false;
      try {
        sessions = await fSessions.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        sessionsTimedOut = true; // سنعتمد على المصدر الآخر
      }
      try {
        lastSessions = await fLast.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        lastTimedOut = true; // سنعتمد على المصدر الآخر
      }
      // دمج بدون تكرار (الأولوية لنتيجة الجلسات التفصيلية)
      final mergedMap = <int, MonthlyCaseSessionRecord>{};
      for (final r in lastSessions) {
        mergedMap[r.caseId] = r;
      }
      for (final r in sessions) {
        mergedMap[r.caseId] =
            r; // override with more recent from sessions table
      }
      final merged = mergedMap.values.toList()
        ..sort((a, b) {
          final da = a.sessionDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.sessionDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da); // الأحدث أولاً كما كان سابقاً
        });
      if (!mounted) return;
      setState(() => _monthData[key] = merged);
      // لا نظهر رسالة فشل إلا إذا حدثت مهلة في المصدرين معًا
      if (sessionsTimedOut && lastTimedOut) {
        _showSnack(
            'انتهت المهلة أو فشل التحميل لشهر ${info.labelWithYear}. حاول مرة أخرى.');
      }
    } catch (e) {
      _showSnack('خطأ في تحميل بيانات شهر ${info.labelWithYear}: $e');
    } finally {
      _loadingMonths.remove(key);
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final months = _generateMonths();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: () async {
          _monthData.clear();
          await _loadStats();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatsCard(),
            const SizedBox(height: 16),
            _buildMonthsWrapper(months),
            const SizedBox(height: 16),
            _buildAppealDueSoonCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('إحصائيات عامة',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loadingStats ? null : _loadStats,
                  icon: _loadingStats
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                )
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _smallStatTile(
                    label: 'القضايا المتداولة',
                    value: _activeCount,
                    icon: Icons.loop),
                _smallStatTile(
                    label: 'القضايا المحفوظة (حكم نهائي)',
                    value: _finalCount,
                    icon: Icons.gavel),
                _smallStatTile(
                    label: 'القضايا داخل الشعبة',
                    value: _reservedCount,
                    icon: Icons.inventory),
                _smallStatTile(
                    label: 'إحصائية القضايا المشطوبة',
                    value: _struckOffCount,
                    icon: Icons.backup_table_outlined),
                _smallStatTile(
                    label: 'القضايا تحت الرفع',
                    value: _pendingFilesCount,
                    icon: Icons.snippet_folder),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppealDueSoonCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('أحكام قاربت على انتهاء الطعن (متبقى عليها 10 أيام)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loadingAppealSoon ? null : _loadAppealDueSoon,
                  icon: _loadingAppealSoon
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                )
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingAppealSoon)
              const LinearProgressIndicator(minHeight: 3)
            else if (_appealDueSoon.isEmpty)
              const Text('لا توجد أحكام قاربت انتهاء الطعن')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('رقم الدعوى')),
                    DataColumn(label: Text('سنة الدعوى')),
                    DataColumn(label: Text('المدعى')),
                    DataColumn(label: Text('الدائرة')),
                    DataColumn(label: Text('تاريخ انتهاء الطعن')),
                    DataColumn(label: Text('الأيام المتبقية')),
                  ],
                  rows: _appealDueSoon
                      .map((r) => DataRow(cells: [
                            DataCell(Text(r.number)),
                            DataCell(Text(r.year)),
                            DataCell(Text(r.plaintiff)),
                            DataCell(Text(r.circuit)),
                            DataCell(Text(_formatDate(r.appealEndDate))),
                            DataCell(Text('${r.daysLeft}')),
                          ]))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _smallStatTile(
      {required String label, required int value, required IconData icon}) {
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('$value',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthsWrapper(List<_MonthInfo> months) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إحصائية الجلسات لكل شهر',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: months
                  .map((m) => _buildMonthCard(
                        m,
                        initiallyExpanded:
                            months.isNotEmpty && m.key == months.first.key,
                      ))
                  .toList(),
            ),
            if (_loadingMonth)
              const Padding(
                padding: EdgeInsets.only(top: 12.0),
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthCard(_MonthInfo info, {bool initiallyExpanded = false}) {
    final key = info.key;
    final data = _monthData[key];
    final isMonthLoading = _loadingMonths.contains(key);
    return SizedBox(
      width: 380,
      child: ExpansionTile(
        title: Text('إحصائية جلسات شهر ${info.labelWithYear}'),
        subtitle: Text(data == null
            ? 'لم يتم التحميل بعد'
            : 'عدد القضايا: ${data.length}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMonthLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'تحديث الشهر',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _loadMonthData(info, force: true),
              ),
            const Icon(Icons.expand_more),
          ],
        ),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: (expanded) {
          if (expanded) {
            _loadMonthData(info, force: true);
          }
        },
        children: [
          if (data == null)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('جاري التحميل أو لم يتم التحميل بعد'),
            )
          else if (data.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('لا توجد قضايا لهذا الشهر'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('رقم الدعوى')),
                  DataColumn(label: Text('سنة الدعوى')),
                  DataColumn(label: Text('المدعى')),
                  DataColumn(label: Text('المدعى عليه')),
                  DataColumn(label: Text('تاريخ الجلسة')),
                  DataColumn(label: Text('الدائرة')),
                ],
                rows: data
                    .map((r) => DataRow(cells: [
                          DataCell(Text(r.number)),
                          DataCell(Text(r.year)),
                          DataCell(Text(r.plaintiff)),
                          DataCell(Text(r.defendant)),
                          DataCell(Text(_formatDate(r.sessionDate))),
                          DataCell(Text(r.circuit)),
                        ]))
                    .toList(),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // لا يوجد مصدر بيانات مخصص الآن بعد العودة لجدول بسيط لكل شهر
}
