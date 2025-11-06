import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'pages/activation_page.dart';
import 'theme/app_theme.dart';
import 'pages/case_details_page.dart';
import 'pages/case_sessions_page.dart';
import 'pages/circuits_list_page.dart';
import 'pages/statistics_page.dart';
import 'pages/department_page.dart';
import 'pages/bulk_migration_page.dart';
import 'pages/home_dashboard_page.dart';
import 'pages/pending_files_page.dart';
import 'services/mysql_service.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1024, 700),
    center: true,
    titleBarStyle: TitleBarStyle.normal,
  );
  // Ensure the app can intercept close events.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimizable(true);
    // Force normal window state to avoid fullscreen white screen.
    await windowManager.setFullScreen(false);
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await windowManager.setSize(const Size(1280, 800));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const AgendaApp());
}

class AgendaApp extends StatefulWidget {
  const AgendaApp({super.key});

  @override
  State<AgendaApp> createState() => _AgendaAppState();
}

class _AgendaAppState extends State<AgendaApp> with WindowListener {
  ThemeMode _mode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gateActivationOnStartup();
      _initDbInBackground();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<bool> _confirmClose(BuildContext ctx) async {
    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الخروج'),
          content: const Text('هل تريد الخروج من البرنامج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: const Text('لا'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: const Text('نعم'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  // WindowListener override to intercept the close event
  @override
  Future<void> onWindowClose() async {
    final canClose = await _confirmClose(navigatorKey.currentContext!);
    if (canClose) {
      await windowManager.destroy();
    }
  }

  static final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('themeMode');
    if (value == 'dark') {
      setState(() => _mode = ThemeMode.dark);
    } else if (value == 'light') {
      setState(() => _mode = ThemeMode.light);
    } else if (value == 'system') {
      setState(() => _mode = ThemeMode.system);
    }
  }

  Future<bool> _isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    // New format: single token 'YYYY-MM-DD:HEX'
    final token = prefs.getString('activation_token');
    if (token != null) {
      try {
        final parts = token.split(':');
        if (parts.length == 2) {
          final expiry = DateTime.parse(parts[0]);
          if (DateTime.now().isAfter(expiry)) return false;
          final serial = await _getSerialSafe();
          final expected = _generateActivationFor(serial, expiry);
          return constantTimeEquals(parts[1], expected);
        }
      } catch (_) {}
      return false;
    }

    // Legacy format: separate code + expiry
    final code = prefs.getString('activation_code');
    final expiryStr = prefs.getString('activation_expiry');
    if (code == null || expiryStr == null) return false;
    try {
      final expiry = DateTime.parse(expiryStr);
      if (DateTime.now().isAfter(expiry)) return false;
      final serial = await _getSerialSafe();
      final expected = _generateActivationFor(serial, expiry);
      return constantTimeEquals(code, expected);
    } catch (_) {
      return false;
    }
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var res = 0;
    for (var i = 0; i < a.length; i++) {
      res |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return res == 0;
  }

  Future<String> _getSerialSafe() async {
    try {
      return await ActivationPage.getMachineSerial()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      final host = Platform.localHostname;
      final user = Platform.environment['USERNAME'] ?? 'user';
      return base64Url.encode(utf8.encode('$host-$user')).replaceAll('=', '');
    }
  }

  String _generateActivationFor(String serial, DateTime expiry) {
    // WARNING: Replace with your own strong secret before shipping.
    const secret = 'CHANGE_ME_STRONG_SECRET';
    final payload = '$serial|${expiry.toIso8601String().substring(0, 10)}';
    final h = Hmac(sha256, utf8.encode(secret));
    final digest = h.convert(utf8.encode(payload));
    return digest.toString();
  }

  Future<void> _toggleAndSave() async {
    setState(() {
      _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'themeMode', _mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> _gateActivationOnStartup() async {
    try {
      final ok = await _isActivated();
      if (ok) return;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActivationPage(
            onActivated: () {
              navigatorKey.currentState?.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => StartPage(
                    onToggleTheme: _toggleAndSave,
                    isDark: _mode == ThemeMode.dark,
                  ),
                ),
              );
            },
            verifyAndSave: (activationInput, fallbackExpiry) async {
              final prefs = await SharedPreferences.getInstance();
              final serial = await _getSerialSafe();

              if (activationInput.contains(':')) {
                try {
                  final parts = activationInput.split(':');
                  if (parts.length != 2) return false;
                  final expiry = DateTime.parse(parts[0]);
                  final expected = _generateActivationFor(serial, expiry);
                  if (!constantTimeEquals(parts[1], expected)) return false;
                  await prefs.setString('activation_token', activationInput);
                  await prefs.setString('activation_activated_at',
                      DateTime.now().toIso8601String());
                  return true;
                } catch (_) {
                  return false;
                }
              }

              final expected = _generateActivationFor(serial, fallbackExpiry);
              if (!constantTimeEquals(activationInput, expected)) return false;
              await prefs.setString('activation_code', activationInput);
              await prefs.setString(
                  'activation_expiry', fallbackExpiry.toIso8601String());
              await prefs.setString(
                  'activation_activated_at', DateTime.now().toIso8601String());
              return true;
            },
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _initDbInBackground() async {
    try {
      await MySqlService().initDatabase().timeout(const Duration(seconds: 8));
    } catch (_) {
      // ignore init errors in background; pages will migrate lazily if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _mode,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        breakpoints: const [
          Breakpoint(start: 0, end: 450, name: MOBILE),
          Breakpoint(start: 451, end: 800, name: TABLET),
          Breakpoint(start: 801, end: 1200, name: DESKTOP),
          Breakpoint(start: 1201, end: double.infinity, name: '4K'),
        ],
      ),
      home: StartPage(
        onToggleTheme: _toggleAndSave,
        isDark: _mode == ThemeMode.dark,
      ),
    );
  }
}

class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    this.onToggleTheme,
    this.isDark = false,
  });

