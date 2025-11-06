import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef VerifyAndSave = Future<bool> Function(
    String activationCode, DateTime expiry);

class ActivationPage extends StatefulWidget {
  final VoidCallback onActivated;
  final VerifyAndSave verifyAndSave;

  const ActivationPage({
    super.key,
    required this.onActivated,
    required this.verifyAndSave,
  });

  static Future<String> getMachineSerial() async {
    try {
      if (Platform.isWindows) {
        // Use wmic to fetch baseboard serial
        final result = await Process.run(
          'wmic',
          ['baseboard', 'get', 'serialnumber'],
          runInShell: true,
        ).timeout(const Duration(seconds: 2));
        if (result.exitCode == 0) {
          final out = (result.stdout as String?) ?? '';
          final lines = out
              .split(RegExp(r'\r?\n'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (lines.length >= 2) {
            final serial = lines[1].replaceAll(RegExp(r'\s+'), '');
            if (serial.isNotEmpty) return serial;
          }
        }
      }
    } catch (_) {}
    // Fallback: generate a pseudo-id from hostname + user
    final host = Platform.localHostname;
    final user = Platform.environment['USERNAME'] ?? 'user';
    return base64Url.encode(utf8.encode('$host-$user')).replaceAll('=', '');
  }

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  String _serial = '';
  final _codeCtrl = TextEditingController();
  final DateTime _expiry = DateTime.now().add(const Duration(days: 365));
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadSerial();
  }

  Future<void> _loadSerial() async {
    final s = await ActivationPage.getMachineSerial();
    if (mounted) setState(() => _serial = s);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            elevation: 2,
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تفعيل البرنامج',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    'يرجى نسخ رقم السيريال وإرساله للدعم الفنى للحصول على كود التفعيل الخاص بك.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'رقم السيريال (المازر بورد)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: SelectableText(
                        _serial.isEmpty ? 'جارٍ الجلب...' : _serial),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _serial.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                                ClipboardData(text: _serial));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ السيريال')),
                            );
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ السيريال'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'كود تفعيل البرنامج',
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'مثال (تنسيق جديد): YYYY-MM-DD:HEX',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _checking
                        ? null
                        : () async {
                            final code = _codeCtrl.text.trim();
                            if (code.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('أدخل كود التفعيل')));
                              return;
                            }
                            setState(() => _checking = true);
                            try {
                              final ok =
                                  await widget.verifyAndSave(code, _expiry);
                              if (!mounted) return;
                              if (ok) {
                                widget.onActivated();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('كود التفعيل غير صحيح')));
                              }
                            } finally {
                              if (mounted) setState(() => _checking = false);
                            }
                          },
                    icon: const Icon(Icons.verified_user),
                    label: Text(_checking ? 'جارٍ التحقق...' : 'تفعيل'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const Text(
                    'فى حال انتهاء مدة التفعيل سيتم إبلاغك برسالة: "تم انتهاء التفعيل يرجى التواصل مع الدعم الفنى لإعادة التفعيل"',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
