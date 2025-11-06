import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ActivationStudioApp());
}

class ActivationStudioApp extends StatelessWidget {
  const ActivationStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Activation Studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const ActivationStudioHome(),
    );
  }
}

class ActivationStudioHome extends StatefulWidget {
  const ActivationStudioHome({super.key});

  @override
  State<ActivationStudioHome> createState() => _ActivationStudioHomeState();
}

class _ActivationStudioHomeState extends State<ActivationStudioHome> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _secretController = TextEditingController();
  final _expiryController = TextEditingController();
  final _codeController = TextEditingController();

  DateTime _expiry = DateTime.now().add(const Duration(days: 365));

  @override
  void initState() {
    super.initState();
    _expiryController.text = _fmtDate(_expiry);
  }

  @override
  void dispose() {
    _serialController.dispose();
    _secretController.dispose();
    _expiryController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _expiry = picked;
        _expiryController.text = _fmtDate(_expiry);
      });
    }
  }

  void _generate() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final serial = _serialController.text.trim();
    final secret = _secretController.text;
    final expiry = _expiryController.text.trim();
    final payload = '$serial|$expiry';

    final code = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(payload))
        .toString();

    setState(() {
      _codeController.text = '$expiry:$code';
    });
  }

  Future<void> _copyAll() async {
    final serial = _serialController.text.trim();
    final expiry = _expiryController.text.trim();
    final code = _codeController.text.trim();
    final payload = '$serial|$expiry';

    final text =
        'Serial: $serial\nExpiry: $expiry\nPayload: $payload\nToken: $code';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied payload + code to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = 720.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activation Studio'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Generate activation code (HMAC-SHA256): code = HMAC(secret, "serial|YYYY-MM-DD")',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _serialController,
                    decoration: const InputDecoration(
                      labelText: 'Machine Serial',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Serial is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _expiryController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Expiry (YYYY-MM-DD)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                            if (!re.hasMatch(s)) return 'Use format YYYY-MM-DD';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.date_range),
                          label: const Text('Pick date'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secretController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Secret',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Secret is required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.key),
                        label: const Text('Generate Code'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _copyAll,
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy payload + code'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final code = _codeController.text.trim();
                          if (code.isEmpty) return;
                          await Clipboard.setData(ClipboardData(text: code));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied token only')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy token'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    readOnly: true,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Activation Code (hex)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: Payload must match the app: serial|expiry',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
