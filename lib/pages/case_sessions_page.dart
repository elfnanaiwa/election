import 'package:flutter/material.dart';
import '../services/mysql_service.dart';

class CaseSessionsPage extends StatefulWidget {
  const CaseSessionsPage({super.key});

  @override
  State<CaseSessionsPage> createState() => _CaseSessionsPageState();
}

class _CaseSessionsPageState extends State<CaseSessionsPage> {
  final _numberController = TextEditingController();
  final _yearController = TextEditingController();
  final _plaintiffController = TextEditingController();
  final _defendantController = TextEditingController();

  final _service = MySqlService();

  bool _loading = false;
  List<CaseWithJudgmentRecord> _results = [];
  CaseWithJudgmentRecord? _selected;
  bool _showSavedJudgments = false;

  @override
  void dispose() {
    _numberController.dispose();
    _yearController.dispose();
    _plaintiffController.dispose();
    _defendantController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() {
      _showSavedJudgments = false;
    });
    final number = _numberController.text.trim();
    final year = _yearController.text.trim();
    final plaintiff = _plaintiffController.text.trim();
    final defendant = _defendantController.text.trim();

    final hasNumberYear = number.isNotEmpty && year.isNotEmpty;
    final hasPlaintiff = plaintiff.isNotEmpty;
    final hasDefendant = defendant.isNotEmpty;

    if (!hasNumberYear && !hasPlaintiff && !hasDefendant) {
      _showMsg('أدخل (رقم وسنة) معاً أو المدعى أو المدعى عليه', isError: true);
      return;
    }
    if ((number.isNotEmpty && year.isEmpty) ||
        (year.isNotEmpty && number.isEmpty)) {
      _showMsg('لابد من إدخال رقم وسنة الدعوى معاً', isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _selected = null;
    });

