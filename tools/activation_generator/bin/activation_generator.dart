import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main(List<String> args) async {
  final map = _parseArgs(args);
  var serial = map['serial'];
  var expiry = map['expiry'];
  var secret = map['secret'];

  if (serial == null || expiry == null || secret == null) {
    stdout.writeln('Activation Code Generator');
    stdout.writeln('Provide serial, expiry (YYYY-MM-DD), and secret.');
    if (serial == null) {
      stdout.write('Serial: ');
      serial = stdin.readLineSync();
    }
    if (expiry == null) {
      stdout.write('Expiry (YYYY-MM-DD): ');
      expiry = stdin.readLineSync();
    }
    if (secret == null) {
      stdout.write('Secret: ');
      secret = stdin.readLineSync();
    }
  }
  if (serial == null || serial.isEmpty) {
    stderr.writeln('Error: serial is required');
    exit(2);
  }
  final dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (expiry == null || !dateRe.hasMatch(expiry)) {
    stderr.writeln('Error: expiry must be YYYY-MM-DD');
    exit(2);
  }
  if (secret == null || secret.isEmpty) {
    stderr.writeln('Error: secret is required');
    exit(2);
  }

  final payload = '$serial|$expiry';
  final h = Hmac(sha256, utf8.encode(secret));
  final digest = h.convert(utf8.encode(payload));
  final code = digest.toString();

  stdout.writeln('\nPayload : $payload');
  stdout.writeln('Code    : $code');
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--serial' && i + 1 < args.length) {
      map['serial'] = args[++i];
    } else if (a == '--expiry' && i + 1 < args.length) {
      map['expiry'] = args[++i];
    } else if (a == '--secret' && i + 1 < args.length) {
      map['secret'] = args[++i];
    }
  }
  return map;
}