  final VoidCallback? onToggleTheme;
  final bool isDark;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Precache logo so it renders without needing a resize
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await precacheImage(
          const AssetImage('assets/images/agenda-logo.png'),
          context,
        );
        if (mounted) setState(() {});
      } catch (_) {}
      // After first frame, show stale cases notification if any.
      _maybeShowStaleCasesDialog();
    });
  }

  Future<void> _maybeShowStaleCasesDialog() async {
    List<CaseRecord> stale = const [];
    int notificationDays = 4;
    try {
      final prefs = await SharedPreferences.getInstance();
      notificationDays =
          (prefs.getInt('stale_reminder_days') ?? 4).clamp(1, 30);
      stale = await MySqlService().getStaleCases(days: notificationDays);
    } catch (_) {}
    if (!mounted || stale.isEmpty) return;

    CaseRecord? selected;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setLocal) {
          String fmt(DateTime? d) => d == null
              ? '-'
              : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return AlertDialog(
            title: Text(
                'تنبيه: قضايا لم تُرحَّل منذ أكثر من $notificationDays يوم'),
            content: SizedBox(
              width: 960,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: true,
                  columns: const [
                    DataColumn(label: Text('رقم الدعوى')),
                    DataColumn(label: Text('سنة الدعوى')),
                    DataColumn(label: Text('الدائرة')),
                    DataColumn(label: Text('المدعى')),
                    DataColumn(label: Text('المدعى عليه')),
                    DataColumn(label: Text('آخر قرار')),
                    DataColumn(label: Text('تاريخ آخر جلسة')),
                  ],
                  rows: stale.map((c) {
                    final isSel = selected?.id == c.id;
                    return DataRow(
                      selected: isSel,
                      onSelectChanged: (v) => setLocal(() {
                        selected = v == true ? c : null;
                      }),
                      cells: [
                        DataCell(Text(c.number)),
                        DataCell(Text(c.year)),
                        DataCell(Text(c.circuit)),
                        DataCell(Text(c.plaintiff)),
                        DataCell(Text(c.defendant)),
                        DataCell(Text(c.decision)),
                        DataCell(Text(fmt(c.lastSessionDate))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
              FilledButton.icon(
                onPressed: selected == null
                    ? null
                    : () async {
                        // Navigate to CaseDetails page and open the transfer dialog for the selected case
                        Navigator.of(ctx).pop();
                        setState(() => _selectedIndex = 1);
                        // Push a new CaseDetailsPage that will auto-open transfer for the selected case
                        if (!mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CaseDetailsPage(
                                openTransferForCaseId: selected!.id),
                          ),
                        );
                      },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('ترحيل'),
              ),
            ],
          );
        }),
      ),
    );
  }

  static const _titles = <String>[
    'الصفحة الرئيسية',
    'بيانات القضية',
    'قضايا تحت الرفع',
    'الحكم في القضية',
    'قائمة الدوائر',
    'الاحصائية',
    'الشعبة',
    'ترحيل مجمع',
  ];

  Widget _buildPageBody(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return const HomeDashboardPage();
      case 1:
        return const CaseDetailsPage();
      case 2:
        return const PendingFilesPage();
      case 3:
        return const CaseSessionsPage();
      case 4:
        return const CircuitsListPage();
      case 5:
        return const StatisticsPage();
      case 6:
        return const DepartmentPage();
      case 7:
        return const BulkMigrationPage();
      default:
        return Center(
          child: Text(
            '${_titles[_selectedIndex]} (قريباً)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
    }
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final activatedAt = prefs.getString('activation_activated_at');
    final activatedAtStr = activatedAt != null
        ? DateTime.tryParse(activatedAt)?.toLocal().toString().split('.').first
        : null;
    int staleDays = (prefs.getInt('stale_reminder_days') ?? 4).clamp(1, 30);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعدادات البرنامج'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_user),
                    title: const Text('تاريخ تفعيل النسخة'),
                    subtitle: Text(activatedAtStr ?? 'غير متوفر'),
                  ),
                  const Divider(),
                  // Stale cases reminder setting
                  StatefulBuilder(
                    builder: (c, setLocal) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.notifications_active),
                        title: const Text('التذكير بالقضايا غير المُرحّلة'),
                        subtitle: const Text(
                            'إظهار تنبيه عند وجود قضايا لم تُرحَّل منذ أكثر من عدد الأيام المحدد'),
                        trailing: DropdownButton<int>(
                          value: staleDays,
                          items: List<int>.generate(30, (i) => i + 1)
                              .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text('$d يوم${d == 1 ? '' : 'اً'}'),
                                  ))
                              .toList(),
                          onChanged: (v) async {
                            if (v == null) return;
                            setLocal(() => staleDays = v);
                            await prefs.setInt('stale_reminder_days', v);
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backup),
                    title: const Text('حفظ نسخة احتياطية من البيانات'),
                    subtitle: const Text(
                        'تخزين نسخة من قاعدة البيانات كملف على جهازك'),
                    trailing: FilledButton(
                      onPressed: () async {
                        try {
                          final path =
                              await MySqlService().exportDatabaseToFile();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('تم حفظ النسخة الاحتياطية: $path')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('فشل حفظ النسخة: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('حفظ'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore),
                    title: const Text('استعادة نسخة البيانات من الجهاز'),
                    subtitle: const Text(
                        'استرجاع البيانات من ملف نسخ احتياطي ودمجها'),
                    trailing: FilledButton(
                      onPressed: () async {
                        try {
                          await MySqlService().importDatabaseFromFile();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تمت الاستعادة بنجاح')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('فشل الاستعادة: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('استعادة'),
                    ),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.support_agent),
                    title: Text('الدعم الفني'),
                    subtitle: Text('المستشار / محمد كمال الصغير\n01015555538'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            const ClipboardData(text: '01015555538'));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ الرقم')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ رقم الهاتف'),
                    ),
                  )
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            )
          ],
        ),
      ),
    );
  }

  NavigationRailDestination _navDestination(
      IconData icon, IconData selected, String label) {
    return NavigationRailDestination(
      icon: _RailItem(icon: icon, label: label),
      selectedIcon: _RailItem(icon: selected, label: label, selected: true),
      label: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.of(context).largerThan(TABLET);
    final railExtended = isDesktop;
    final railWidth = railExtended ? 210.0 : 72.0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: railExtended, // عرض كامل لسطح المكتب فقط
            minWidth: railWidth,
            groupAlignment: -1,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 220,
                      height: 200,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox.expand(
                          child: Image.asset(
                            'assets/images/agenda-logo.png',
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ).animate().fadeIn(duration: 400.ms).scale(
                                begin: const Offset(0.97, 0.97),
                                end: const Offset(1, 1),
                                curve: Curves.easeOut,
                                duration: 400.ms,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            trailing: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                        ),
                        onPressed: () => _showSettingsDialog(context),
                        icon: const Icon(Icons.settings),
                        label: const Text('إعدادات البرنامج'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                        ),
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                          widget.isDark ? Icons.wb_sunny : Icons.dark_mode,
                          size: 18,
                        ),
                        label: Text(
                          'الانتقال إلى الوضع الليلى',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: widget.isDark
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Colors.white,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            destinations: [
              _navDestination(
                  Icons.home_outlined, Icons.home, 'الصفحة الرئيسية'),
              _navDestination(Icons.folder_open, Icons.folder, 'بيانات القضية'),
              _navDestination(Icons.snippet_folder_outlined,
                  Icons.snippet_folder, 'قضايا تحت الرفع'),
              _navDestination(Icons.event_busy, Icons.event, 'الحكم في القضية'),
              _navDestination(
                  Icons.list_alt, Icons.assignment, 'قائمة الدوائر'),
              _navDestination(
                  Icons.bar_chart_outlined, Icons.bar_chart, 'الاحصائية'),
              _navDestination(
                  Icons.account_tree_outlined, Icons.account_tree, 'الشعبة'),
              _navDestination(Icons.sync_alt, Icons.sync, 'ترحيل مجمع'),
            ],
            labelType: NavigationRailLabelType.none,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _titles[_selectedIndex],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildPageBody(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: selected
          ? BoxDecoration(
              color: theme.colorScheme.tertiary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