    try {
      final data = await _service.searchCasesWithJudgment(
        number: hasNumberYear ? number : null,
        year: hasNumberYear ? year : null,
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

  Future<void> _loadSavedJudgments() async {
    setState(() {
      _loading = true;
      _showSavedJudgments = true;
      _selected = null;
    });
    try {
      final data = await _service.getCasesWithSavedJudgments();
      if (!mounted) return;
      setState(() {
        _results = data;
      });
      if (data.isEmpty) {
        _showMsg('لا توجد أحكام محفوظة');
      }
    } catch (e) {
      _showMsg('خطأ أثناء تحميل الأحكام: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  Future<void> _openJudgmentDialog({required bool edit}) async {
    if (_selected == null) return;
    final caseRec = _selected!;

    // تحميل الجلسات و الحكم السابق (إن وجد)
    final sessionsFuture = _service.getSessionsForCase(caseRec.id);
    final existingJudgment =
        edit ? await _service.getJudgmentByCaseId(caseRec.id) : null;

    final judgmentTypeOptions = const ['حكم تمهيدى', 'حكم نهائي'];
    final typeValue = ValueNotifier<String?>(existingJudgment?.judgmentType);
    final sessionValue =
        ValueNotifier<SessionRecord?>(null); // سيتم ضبطها بعد تحميل الجلسات
    final textController =
        TextEditingController(text: existingJudgment?.text ?? '');
    final judgmentNatureValue =
        ValueNotifier<String?>(existingJudgment?.judgmentType == 'حكم نهائي'
            ? existingJudgment?.judgmentNature
            : existingJudgment?.judgmentType == 'حكم تمهيدى'
                ? existingJudgment?.judgmentNature
                : null);
    final appealDaysValue =
        ValueNotifier<int?>(existingJudgment?.appealDeadlineDays);
    final registerNumberController =
        TextEditingController(text: existingJudgment?.registerNumber ?? '');
    // متغيرات الوقف الجزائي
    final suspensionPeriodValue =
        ValueNotifier<String?>(existingJudgment?.suspensionPeriod);

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            scrollable: true,
            title: Text(edit ? 'تعديل الحكم' : 'إضافة حكم'),
            content: SizedBox(
              width: 600,
              child: FutureBuilder<List<SessionRecord>>(
                future: sessionsFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final sessions = snap.data ?? const <SessionRecord>[];
                  final maxH = MediaQuery.of(context).size.height * 0.75;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _readOnlyField('رقم الدعوى', caseRec.number),
                          _readOnlyField('سنة الدعوى', caseRec.year),
                          _readOnlyField('المدعى', caseRec.plaintiff),
                          _readOnlyField('المدعى عليه', caseRec.defendant),
                          const SizedBox(height: 8),
                          // اختيار جلسة القضية (إلزامي)
                          ValueListenableBuilder<SessionRecord?>(
                            valueListenable: sessionValue,
                            builder: (context, val, _) {
                              // لو تعديل وحُمل الحكم السابق ولم نعين الجلسة بعد
                              if (val == null &&
                                  existingJudgment?.sessionId != null) {
                                final found = sessions.firstWhere(
                                  (s) => s.id == existingJudgment!.sessionId,
                                  orElse: () => SessionRecord(
                                      id: null,
                                      caseId: caseRec.id,
                                      sessionDate: null,
                                      decision: ''),
                                );
                                if (found.id != null) {
                                  // ضبط القيمة مرة واحدة داخل post-frame لتفادي setState أثناء البناء
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (sessionValue.value == null) {
                                      sessionValue.value = found;
                                    }
                                  });
                                }
                              }
                              return DropdownButtonFormField<SessionRecord>(
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'جلسة القضية *'),
                                initialValue: sessionValue.value,
                                items: sessions
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s.sessionDate
                                                  ?.toIso8601String()
                                                  .substring(0, 10) ??
                                              'بدون تاريخ'),
                                        ))
                                    .toList(),
                                onChanged: (v) => sessionValue.value = v,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<String?>(
                            valueListenable: typeValue,
                            builder: (context, val, _) {
                              return Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(
                                        labelText: 'نوع الحكم *'),
                                    initialValue: val,
                                    items: judgmentTypeOptions
                                        .map((t) => DropdownMenuItem(
                                            value: t, child: Text(t)))
                                        .toList(),
                                    onChanged: (v) => typeValue.value = v,
                                  ),
                                  const SizedBox(height: 8),
                                  if (val == 'حكم نهائي') ...[
                                    TextFormField(
                                      controller: registerNumberController,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'رقم القيد فى سجل الأحكام (اختياري)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  // حكم نهائي: ضد أو صالح
                                  if (val == 'حكم نهائي')
                                    ValueListenableBuilder<String?>(
                                      valueListenable: judgmentNatureValue,
                                      builder: (context, nat, __) {
                                        return Column(
                                          children: [
                                            DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(
                                                  labelText: 'طبيعة الحكم *'),
                                              initialValue: nat,
                                              items: const [
                                                DropdownMenuItem(
                                                    value: 'ضد',
                                                    child: Text('ضد')),
                                                DropdownMenuItem(
                                                    value: 'صالح',
                                                    child: Text('صالح')),
                                              ],
                                              onChanged: (v) =>
                                                  judgmentNatureValue.value = v,
                                            ),
                                            if (nat == 'ضد') ...[
                                              const SizedBox(height: 8),
                                              DropdownButtonFormField<int>(
                                                decoration: const InputDecoration(
                                                    labelText:
                                                        'موعد الطعن على الحكم *'),
                                                initialValue:
                                                    appealDaysValue.value,
                                                items: const [8, 10, 15, 40, 60]
                                                    .map(
                                                      (d) => DropdownMenuItem(
                                                        value: d,
                                                        child: Text('$d أيام'),
                                                      ),
                                                    )
                                                    .toList(),
                                                onChanged: (v) =>
                                                    appealDaysValue.value = v,
                                              ),
                                              const SizedBox(height: 8),
                                              ValueListenableBuilder<
                                                  SessionRecord?>(
                                                valueListenable: sessionValue,
                                                builder: (context, sess, ___) {
                                                  return ValueListenableBuilder<
                                                      int?>(
                                                    valueListenable:
                                                        appealDaysValue,
                                                    builder:
                                                        (context, days, ____) {
                                                      final base =
                                                          sess?.sessionDate;
                                                      final endDate = (base !=
                                                                  null &&
                                                              days != null)
                                                          ? base.add(Duration(
                                                              days: days))
                                                          : null;
                                                      return InputDecorator(
                                                        decoration:
                                                            const InputDecoration(
                                                          labelText:
                                                              'تاريخ انتهاء الطعن',
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                        child: Text(endDate !=
                                                                null
                                                            ? endDate
                                                                .toIso8601String()
                                                                .substring(
                                                                    0, 10)
                                                            : '-'),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  // حكم تمهيدي: وقف جزائي أو وقف تعليقي
                                  if (val == 'حكم تمهيدى')
                                    ValueListenableBuilder<String?>(
                                      valueListenable: judgmentNatureValue,
                                      builder: (context, prelimNat, __) {
                                        return Column(
                                          children: [
                                            DropdownButtonFormField<String>(
                                              decoration: const InputDecoration(
                                                  labelText: 'طبيعة الحكم *'),
                                              initialValue: prelimNat,
                                              items: const [
                                                DropdownMenuItem(
                                                    value: 'وقف جزائى',
                                                    child: Text('وقف جزائى')),
                                                DropdownMenuItem(
                                                    value: 'وقف تعليقى',
                                                    child: Text('وقف تعليقى')),
                                              ],
                                              onChanged: (v) {
                                                judgmentNatureValue.value = v;
                                                if (v != 'وقف جزائى') {
                                                  suspensionPeriodValue.value =
                                                      null;
                                                }
                                              },
                                            ),
                                            // خيارات الوقف الجزائي
                                            if (prelimNat == 'وقف جزائى') ...[
                                              const SizedBox(height: 8),
                                              ValueListenableBuilder<String?>(
                                                valueListenable:
                                                    suspensionPeriodValue,
                                                builder:
                                                    (context, period, ____) {
                                                  return DropdownButtonFormField<
                                                      String>(
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'مدة الوقف الجزائى *'),
                                                    initialValue: period,
                                                    items: const [
                                                      'اسبوع',
                                                      '15 يوم',
                                                      'شهر'
                                                    ]
                                                        .map((p) =>
                                                            DropdownMenuItem(
                                                                value: p,
                                                                child: Text(p)))
                                                        .toList(),
                                                    onChanged: (v) =>
                                                        suspensionPeriodValue
                                                            .value = v,
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              // عرض تواريخ التجديد المحسوبة
                                              ValueListenableBuilder<
                                                  SessionRecord?>(
                                                valueListenable: sessionValue,
                                                builder: (context, sess, _) {
                                                  return ValueListenableBuilder<
                                                      String?>(
                                                    valueListenable:
                                                        suspensionPeriodValue,
                                                    builder: (context,
                                                        suspPeriod, _) {
                                                      final judgmentDate =
                                                          sess?.sessionDate;
                                                      DateTime?
                                                          suspensionEndDate;
                                                      DateTime? renewalFromDate;
                                                      DateTime?
                                                          renewalDeadlineDate;

                                                      if (judgmentDate !=
                                                              null &&
                                                          suspPeriod != null) {
                                                        // حساب تاريخ انتهاء الوقف
                                                        if (suspPeriod ==
                                                            'اسبوع') {
                                                          suspensionEndDate =
                                                              judgmentDate.add(
                                                                  const Duration(
                                                                      days: 7));
                                                        } else if (suspPeriod ==
                                                            '15 يوم') {
                                                          suspensionEndDate =
                                                              judgmentDate.add(
                                                                  const Duration(
                                                                      days:
                                                                          15));
                                                        } else if (suspPeriod ==
                                                            'شهر') {
                                                          suspensionEndDate =
                                                              DateTime(
                                                            judgmentDate.year,
                                                            judgmentDate.month +
                                                                1,
                                                            judgmentDate.day,
                                                          );
                                                        }

                                                        if (suspensionEndDate !=
                                                            null) {
                                                          // تاريخ التجديد = اليوم التالي لانتهاء الوقف
                                                          renewalFromDate =
                                                              suspensionEndDate.add(
                                                                  const Duration(
                                                                      days: 1));
                                                          // تاريخ انتهاء ميعاد التجديد = شهر إلا يوم من تاريخ انتهاء الوقف
                                                          renewalDeadlineDate =
                                                              DateTime(
                                                            suspensionEndDate
                                                                .year,
                                                            suspensionEndDate
                                                                    .month +
                                                                1,
                                                            suspensionEndDate
                                                                .day,
                                                          ).subtract(
                                                                  const Duration(
                                                                      days: 1));
                                                        }
                                                      }

                                                      return Column(
                                                        children: [
                                                          InputDecorator(
                                                            decoration:
                                                                const InputDecoration(
                                                              labelText:
                                                                  'تاريخ التجديد من الوقف الجزائى',
                                                              border:
                                                                  OutlineInputBorder(),
                                                            ),
                                                            child: Text(renewalFromDate !=
                                                                    null
                                                                ? renewalFromDate
                                                                    .toIso8601String()
                                                                    .substring(
                                                                        0, 10)
                                                                : '-'),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          InputDecorator(
                                                            decoration:
                                                                const InputDecoration(
                                                              labelText:
                                                                  'تاريخ انتهاء ميعاد التجديد من الوقف الجزائى',
                                                              border:
                                                                  OutlineInputBorder(),
                                                            ),
                                                            child: Text(renewalDeadlineDate !=
                                                                    null
                                                                ? renewalDeadlineDate
                                                                    .toIso8601String()
                                                                    .substring(
                                                                        0, 10)
                                                                : '-'),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: textController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'نص الحكم *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: typeValue,
                builder: (context, type, _) {
                  return ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(edit ? 'تعديل الحكم' : 'حفظ الحكم'),
                    onPressed: () async {
                      if (sessionValue.value == null) {
                        _showMsg('اختر جلسة القضية', isError: true);
                        return;
                      }
                      if (type == null || type.isEmpty) {
                        _showMsg('اختر نوع الحكم', isError: true);
                        return;
                      }
                      if (textController.text.trim().isEmpty) {
                        _showMsg('أدخل نص الحكم', isError: true);
                        return;
                      }
                      final dialogNavigator = Navigator.of(ctx);
                      try {
                        // حساب حقول الحكم حسب النوع
                        final isFinal = type == 'حكم نهائي';
                        final isPreliminary = type == 'حكم تمهيدى';

                        // التحقق من طبيعة الحكم
                        if ((isFinal || isPreliminary) &&
                            (judgmentNatureValue.value == null ||
                                judgmentNatureValue.value!.isEmpty)) {
                          _showMsg('اختر طبيعة الحكم', isError: true);
                          return;
                        }

                        int? appealDays;
                        DateTime? appealEnd;
                        String? suspensionPeriod;
                        DateTime? renewalFromDate;
                        DateTime? renewalDeadlineDate;

                        // حكم نهائي ضد
                        if (isFinal && judgmentNatureValue.value == 'ضد') {
                          if (appealDaysValue.value == null) {
                            _showMsg('اختر موعد الطعن على الحكم',
                                isError: true);
                            return;
                          }
                          final sDate = sessionValue.value?.sessionDate;
                          if (sDate == null) {
                            _showMsg(
                                'تاريخ جلسة الحكم غير معروف لحساب نهاية الطعن',
                                isError: true);
                            return;
                          }
                          appealDays = appealDaysValue.value;
                          appealEnd = sDate.add(Duration(days: appealDays!));
                        }

                        // حكم تمهيدي - وقف جزائي
                        if (isPreliminary &&
                            judgmentNatureValue.value == 'وقف جزائى') {
                          if (suspensionPeriodValue.value == null) {
                            _showMsg('اختر مدة الوقف الجزائى', isError: true);
                            return;
                          }
                          final sDate = sessionValue.value?.sessionDate;
                          if (sDate == null) {
                            _showMsg(
                                'تاريخ جلسة الحكم غير معروف لحساب تواريخ التجديد',
                                isError: true);
                            return;
                          }
                          suspensionPeriod = suspensionPeriodValue.value;
                          DateTime suspensionEndDate;
                          // حساب تاريخ انتهاء الوقف
                          if (suspensionPeriod == 'اسبوع') {
                            suspensionEndDate =
                                sDate.add(const Duration(days: 7));
                          } else if (suspensionPeriod == '15 يوم') {
                            suspensionEndDate =
                                sDate.add(const Duration(days: 15));
                          } else {
                            // شهر
                            suspensionEndDate = DateTime(
                              sDate.year,
                              sDate.month + 1,
                              sDate.day,
                            );
                          }
                          // تاريخ التجديد = اليوم التالي
                          renewalFromDate =
                              suspensionEndDate.add(const Duration(days: 1));
                          // تاريخ انتهاء ميعاد التجديد = شهر إلا يوم
                          renewalDeadlineDate = DateTime(
                            suspensionEndDate.year,
                            suspensionEndDate.month + 1,
                            suspensionEndDate.day,
                          ).subtract(const Duration(days: 1));
                        }

                        if (edit && existingJudgment != null) {
                          await _service.updateJudgment(JudgmentRecord(
                            id: existingJudgment.id,
                            caseId: caseRec.id,
                            sessionId: sessionValue.value!.id,
                            judgmentType: type,
                            registerNumber: isFinal &&
                                    registerNumberController.text
                                        .trim()
                                        .isNotEmpty
                                ? registerNumberController.text.trim()
                                : null,
                            text: textController.text.trim(),
                            judgmentNature: (isFinal || isPreliminary)
                                ? judgmentNatureValue.value
                                : null,
                            appealDeadlineDays:
                                isFinal && judgmentNatureValue.value == 'ضد'
                                    ? appealDays
                                    : null,
                            appealEndDate:
                                isFinal && judgmentNatureValue.value == 'ضد'
                                    ? appealEnd
                                    : null,
                            suspensionPeriod: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? suspensionPeriod
                                : null,
                            renewalFromSuspensionDate: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? renewalFromDate
                                : null,
                            renewalDeadlineDate: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? renewalDeadlineDate
                                : null,
                          ));
                        } else {
                          await _service.addJudgment(JudgmentRecord(
                            caseId: caseRec.id,
                            sessionId: sessionValue.value!.id,
                            judgmentType: type,
                            registerNumber: isFinal &&
                                    registerNumberController.text
                                        .trim()
                                        .isNotEmpty
                                ? registerNumberController.text.trim()
                                : null,
                            text: textController.text.trim(),
                            judgmentNature: (isFinal || isPreliminary)
                                ? judgmentNatureValue.value
                                : null,
                            appealDeadlineDays:
                                isFinal && judgmentNatureValue.value == 'ضد'
                                    ? appealDays
                                    : null,
                            appealEndDate:
                                isFinal && judgmentNatureValue.value == 'ضد'
                                    ? appealEnd
                                    : null,
                            suspensionPeriod: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? suspensionPeriod
                                : null,
                            renewalFromSuspensionDate: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? renewalFromDate
                                : null,
                            renewalDeadlineDate: isPreliminary &&
                                    judgmentNatureValue.value == 'وقف جزائى'
                                ? renewalDeadlineDate
                                : null,
                          ));
                        }
                        dialogNavigator.pop(true);
                      } catch (e) {
                        _showMsg('خطأ: $e', isError: true);
                      }
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
    if (saved == true) {
      // إعادة تحميل النتائج بنفس المعايير أو تحديث الصف الحالي فقط
      await _refreshAfterJudgment(caseRec.id);
      _showMsg('تم الحفظ');
    }
  }

  Future<void> _refreshAfterJudgment(int caseId) async {
    try {
      // الحصول على الحكم الأحدث
      final latest = await _service.getJudgmentByCaseId(caseId);
      setState(() {
        final idx = _results.indexWhere((c) => c.id == caseId);
        if (idx != -1) {
          final old = _results[idx];
          _results[idx] = CaseWithJudgmentRecord(
            id: old.id,
            number: old.number,
            year: old.year,
            plaintiff: old.plaintiff,
            defendant: old.defendant,
            lastSessionDate: old.lastSessionDate,
            latestJudgmentType: latest?.judgmentType,
            latestJudgmentNature: latest?.judgmentNature,
            appealEndDate: latest?.appealEndDate,
          );
          _selected = _results[idx];
        }
      });
    } catch (_) {}
  }

  Future<void> _openViewJudgment() async {
    if (_selected == null) return;
    final j = await _service.getJudgmentByCaseId(_selected!.id);
    if (!mounted) return;
    if (j == null) {
      _showMsg('لا يوجد حكم محفوظ', isError: true);
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: const Text('عرض الحكم'),
          content: SizedBox(
            width: 600,
            child: Builder(
              builder: (context) {
                final maxH = MediaQuery.of(context).size.height * 0.75;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _readOnlyField('رقم الدعوى', _selected!.number),
                        _readOnlyField('سنة الدعوى', _selected!.year),
                        _readOnlyField('المدعى', _selected!.plaintiff),
                        _readOnlyField('المدعى عليه', _selected!.defendant),
                        _readOnlyField('نوع الحكم', j.judgmentType),
                        if (j.judgmentType == 'حكم نهائي' &&
                            j.registerNumber != null &&
                            j.registerNumber!.isNotEmpty)
                          _readOnlyField(
                              'رقم القيد فى سجل الأحكام', j.registerNumber!),
                        if (j.judgmentNature != null &&
                            j.judgmentNature!.isNotEmpty)
                          _readOnlyField('طبيعة الحكم', j.judgmentNature!),
                        if (j.judgmentNature == 'ضد') ...[
                          if (j.appealDeadlineDays != null)
                            _readOnlyField('موعد الطعن على الحكم',
                                '${j.appealDeadlineDays} أيام'),
                          if (j.appealEndDate != null)
                            _readOnlyField(
                                'تاريخ انتهاء الطعن',
                                j.appealEndDate!
                                    .toIso8601String()
                                    .substring(0, 10)),
                        ],
                        const SizedBox(height: 8),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'نص الحكم',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(j.text.isEmpty ? '-' : j.text),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor:
              Theme.of(context).colorScheme.onInverseSurface.withAlpha(12),
        ),
      ),
    );
  }

  DataRow _buildRow(CaseWithJudgmentRecord c) {
    final theme = Theme.of(context);
    final selected = _selected?.id == c.id;
    String status;
    if (c.latestJudgmentType == null || c.latestJudgmentType!.isEmpty) {
      status = 'لم يتم الحكم';
    } else {
      status = c.latestJudgmentType!; // 'حكم تمهيدى' أو 'حكم نهائي'
    }
    Color? bg;
    if (status == 'حكم نهائي') {
      bg = Colors.green.withAlpha(38); // ~15%
    } else if (status == 'حكم تمهيدى') {
      bg = Colors.amber.withAlpha(46); // ~18%
    }
    return DataRow(
      color: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.primary.withValues(alpha: 0.2);
          }
          return bg;
        },
      ),
      selected: selected,
      onSelectChanged: (_) {
        setState(() {
          _selected = c;
        });
      },
      cells: [
        DataCell(Text(c.number)),
        DataCell(Text(c.year)),
        DataCell(Text(c.plaintiff)),
        DataCell(Text(c.defendant)),
        DataCell(Text(c.lastSessionDate != null
            ? c.lastSessionDate!.toIso8601String().substring(0, 10)
            : '-')),
        DataCell(Text(status)),
        DataCell(Text(
          (c.latestJudgmentType == 'حكم نهائي' ||
                  c.latestJudgmentType == 'حكم تمهيدى')
              ? (c.latestJudgmentNature ?? '-')
              : '-',
        )),
        DataCell(Text(
          (c.latestJudgmentType == 'حكم نهائي' &&
                  (c.latestJudgmentNature == 'ضد') &&
                  c.appealEndDate != null)
              ? c.appealEndDate!.toIso8601String().substring(0, 10)
              : '-',
        )),
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
                          width: 170,
                          child: TextField(
                            controller: _numberController,
                            decoration: const InputDecoration(
                              labelText: 'رقم الدعوى',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _yearController,
                            decoration: const InputDecoration(
                              labelText: 'سنة الدعوى',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _plaintiffController,
                            decoration: const InputDecoration(
                              labelText: 'المدعى',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _defendantController,
                            decoration: const InputDecoration(
                              labelText: 'المدعى عليه',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _performSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('بحث'),
                        ),
                        const SizedBox(width: 8),
                        if (!_showSavedJudgments)
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _loadSavedJudgments,
                            icon: const Icon(Icons.table_view),
                            label: const Text('عرض بيانات الأحكام المحفوظة'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _performSearch,
                            icon: const Icon(Icons.search_off),
                            label: const Text('عرض نتائج البحث'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                elevation: 2,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? const Center(child: Text('لا توجد بيانات'))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _showSavedJudgments
                                        ? 'الأحكام المحفوظة'
                                        : 'نتائج البحث',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('رقم')),
                                    DataColumn(label: Text('سنة')),
                                    DataColumn(label: Text('المدعى')),
                                    DataColumn(label: Text('المدعى عليه')),
                                    DataColumn(label: Text('آخر جلسة')),
                                    DataColumn(label: Text('حالة الحكم')),
                                    DataColumn(label: Text('طبيعة الحكم')),
                                    DataColumn(
                                        label: Text('تاريخ انتهاء الطعن')),
                                  ],
                                  rows: _results.map(_buildRow).toList(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    if (_selected != null &&
                                        (_selected!.latestJudgmentType ==
                                                null ||
                                            _selected!.latestJudgmentType!
                                                .isEmpty)) ...[
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _openJudgmentDialog(edit: false),
                                        icon: const Icon(Icons.add),
                                        label: const Text('إضافة حكم'),
                                      ),
                                    ] else if (_selected != null) ...[
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _openJudgmentDialog(edit: true),
                                        icon: const Icon(Icons.edit),
                                        label: const Text('تعديل الحكم'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: _openViewJudgment,
                                        icon: const Icon(Icons.visibility),
                                        label: const Text('عرض الحكم'),
                                      ),
                                    ] else ...[
                                      // لا شيء عندما لا يوجد اختيار
                                      ElevatedButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.add),
                                        label: const Text('إضافة حكم'),
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
