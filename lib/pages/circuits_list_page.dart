import 'package:flutter/material.dart';
import '../services/mysql_service.dart';

class CircuitsListPage extends StatefulWidget {
  const CircuitsListPage({super.key});

  @override
  State<CircuitsListPage> createState() => _CircuitsListPageState();
}

class _CircuitsListPageState extends State<CircuitsListPage> {
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  String? _day;
  String? _time; // صباحى / مسائى

  List<CircuitRecord> _circuits = [];
  int? _selectedId;

  final _days = const [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    // خيارات إضافية: الأسبوع في الشهر
    'الاسبوع الاول فى الشهر',
    'الاسبوع الثانى فى الشهر',
    'الاسبوع الثالث فى الشهر',
    'الاسبوع الرابع فى الشهر',
  ];
  final _times = const ['صباحى', 'مسائى'];

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  Future<void> _loadCircuits() async {
    try {
      final service = MySqlService();
      final list = await service.getCircuits();
      setState(() {
        _circuits = list;
        if (_selectedId != null && !_circuits.any((c) => c.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تحميل الدوائر: $e')),
      );
    }
  }

  Future<void> _addCircuit() async {
    final name = _nameCtrl.text.trim();
    final number = _numberCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم الدائرة مطلوب')),
      );
      return;
    }
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الدائرة مطلوب')),
      );
      return;
    }
    if (_day == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يوم الانعقاد مطلوب')),
      );
      return;
    }
    if (_time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('موعد الانعقاد مطلوب')),
      );
      return;
    }
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final service = MySqlService();
      await service.createCircuit(CircuitRecord(
        name: name,
        number: number,
        meetingDay: _day!,
        meetingTime: _time!,
      ));
      _nameCtrl.clear();
      _numberCtrl.clear();
      setState(() {
        _day = null;
        _time = null;
      });
      await _loadCircuits();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('تمت إضافة الدائرة')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('فشل الإضافة: $e')),
      );
    }
  }

  Future<void> _editSelected() async {
    final current = _circuits.firstWhere((c) => c.id == _selectedId);
    final nameCtrl = TextEditingController(text: current.name);
    final numberCtrl = TextEditingController(text: current.number);
    String? day = current.meetingDay.isEmpty ? null : current.meetingDay;
    String? time = current.meetingTime.isEmpty ? null : current.meetingTime;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: const Text('تعديل الدائرة'),
          content: StatefulBuilder(
            builder: (context, setLocal) {
              final maxH = MediaQuery.of(context).size.height * 0.7;
              return SizedBox(
                width: 500,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _outlined('اسم الدائرة *', nameCtrl),
                        const SizedBox(height: 8),
                        _outlined('رقم الدائرة *', numberCtrl),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: day,
                                items: _days
                                    .map((d) => DropdownMenuItem(
                                        value: d, child: Text(d)))
                                    .toList(),
                                onChanged: (v) => setLocal(() => day = v),
                                decoration: const InputDecoration(
                                    labelText: 'يوم الانعقاد *',
                                    border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: time,
                                items: _times
                                    .map((t) => DropdownMenuItem(
                                        value: t, child: Text(t)))
                                    .toList(),
                                onChanged: (v) => setLocal(() => time = v),
                                decoration: const InputDecoration(
                                    labelText: 'موعد الانعقاد *',
                                    border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                final newNumber = numberCtrl.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('اسم الدائرة مطلوب')),
                  );
                  return;
                }
                if (newNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('رقم الدائرة مطلوب')),
                  );
                  return;
                }
                if (day == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يوم الانعقاد مطلوب')),
                  );
                  return;
                }
                if (time == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('موعد الانعقاد مطلوب')),
                    );
                  }
                  return;
                }
                final navigator = Navigator.of(ctx);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                try {
                  final service = MySqlService();
                  await service.updateCircuit(CircuitRecord(
                    id: current.id,
                    name: newName,
                    number: newNumber,
                    meetingDay: day!,
                    meetingTime: time!,
                  ));
                  navigator.pop();
                  await _loadCircuits();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('تم تعديل الدائرة')),
                  );
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('فشل التعديل: $e')),
                  );
                }
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedId == null) return;
    // Check associated cases before confirming delete
    final circuit = _circuits.firstWhere((c) => c.id == _selectedId);
    int linkedCases = 0;
    try {
      final service = MySqlService();
      linkedCases = await service.getCasesCountForCircuit(circuit.name);
    } catch (_) {}

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: const Text('تأكيد الحذف'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('هل أنت متأكد من حذف الدائرة المحددة؟'),
                if (linkedCases > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'تنبيه: هذه الدائرة مرتبطة بعدد $linkedCases قضية/قضايا. حذف الدائرة قد يؤثر على القضايا المرتبطة بها.',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('لا')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('نعم، حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final service = MySqlService();
      // Use the new method to delete the circuit and all its associated cases
      await service.deleteCircuitAndCases(circuit.name);
      await _loadCircuits();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
            content: Text('تم حذف الدائرة وجميع القضايا المرتبطة بها')),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('فشل الحذف: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('إضافة دائرة جديدة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _outlined('اسم الدائرة *', _nameCtrl),
                    const SizedBox(height: 8),
                    _outlined('رقم الدائرة *', _numberCtrl),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _day,
                            items: _days
                                .map((d) =>
                                    DropdownMenuItem(value: d, child: Text(d)))
                                .toList(),
                            onChanged: (v) => setState(() => _day = v),
                            decoration: const InputDecoration(
                                labelText: 'يوم الانعقاد *',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _time,
                            items: _times
                                .map((t) =>
                                    DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (v) => setState(() => _time = v),
                            decoration: const InputDecoration(
                                labelText: 'موعد الانعقاد *',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _addCircuit,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة دائرة جديدة'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('بيانات الدائرة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('اسم الدائرة')),
                          DataColumn(label: Text('رقم الدائرة')),
                          DataColumn(label: Text('يوم الانعقاد')),
                          DataColumn(label: Text('موعد الانعقاد')),
                        ],
                        rows: _circuits
                            .map(
                              (c) => DataRow(
                                selected: c.id == _selectedId,
                                onSelectChanged: (_) =>
                                    setState(() => _selectedId = c.id),
                                cells: [
                                  DataCell(Text(c.name)),
                                  DataCell(Text(c.number)),
                                  DataCell(Text(c.meetingDay)),
                                  DataCell(Text(c.meetingTime)),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _selectedId == null ? null : _editSelected,
                          icon: const Icon(Icons.edit),
                          label: const Text('تعديل الدائرة'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _selectedId == null ? null : _deleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('حذف الدائرة'),
                        ),
                      ],
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

  Widget _outlined(String label, TextEditingController ctrl,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
