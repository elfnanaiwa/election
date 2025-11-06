import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mysql1/mysql1.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'dart:io';
import 'package:file_selector/file_selector.dart';

class DbConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String db;
  final String charset;
  final String collation;

  const DbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.db,
    this.charset = 'utf8mb4',
    this.collation = 'utf8mb4_unicode_ci',
  });

  factory DbConfig.fromJson(Map<String, dynamic> json) => DbConfig(
        host: json['host'] as String? ?? '127.0.0.1',
        port: (json['port'] as num?)?.toInt() ?? 3306,
        user: json['user'] as String? ?? 'root',
        password: json['password'] as String? ?? '',
        db: json['db'] as String? ?? 'agenda_db',
        charset: json['charset'] as String? ?? 'utf8mb4',
        collation: json['collation'] as String? ?? 'utf8mb4_unicode_ci',
      );
}

class MySqlService {
  static const _assetPath = 'assets/config/db_config.json';

  // Convert values to JSON-encodable types (handles DateTime, BigInt, bytes)
  dynamic _jsonSafe(Object? value) {
    if (value == null) return null;
    if (value is num || value is bool || value is String) return value;
    if (value is DateTime) return value.toIso8601String();
    if (value is BigInt) return value.toString();
    if (value is Uint8List) return base64Encode(value);
    return value.toString();
  }

  // Decode a value to String if it's a String or bytes; otherwise toString().
  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is Uint8List) {
      try {
        return utf8.decode(v);
      } catch (_) {
        return String.fromCharCodes(v);
      }
    }
    if (v is List<int>) {
      try {
        return utf8.decode(v);
      } catch (_) {
        return String.fromCharCodes(v);
      }
    }
    return v.toString();
  }

  Future<DbConfig> _loadConfig() async {
    try {
      final text = await rootBundle.loadString(_assetPath);
      final map = json.decode(text) as Map<String, dynamic>;
      return DbConfig.fromJson(map);
    } catch (_) {
      // Fallback to sample defaults if config file is missing
      return const DbConfig(
          host: '127.0.0.1',
          port: 3306,
          user: 'root',
          password: '',
          db: 'agenda_db');
    }
  }

  // ====== Statistics ======
  Future<int> getActiveCasesCount() async {
    var conn = await _connect();
    try {
      // Cases without a final judgment
      final sql = '''
        SELECT COUNT(*) FROM cases c
        WHERE c.reserved_for_report=0
          AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
          AND NOT EXISTS (
            SELECT 1 FROM judgments j
            WHERE j.case_id = c.id AND j.judgment_type = 'حكم نهائي'
          )
      ''';
      final rows = await conn.query(sql);
      return (rows.first[0] as int?) ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final rows = await conn.query('''
          SELECT COUNT(*) FROM cases c
            WHERE NOT EXISTS (
              SELECT 1 FROM judgments j
              WHERE j.case_id = c.id AND j.judgment_type = 'حكم نهائي'
            )
            AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
        ''');
        return (rows.first[0] as int?) ?? 0;
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> getFinalJudgmentCasesCount() async {
    var conn = await _connect();
    try {
      final sql = '''
        SELECT COUNT(DISTINCT c.id) FROM cases c
        JOIN judgments j ON j.case_id = c.id AND j.judgment_type = 'حكم نهائي'
        WHERE c.reserved_for_report=0
          AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
      ''';
      final rows = await conn.query(sql);
      return (rows.first[0] as int?) ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final rows = await conn.query('''
          SELECT COUNT(DISTINCT c.id) FROM cases c
          JOIN judgments j ON j.case_id = c.id AND j.judgment_type = 'حكم نهائي'
          WHERE NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
        ''');
        return (rows.first[0] as int?) ?? 0;
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> getReservedCasesCount() async {
    var conn = await _connect();
    try {
      final rows = await conn.query(
          'SELECT COUNT(*) FROM cases c WHERE c.reserved_for_report=1 AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)');
      return (rows.first[0] as int?) ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        // migrate then retry
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final rows = await conn.query(
            'SELECT COUNT(*) FROM cases c WHERE NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)');
        return (rows.first[0] as int?) ?? 0; // fallback w/o column
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<List<MonthlyCaseSessionRecord>> getMonthlySessions({
    required int year,
    required int month,
  }) async {
    // first and last day of month
    final first = DateTime(year, month, 1);
    final nextMonth =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final last = nextMonth.subtract(const Duration(days: 1));
    final fromStr = first.toIso8601String().substring(0, 10);
    final toStr = last.toIso8601String().substring(0, 10);
    var conn = await _connect();
    try {
      final sqlWith = '''
  SELECT c.id, c.number, c.year, c.plaintiff, c.defendant, s.session_date, s.decision, c.circuit
        FROM cases c
        JOIN (
          SELECT s1.case_id, s1.session_date, s1.decision
          FROM sessions s1
          JOIN (
            SELECT case_id, MAX(session_date) AS max_date
            FROM sessions
            WHERE session_date BETWEEN ? AND ?
            GROUP BY case_id
          ) ms ON ms.case_id = s1.case_id AND ms.max_date = s1.session_date
        ) s ON s.case_id = c.id
        WHERE c.reserved_for_report=0
          AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
          AND s.session_date BETWEEN ? AND ?
        ORDER BY s.session_date DESC, c.id DESC
      ''';
      final sqlNo = '''
  SELECT c.id, c.number, c.year, c.plaintiff, c.defendant, s.session_date, s.decision, c.circuit
        FROM cases c
        JOIN (
          SELECT s1.case_id, s1.session_date, s1.decision
          FROM sessions s1
          JOIN (
            SELECT case_id, MAX(session_date) AS max_date
            FROM sessions
            WHERE session_date BETWEEN ? AND ?
            GROUP BY case_id
          ) ms ON ms.case_id = s1.case_id AND ms.max_date = s1.session_date
        ) s ON s.case_id = c.id
        WHERE s.session_date BETWEEN ? AND ?
        ORDER BY s.session_date DESC, c.id DESC
      ''';
      Future<List<MonthlyCaseSessionRecord>> parse(Results rows) async {
        return rows
            .map((r) => MonthlyCaseSessionRecord(
                  caseId: r[0] as int,
                  number: r[1] as String? ?? '',
                  year: r[2] as String? ?? '',
                  plaintiff: r[3] as String? ?? '',
                  defendant: r[4] as String? ?? '',
                  sessionDate:
                      r[5] != null ? DateTime.tryParse(r[5].toString()) : null,
                  sessionDecision: r[6] as String? ?? '',
                  circuit: r[7] as String? ?? '',
                ))
            .toList();
      }

      try {
        final rows =
            await conn.query(sqlWith, [fromStr, toStr, fromStr, toStr]);
        return parse(rows);
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          await ensureTables();
          try {
            final rows2 =
                await conn.query(sqlWith, [fromStr, toStr, fromStr, toStr]);
            return parse(rows2);
          } on MySqlException catch (_) {
            final rows3 =
                await conn.query(sqlNo, [fromStr, toStr, fromStr, toStr]);
            return parse(rows3);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  Future<List<MonthlyCaseSessionRecord>> getMonthlyCasesFromCaseTable({
    required int year,
    required int month,
  }) async {
    final first = DateTime(year, month, 1);
    final nextMonth =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final last = nextMonth.subtract(const Duration(days: 1));
    final fromStr = first.toIso8601String().substring(0, 10);
    final toStr = last.toIso8601String().substring(0, 10);
    var conn = await _connect();
    try {
      final sql = '''
        SELECT c.id, c.number, c.year, c.plaintiff, c.defendant, c.last_session_date, c.decision, c.circuit
        FROM cases c
        WHERE c.last_session_date BETWEEN ? AND ?
          AND NOT EXISTS (SELECT 1 FROM struck_off_cases so WHERE so.case_id=c.id)
      ''';
      final rows = await conn.query(sql, [fromStr, toStr]);
      return rows
          .map((r) => MonthlyCaseSessionRecord(
                caseId: r[0] as int,
                number: r[1] as String? ?? '',
                year: r[2] as String? ?? '',
                plaintiff: r[3] as String? ?? '',
                defendant: r[4] as String? ?? '',
                sessionDate:
                    r[5] != null ? DateTime.tryParse(r[5].toString()) : null,
                sessionDecision: r[6] as String? ?? '',
                circuit: r[7] as String? ?? '',
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  Future<MySqlConnection> _connect({bool withDb = true}) async {
    final cfg = await _loadConfig();
    final settings = ConnectionSettings(
      host: cfg.host,
      port: cfg.port,
      user: cfg.user,
      password: cfg.password,
      db: withDb ? cfg.db : null,
      timeout: const Duration(seconds: 8),
    );
    final conn = await MySqlConnection.connect(settings);
    // Ensure charset/collation
    await conn.query("SET NAMES ${cfg.charset} COLLATE ${cfg.collation}");
    return conn;
  }

  Future<void> ensureDatabase() async {
    final cfg = await _loadConfig();
    final conn = await _connect(withDb: false);
    try {
      await conn.query(
          "CREATE DATABASE IF NOT EXISTS `${cfg.db}` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");
    } finally {
      await conn.close();
    }
  }

  Future<void> ensureTables() async {
    final conn = await _connect(withDb: true);
    try {
      // cases
      await conn.query('''
        CREATE TABLE IF NOT EXISTS `cases` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `traded_number` VARCHAR(100) NULL,
          `roll_number` VARCHAR(100) NULL,
          `number` VARCHAR(100) NOT NULL,
          `year` VARCHAR(10) NULL,
          `circuit` VARCHAR(255) NULL,
          `plaintiff` VARCHAR(255) NULL,
          `defendant` VARCHAR(255) NULL,
          `decision` VARCHAR(255) NULL,
          `last_session_date` DATE NULL,
          `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');

      // In-place migration: add missing columns (compatible with older MySQL/MariaDB)
      await _ensureColumn(conn, 'cases', 'traded_number', 'VARCHAR(100) NULL');
      await _ensureColumn(conn, 'cases', 'roll_number', 'VARCHAR(100) NULL');
      await _ensureColumn(conn, 'cases', 'year', 'VARCHAR(10) NULL');
      await _ensureColumn(conn, 'cases', 'circuit', 'VARCHAR(255) NULL');
      await _ensureColumn(conn, 'cases', 'plaintiff', 'VARCHAR(255) NULL');
      await _ensureColumn(conn, 'cases', 'defendant', 'VARCHAR(255) NULL');
      await _ensureColumn(conn, 'cases', 'decision', 'VARCHAR(255) NULL');
      await _ensureColumn(conn, 'cases', 'last_session_date', 'DATE NULL');
      await _ensureColumn(conn, 'cases', 'reserved_for_report',
          'TINYINT(1) NOT NULL DEFAULT 0');
      await _ensureColumn(conn, 'cases', 'subject', 'LONGTEXT NULL');

      // sessions
      await conn.query('''
        CREATE TABLE IF NOT EXISTS sessions (
          id INT AUTO_INCREMENT PRIMARY KEY,
          case_id INT,
          session_date DATE,
          decision VARCHAR(255) NULL,
          notes TEXT,
          CONSTRAINT fk_sessions_case FOREIGN KEY (case_id) REFERENCES cases(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      await _ensureColumn(conn, 'sessions', 'decision', 'VARCHAR(255) NULL');

      // circuits
      await conn.query('''
        CREATE TABLE IF NOT EXISTS circuits (
          id INT AUTO_INCREMENT PRIMARY KEY,
          name VARCHAR(255) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      // migrate older circuits schema if needed (compatible with MySQL/MariaDB versions without IF NOT EXISTS)
      await _ensureColumn(conn, 'circuits', 'number', 'VARCHAR(100) NULL');
      await _ensureColumn(conn, 'circuits', 'meeting_day', 'VARCHAR(50) NULL');
      await _ensureColumn(conn, 'circuits', 'meeting_time', 'VARCHAR(20) NULL');

      // departments
      await conn.query('''
        CREATE TABLE IF NOT EXISTS departments (
          id INT AUTO_INCREMENT PRIMARY KEY,
          name VARCHAR(255) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      // attachments (linked to cases)
      // Fix potential legacy typo: attchment -> attachments
      if (await _tableExists(conn, 'attchment') &&
          !(await _tableExists(conn, 'attachments'))) {
        await conn.query('RENAME TABLE `attchment` TO `attachments`');
      }
      await conn.query('''
        CREATE TABLE IF NOT EXISTS attachments (
          id INT AUTO_INCREMENT PRIMARY KEY,
          case_id INT NOT NULL,
          type VARCHAR(100) NOT NULL,
          file_path VARCHAR(1024) NOT NULL,
          copy_date DATE NULL,
          copy_register_number VARCHAR(100) NULL,
          submit_date DATE NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT fk_attachments_case FOREIGN KEY (case_id) REFERENCES cases(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      await _ensureColumn(conn, 'attachments', 'copy_date', 'DATE NULL');
      await _ensureColumn(
          conn, 'attachments', 'copy_register_number', 'VARCHAR(100) NULL');
      await _ensureColumn(conn, 'attachments', 'submit_date', 'DATE NULL');

      // judgments
      await conn.query('''
        CREATE TABLE IF NOT EXISTS `judgments` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `case_id` INT NOT NULL,
          `session_id` INT NULL,
          `judgment_type` VARCHAR(50) NOT NULL,
          `register_number` VARCHAR(100) NULL,
          `text` LONGTEXT NOT NULL,
          `judgment_nature` VARCHAR(20) NULL,
          `appeal_deadline_days` INT NULL,
          `appeal_end_date` DATE NULL,
          `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
          `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          CONSTRAINT `fk_judgments_case` FOREIGN KEY (`case_id`) REFERENCES `cases`(`id`) ON DELETE CASCADE,
          CONSTRAINT `fk_judgments_session` FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      await _ensureColumn(conn, 'judgments', 'session_id', 'INT NULL');
      await _ensureColumn(
          conn, 'judgments', 'judgment_type', 'VARCHAR(50) NOT NULL');
      await _ensureColumn(
          conn, 'judgments', 'register_number', 'VARCHAR(100) NULL');
      await _ensureColumn(conn, 'judgments', 'text', 'LONGTEXT NOT NULL');
      await _ensureColumn(
          conn, 'judgments', 'judgment_nature', 'VARCHAR(20) NULL');
      await _ensureColumn(
          conn, 'judgments', 'appeal_deadline_days', 'INT NULL');
      await _ensureColumn(conn, 'judgments', 'appeal_end_date', 'DATE NULL');
      await _ensureColumn(
          conn, 'judgments', 'suspension_period', 'VARCHAR(20) NULL');
      await _ensureColumn(
          conn, 'judgments', 'renewal_from_suspension_date', 'DATE NULL');
      await _ensureColumn(
          conn, 'judgments', 'renewal_deadline_date', 'DATE NULL');
      await _ensureColumn(conn, 'judgments', 'created_at', 'DATETIME NULL');
      await _ensureColumn(conn, 'judgments', 'updated_at', 'DATETIME NULL');

      // سجل القضايا المشطوبة
      await conn.query('''
        CREATE TABLE IF NOT EXISTS `struck_off_cases` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `case_id` INT NOT NULL,
          `struck_off_date` DATE NOT NULL,
          `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT `fk_struck_case` FOREIGN KEY (`case_id`) REFERENCES `cases`(`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      await _ensureColumn(
          conn, 'struck_off_cases', 'struck_off_date', 'DATE NOT NULL');

      // جدول الملفات تحت الرفع
      await conn.query('''
        CREATE TABLE IF NOT EXISTS `pending_files` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `file_number` VARCHAR(100) NOT NULL,
          `file_year` VARCHAR(10) NOT NULL,
          `receipt_date` DATE NOT NULL,
          `plaintiff` VARCHAR(255) NOT NULL,
          `defendant` VARCHAR(255) NOT NULL,
          `legal_opinion` VARCHAR(100) NOT NULL,
          `case_number_after_filing` VARCHAR(100) NULL,
          `case_year_after_filing` VARCHAR(10) NULL,
          `circuit_after_filing` VARCHAR(255) NULL,
          `first_session_date` DATE NULL,
          `notes` LONGTEXT NULL,
          `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
          `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      await _ensureColumn(
          conn, 'pending_files', 'file_number', 'VARCHAR(100) NOT NULL');
      await _ensureColumn(
          conn, 'pending_files', 'file_year', 'VARCHAR(10) NOT NULL');
      await _ensureColumn(
          conn, 'pending_files', 'receipt_date', 'DATE NOT NULL');
      await _ensureColumn(
          conn, 'pending_files', 'plaintiff', 'VARCHAR(255) NOT NULL');
      await _ensureColumn(
          conn, 'pending_files', 'defendant', 'VARCHAR(255) NOT NULL');
      await _ensureColumn(
          conn, 'pending_files', 'legal_opinion', 'VARCHAR(100) NOT NULL');
      await _ensureColumn(conn, 'pending_files', 'case_number_after_filing',
          'VARCHAR(100) NULL');
      await _ensureColumn(
          conn, 'pending_files', 'case_year_after_filing', 'VARCHAR(10) NULL');
      await _ensureColumn(
          conn, 'pending_files', 'circuit_after_filing', 'VARCHAR(255) NULL');
      await _ensureColumn(
          conn, 'pending_files', 'first_session_date', 'DATE NULL');
      await _ensureColumn(conn, 'pending_files', 'notes', 'LONGTEXT NULL');
    } finally {
      await conn.close();
    }
  }

  // Execute optional SQL init script from assets once. Script path: assets/sql/init.sql
  Future<void> runInitSqlIfNeeded() async {
    const assetPath = 'assets/sql/init.sql';
    String sql;
    try {
      sql = await rootBundle.loadString(assetPath);
    } catch (_) {
      return; // no script bundled
    }
    final script = sql.trim();
    if (script.isEmpty) return;

    final hash = sha256.convert(utf8.encode(script)).toString();
    final conn = await _connect(withDb: true);
    try {
      await conn.query('''
        CREATE TABLE IF NOT EXISTS app_meta (
          k VARCHAR(100) PRIMARY KEY,
          v TEXT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ''');
      final rows = await conn.query(
          'SELECT v FROM app_meta WHERE k = ? LIMIT 1', ['init_sql_hash']);
      final existing = rows.isNotEmpty ? (rows.first[0] as String? ?? '') : '';
      if (existing == hash) return; // already applied

      final cleaned = _stripSqlComments(script);
      final statements = _splitSqlStatements(cleaned);

      await conn.transaction((ctx) async {
        for (final stmt in statements) {
          final s = stmt.trim();
          if (s.isEmpty) continue;
          await ctx.query(s);
        }
        if (rows.isEmpty) {
          await ctx.query('INSERT INTO app_meta (k, v) VALUES (?, ?)',
              ['init_sql_hash', hash]);
        } else {
          await ctx.query(
              'UPDATE app_meta SET v=? WHERE k=?', [hash, 'init_sql_hash']);
        }
      });
    } finally {
      await conn.close();
    }
  }

  // Naive comment stripper: removes -- line comments and /* */ blocks
  String _stripSqlComments(String input) {
    var out = input;
    // remove /* ... */
    out = out.replaceAll(RegExp(r"/\*.*?\*/", dotAll: true), '');
    // remove lines starting with --
    final lines = out.split(RegExp(r"\r?\n"));
    final kept = <String>[];
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('--')) continue;
      kept.add(line);
    }
    return kept.join('\n');
  }

  // Split SQL into statements by semicolons not inside quotes. Basic parser.
  List<String> _splitSqlStatements(String input) {
    final result = <String>[];
    final buf = StringBuffer();
    bool inSingle = false;
    bool inDouble = false;
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == "'" && !inDouble) {
        // handle escaped single quote ''
        if (inSingle && i + 1 < input.length && input[i + 1] == "'") {
          buf.write("''");
          i++;
          continue;
        }
        inSingle = !inSingle;
        buf.write(ch);
        continue;
      }
      if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
        buf.write(ch);
        continue;
      }
      if (ch == ';' && !inSingle && !inDouble) {
        result.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  Future<bool> _tableExists(MySqlConnection conn, String table) async {
    final rows = await conn.query(
        'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1',
        [table]);
    return ((rows.first[0] as num?)?.toInt() ?? 0) > 0;
  }

  // Ensure a column exists; if missing, add it with the provided definition
  Future<void> _ensureColumn(
    MySqlConnection conn,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await conn.query(
      "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
      [table, column],
    );
    final exists = (rows.first[0] as num?)?.toInt() == 1;
    if (!exists) {
      await conn.query('ALTER TABLE `$table` ADD COLUMN `$column` $definition');
    }
  }

  Future<void> initDatabase() async {
    await ensureDatabase();
    await ensureTables();
    await runInitSqlIfNeeded();
  }

  // ===== Backup & Restore (JSON) =====
  Future<String?> exportDatabaseToFile() async {
    final conn = await _connect();
    try {
      final data = <String, dynamic>{};
      Future<void> dumpTable(String table) async {
        final rows = await conn.query('SELECT * FROM `$table`');
        final columns = rows.fields.map((f) => f.name ?? '').toList();
        final list = <Map<String, dynamic>>[];
        for (final r in rows) {
          final map = <String, dynamic>{};
          for (var i = 0; i < columns.length; i++) {
            map[columns[i]] = _jsonSafe(r[i]);
          }
          list.add(map);
        }
        data[table] = list;
      }

      await dumpTable('cases');
      await dumpTable('sessions');
      await dumpTable('attachments');
      await dumpTable('circuits');
      await dumpTable('departments');
      await dumpTable('judgments');
      await dumpTable('struck_off_cases');

      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getDirectoryPath();
      if (dir == null) return null;
      final fileName =
          'agenda_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
      final fullPath = dir.endsWith('\\') || dir.endsWith('/')
          ? '$dir$fileName'
          : '$dir${Platform.pathSeparator}$fileName';
      await File(fullPath).writeAsString(jsonStr);
      return fullPath;
    } finally {
      await conn.close();
    }
  }

  Future<void> importDatabaseFromFile() async {
    final XFile? open = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json'])
      ],
    );
    if (open == null) return;
    final content = await open.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;

    final conn = await _connect();
    try {
      await conn.transaction((tx) async {
        Future<void> upsert(String table, List<String> cols,
            List<Map<String, dynamic>> rows) async {
          if (rows.isEmpty) return;
          final placeholders = '(${List.filled(cols.length, '?').join(',')})';
          final sql =
              'REPLACE INTO `$table` (${cols.map((c) => '`$c`').join(',')}) VALUES $placeholders';
          for (final row in rows) {
            final values = cols.map((c) => row[c]).toList();
            await tx.query(sql, values);
          }
        }

        Future<List<Map<String, dynamic>>> list(String key) async {
          final v = data[key];
          if (v is List) {
            return v.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
          }
          return <Map<String, dynamic>>[];
        }

        final cases = await list('cases');
        if (cases.isNotEmpty) {
          final cols = cases.first.keys.toList();
          await upsert('cases', cols, cases);
        }
        final sessions = await list('sessions');
        if (sessions.isNotEmpty) {
          final cols = sessions.first.keys.toList();
          await upsert('sessions', cols, sessions);
        }
        final attachments = await list('attachments');
        if (attachments.isNotEmpty) {
          final cols = attachments.first.keys.toList();
          await upsert('attachments', cols, attachments);
        }
        final circuits = await list('circuits');
        if (circuits.isNotEmpty) {
          final cols = circuits.first.keys.toList();
          await upsert('circuits', cols, circuits);
        }
        final departments = await list('departments');
        if (departments.isNotEmpty) {
          final cols = departments.first.keys.toList();
          await upsert('departments', cols, departments);
        }
        final judgments = await list('judgments');
        if (judgments.isNotEmpty) {
          final cols = judgments.first.keys.toList();
          await upsert('judgments', cols, judgments);
        }
        final struck = await list('struck_off_cases');
        if (struck.isNotEmpty) {
          final cols = struck.first.keys.toList();
          await upsert('struck_off_cases', cols, struck);
        }
      });
    } finally {
      await conn.close();
    }
  }

  // CRUD for circuits
  Future<int> createCircuit(CircuitRecord c) async {
    Future<int> insert(MySqlConnection conn) async {
      final res = await conn.query(
        'INSERT INTO `circuits` (`name`, `number`, `meeting_day`, `meeting_time`) VALUES (?,?,?,?)',
        [c.name, c.number, c.meetingDay, c.meetingTime],
      );
      return res.insertId ?? 0;
    }

    var conn = await _connect();
    try {
      return await insert(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<List<CircuitRecord>> getCircuits() async {
    final conn = await _connect();
    try {
      final rows = await conn.query(
          'SELECT `id`, `name`, `number`, `meeting_day`, `meeting_time` FROM `circuits` ORDER BY `id` DESC');
      return rows
          .map((r) => CircuitRecord(
                id: r[0] as int,
                name: r[1] as String? ?? '',
                number: r[2] as String? ?? '',
                meetingDay: r[3] as String? ?? '',
                meetingTime: r[4] as String? ?? '',
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  Future<int> updateCircuit(CircuitRecord c) async {
    if (c.id == null) return 0;
    final conn = await _connect();
    try {
      final res = await conn.query(
        'UPDATE `circuits` SET `name`=?, `number`=?, `meeting_day`=?, `meeting_time`=? WHERE `id`=?',
        [c.name, c.number, c.meetingDay, c.meetingTime, c.id],
      );
      return res.affectedRows ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<int> deleteCircuit(int id) async {
    final conn = await _connect();
    try {
      final res = await conn.query('DELETE FROM `circuits` WHERE `id`=?', [id]);
      return res.affectedRows ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<void> deleteCircuitAndCases(String circuitName) async {
    final conn = await _connect();
    try {
      await conn.transaction((_) async {
        // First, delete all cases associated with the circuit name
        await conn.query('DELETE FROM cases WHERE circuit = ?', [circuitName]);
        // Then, delete the circuit itself
        await conn.query('DELETE FROM circuits WHERE name = ?', [circuitName]);
      });
    } finally {
      await conn.close();
    }
  }

  // Count cases associated with a circuit by name (exact match)
  Future<int> getCasesCountForCircuit(String circuitName) async {
    var conn = await _connect();
    try {
      // Prefer exact match on circuit field; exclude reserved unless needed
      try {
        final rows = await conn.query(
            'SELECT COUNT(*) FROM `cases` WHERE `circuit` = ? AND `reserved_for_report`=0',
            [circuitName.trim()]);
        return (rows.first[0] as int?) ?? 0;
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          await conn.close();
          await ensureTables();
          conn = await _connect();
          try {
            final rows = await conn.query(
                'SELECT COUNT(*) FROM `cases` WHERE `circuit` = ? AND `reserved_for_report`=0',
                [circuitName.trim()]);
            return (rows.first[0] as int?) ?? 0;
          } on MySqlException catch (_) {
            final rows = await conn.query(
                'SELECT COUNT(*) FROM `cases` WHERE `circuit` = ?',
                [circuitName.trim()]);
            return (rows.first[0] as int?) ?? 0;
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // Attachments CRUD
  Future<int> addAttachment(AttachmentRecord a) async {
    Future<int> insert(MySqlConnection conn) async {
      final res = await conn.query(
        'INSERT INTO `attachments` (`case_id`, `type`, `file_path`, `copy_date`, `copy_register_number`, `submit_date`) VALUES (?,?,?,?,?,?)',
        [
          a.caseId,
          a.type,
          a.filePath,
          a.copyDate?.toIso8601String().substring(0, 10),
          a.copyRegisterNumber,
          a.submitDate?.toIso8601String().substring(0, 10),
        ],
      );
      return res.insertId ?? 0;
    }

    var conn = await _connect();
    try {
      return await insert(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      } else if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // Sessions CRUD
  Future<int> addSession(
      {required int caseId, required DateTime date, String? decision}) async {
    Future<int> executeSessionInsert(MySqlConnection conn) async {
      final res = await conn.query(
        'INSERT INTO `sessions` (`case_id`, `session_date`, `decision`) VALUES (?,?,?)',
        [caseId, date.toIso8601String().substring(0, 10), decision],
      );
      await conn.query(
          'UPDATE `cases` SET `last_session_date`=?, `decision`=? WHERE `id`=?',
          [date.toIso8601String().substring(0, 10), decision, caseId]);
      return res.insertId ?? 0;
    }

    var conn = await _connect();
    try {
      return await executeSessionInsert(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await executeSessionInsert(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<List<SessionRecord>> getSessionsForCase(int caseId) async {
    final conn = await _connect();
    try {
      final rows = await conn.query(
          'SELECT `id`, `case_id`, `session_date`, `decision` FROM `sessions` WHERE `case_id`=? ORDER BY `session_date` DESC, `id` DESC',
          [caseId]);
      return rows
          .map((r) => SessionRecord(
                id: r[0] as int,
                caseId: r[1] as int,
                sessionDate:
                    r[2] != null ? DateTime.tryParse(r[2].toString()) : null,
                decision: r[3] as String? ?? '',
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  Future<int> deleteSession(int id) async {
    final conn = await _connect();
    try {
      final res = await conn.query('DELETE FROM `sessions` WHERE `id`=?', [id]);
      return res.affectedRows ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<List<AttachmentRecord>> getAttachmentsForCase(int caseId) async {
    Future<List<AttachmentRecord>> fetch(MySqlConnection conn) async {
      final rows = await conn.query(
        'SELECT `id`, `case_id`, `type`, `file_path`, `copy_date`, `copy_register_number`, `submit_date`, `created_at` FROM `attachments` WHERE `case_id` = ? ORDER BY `id` DESC',
        [caseId],
      );
      return rows
          .map(
            (r) => AttachmentRecord(
              id: r[0] as int,
              caseId: r[1] as int,
              type: r[2] as String? ?? '',
              filePath: r[3] as String? ?? '',
              copyDate:
                  r[4] != null ? DateTime.tryParse(r[4].toString()) : null,
              copyRegisterNumber: r[5] as String?,
              submitDate:
                  r[6] != null ? DateTime.tryParse(r[6].toString()) : null,
              createdAt:
                  r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
            ),
          )
          .toList();
    }

    var conn = await _connect();
    try {
      return await fetch(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await fetch(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // إرجاع القضايا التي لديها مذكرات دفاع (type='مذكرة دفاع') بتاريخ نسخ داخل الفترة
  Future<List<CaseRecord>> getCasesWithDefenseMemosBetween(
      DateTime from, DateTime to) async {
    final conn = await _connect();
    try {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      final rows = await conn.query('''
        SELECT DISTINCT c.id, c.number, c.year, c.circuit, c.plaintiff, c.defendant,
          c.decision, c.last_session_date, c.reserved_for_report,
          a.copy_date, a.submit_date
        FROM cases c
        JOIN attachments a ON a.case_id = c.id AND a.type = 'مذكرة دفاع'
        WHERE a.copy_date IS NOT NULL
          AND a.copy_date BETWEEN ? AND ?
        ORDER BY c.id DESC
      ''', [fromStr, toStr]);
      return rows
          .map((r) => CaseRecord(
                id: r[0] as int?,
                number: r[1] as String? ?? '',
                year: r[2] as String? ?? '',
                circuit: r[3] as String? ?? '',
                plaintiff: r[4] as String? ?? '',
                defendant: r[5] as String? ?? '',
                decision: r[6] as String? ?? '',
                lastSessionDate:
                    r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                reservedForReport: (r[8] is int)
                    ? ((r[8] as int) == 1)
                    : (r[8].toString() == '1'),
                memoCopyDate:
                    r[9] != null ? DateTime.tryParse(r[9].toString()) : null,
                memoSessionDate:
                    r[10] != null ? DateTime.tryParse(r[10].toString()) : null,
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  // إرجاع القضايا التي لديها حكم نهائي مرتبط بجلسة بتاريخ داخل الفترة
  Future<List<CaseRecord>> getCasesWithFinalJudgmentsBetween(
      DateTime from, DateTime to) async {
    final conn = await _connect();
    try {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      final rows = await conn.query('''
        SELECT DISTINCT c.id, c.number, c.year, c.circuit, c.plaintiff, c.defendant,
          c.decision, c.last_session_date, c.reserved_for_report,
          s.session_date AS judgment_session_date
        FROM cases c
        JOIN judgments j ON j.case_id = c.id AND j.judgment_type = 'حكم نهائي'
        LEFT JOIN sessions s ON s.id = j.session_id
        WHERE s.session_date IS NOT NULL
          AND s.session_date BETWEEN ? AND ?
        ORDER BY c.id DESC
      ''', [fromStr, toStr]);
      return rows
          .map((r) => CaseRecord(
                id: r[0] as int?,
                number: r[1] as String? ?? '',
                year: r[2] as String? ?? '',
                circuit: r[3] as String? ?? '',
                plaintiff: r[4] as String? ?? '',
                defendant: r[5] as String? ?? '',
                decision: r[6] as String? ?? '',
                lastSessionDate:
                    r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                reservedForReport: (r[8] is int)
                    ? ((r[8] as int) == 1)
                    : (r[8].toString() == '1'),
                judgmentSessionDate:
                    r[9] != null ? DateTime.tryParse(r[9].toString()) : null,
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  // إرجاع القضايا ذات الحكم النهائي مع تصفية "طبيعة الحكم" (صالح/ضد) خلال الفترة
  Future<List<CaseRecord>> getCasesWithFinalJudgmentsByNatureBetween(
      DateTime from, DateTime to, String nature) async {
    final conn = await _connect();
    try {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      final sql = '''
        SELECT DISTINCT c.id, c.number, c.year, c.circuit, c.plaintiff, c.defendant,
          c.decision, c.last_session_date, c.reserved_for_report,
          s.session_date AS judgment_session_date
        FROM cases c
        JOIN judgments j ON j.case_id = c.id AND j.judgment_type = 'حكم نهائي' AND j.judgment_nature = ?
        LEFT JOIN sessions s ON s.id = j.session_id
        WHERE s.session_date IS NOT NULL
          AND s.session_date BETWEEN ? AND ?
        ORDER BY c.id DESC
      ''';
      final rows = await conn.query(sql, [nature, fromStr, toStr]);
      return rows
          .map((r) => CaseRecord(
                id: r[0] as int?,
                number: r[1] as String? ?? '',
                year: r[2] as String? ?? '',
                circuit: r[3] as String? ?? '',
                plaintiff: r[4] as String? ?? '',
                defendant: r[5] as String? ?? '',
                decision: r[6] as String? ?? '',
                lastSessionDate:
                    r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                reservedForReport: (r[8] is int)
                    ? ((r[8] as int) == 1)
                    : (r[8].toString() == '1'),
                judgmentSessionDate:
                    r[9] != null ? DateTime.tryParse(r[9].toString()) : null,
              ))
          .toList();
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 &&
          e.message.toLowerCase().contains('judgment_nature')) {
        try {
          await ensureTables();
        } catch (_) {}
        // retry once
        final fromStr = from.toIso8601String().substring(0, 10);
        final toStr = to.toIso8601String().substring(0, 10);
        final sql = '''
          SELECT DISTINCT c.id, c.number, c.year, c.circuit, c.plaintiff, c.defendant,
            c.decision, c.last_session_date, c.reserved_for_report,
            s.session_date AS judgment_session_date
          FROM cases c
          JOIN judgments j ON j.case_id = c.id AND j.judgment_type = 'حكم نهائي' AND j.judgment_nature = ?
          LEFT JOIN sessions s ON s.id = j.session_id
          WHERE s.session_date IS NOT NULL
            AND s.session_date BETWEEN ? AND ?
          ORDER BY c.id DESC
        ''';
        final rows = await conn.query(sql, [nature, fromStr, toStr]);
        return rows
            .map((r) => CaseRecord(
                  id: r[0] as int?,
                  number: r[1] as String? ?? '',
                  year: r[2] as String? ?? '',
                  circuit: r[3] as String? ?? '',
                  plaintiff: r[4] as String? ?? '',
                  defendant: r[5] as String? ?? '',
                  decision: r[6] as String? ?? '',
                  lastSessionDate:
                      r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                  reservedForReport: (r[8] is int)
                      ? ((r[8] as int) == 1)
                      : (r[8].toString() == '1'),
                  judgmentSessionDate:
                      r[9] != null ? DateTime.tryParse(r[9].toString()) : null,
                ))
            .toList();
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> deleteAttachment(int id) async {
    Future<int> del(MySqlConnection conn) async {
      final res =
          await conn.query('DELETE FROM `attachments` WHERE `id`=?', [id]);
      return res.affectedRows ?? 0;
    }

    var conn = await _connect();
    try {
      return await del(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await del(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // Judgments CRUD
  Future<int> addJudgment(JudgmentRecord j) async {
    Future<int> insert(MySqlConnection conn) async {
      final res = await conn.query(
        'INSERT INTO `judgments` (`case_id`, `session_id`, `judgment_type`, `register_number`, `text`, `judgment_nature`, `appeal_deadline_days`, `appeal_end_date`, `suspension_period`, `renewal_from_suspension_date`, `renewal_deadline_date`) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [
          j.caseId,
          j.sessionId,
          j.judgmentType,
          j.registerNumber,
          j.text,
          j.judgmentNature,
          j.appealDeadlineDays,
          j.appealEndDate?.toIso8601String().substring(0, 10),
          j.suspensionPeriod,
          j.renewalFromSuspensionDate?.toIso8601String().substring(0, 10),
          j.renewalDeadlineDate?.toIso8601String().substring(0, 10),
        ],
      );
      // Some environments may not return insertId; fallback to affectedRows
      final insertedId = res.insertId;
      if (insertedId != null && insertedId > 0) return insertedId;
      final affected = res.affectedRows ?? 0;
      return affected > 0 ? affected : 0;
    }

    var conn = await _connect();
    try {
      return await insert(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      } else if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<JudgmentRecord?> getJudgmentByCaseId(int caseId) async {
    Future<JudgmentRecord?> fetch(MySqlConnection conn) async {
      final rows = await conn.query(
        'SELECT `id`, `case_id`, `session_id`, `judgment_type`, `register_number`, `text`, `judgment_nature`, `appeal_deadline_days`, `appeal_end_date`, `suspension_period`, `renewal_from_suspension_date`, `renewal_deadline_date`, `created_at`, `updated_at` FROM `judgments` WHERE `case_id` = ? ORDER BY `id` DESC LIMIT 1',
        [caseId],
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      // حماية من نوع Blob (يظهر أحياناً مع أعمدة LONGTEXT)
      String toStr(dynamic v) {
        if (v == null) return '';
        if (v is String) return v;
        if (v is List<int>) {
          try {
            return utf8.decode(v);
          } catch (_) {
            return String.fromCharCodes(v);
          }
        }
        return v.toString();
      }

      final judgmentTypeVal = toStr(r[3]);
      final registerNumberVal = toStr(r[4]);
      final textVal = toStr(r[5]);
      final natureVal = toStr(r[6]);
      final suspensionPeriodVal = toStr(r[9]);
      return JudgmentRecord(
        id: r[0] as int,
        caseId: r[1] as int,
        sessionId: r[2] as int?,
        judgmentType: judgmentTypeVal,
        registerNumber: registerNumberVal.isEmpty ? null : registerNumberVal,
        text: textVal,
        judgmentNature: natureVal.isEmpty ? null : natureVal,
        appealDeadlineDays: (r[7] as int?) ??
            (r[7] is BigInt ? (r[7] as BigInt).toInt() : null),
        appealEndDate: r[8] != null ? DateTime.tryParse(r[8].toString()) : null,
        suspensionPeriod:
            suspensionPeriodVal.isEmpty ? null : suspensionPeriodVal,
        renewalFromSuspensionDate:
            r[10] != null ? DateTime.tryParse(r[10].toString()) : null,
        renewalDeadlineDate:
            r[11] != null ? DateTime.tryParse(r[11].toString()) : null,
        createdAt: r[12] != null ? DateTime.tryParse(r[12].toString()) : null,
        updatedAt: r[13] != null ? DateTime.tryParse(r[13].toString()) : null,
      );
    }

    var conn = await _connect();
    try {
      return await fetch(conn);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await fetch(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> updateJudgment(JudgmentRecord j) async {
    if (j.id == null) return 0;
    var conn = await _connect();
    try {
      final res = await conn.query(
        'UPDATE `judgments` SET `session_id`=?, `judgment_type`=?, `register_number`=?, `text`=?, `judgment_nature`=?, `appeal_deadline_days`=?, `appeal_end_date`=?, `suspension_period`=?, `renewal_from_suspension_date`=?, `renewal_deadline_date`=? WHERE `id`=?',
        [
          j.sessionId,
          j.judgmentType,
          j.registerNumber,
          j.text,
          j.judgmentNature,
          j.appealDeadlineDays,
          j.appealEndDate?.toIso8601String().substring(0, 10),
          j.suspensionPeriod,
          j.renewalFromSuspensionDate?.toIso8601String().substring(0, 10),
          j.renewalDeadlineDate?.toIso8601String().substring(0, 10),
          j.id
        ],
      );
      return res.affectedRows ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1146 ||
          e.message.toLowerCase().contains("doesn't exist") ||
          e.message.toLowerCase().contains('does not exist')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final res = await conn.query(
          'UPDATE `judgments` SET `session_id`=?, `judgment_type`=?, `register_number`=?, `text`=?, `judgment_nature`=?, `appeal_deadline_days`=?, `appeal_end_date`=?, `suspension_period`=?, `renewal_from_suspension_date`=?, `renewal_deadline_date`=? WHERE `id`=?',
          [
            j.sessionId,
            j.judgmentType,
            j.registerNumber,
            j.text,
            j.judgmentNature,
            j.appealDeadlineDays,
            j.appealEndDate?.toIso8601String().substring(0, 10),
            j.suspensionPeriod,
            j.renewalFromSuspensionDate?.toIso8601String().substring(0, 10),
            j.renewalDeadlineDate?.toIso8601String().substring(0, 10),
            j.id
          ],
        );
        return res.affectedRows ?? 0;
      } else if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final res = await conn.query(
          'UPDATE `judgments` SET `session_id`=?, `judgment_type`=?, `register_number`=?, `text`=?, `judgment_nature`=?, `appeal_deadline_days`=?, `appeal_end_date`=?, `suspension_period`=?, `renewal_from_suspension_date`=?, `renewal_deadline_date`=? WHERE `id`=?',
          [
            j.sessionId,
            j.judgmentType,
            j.registerNumber,
            j.text,
            j.judgmentNature,
            j.appealDeadlineDays,
            j.appealEndDate?.toIso8601String().substring(0, 10),
            j.suspensionPeriod,
            j.renewalFromSuspensionDate?.toIso8601String().substring(0, 10),
            j.renewalDeadlineDate?.toIso8601String().substring(0, 10),
            j.id
          ],
        );
        return res.affectedRows ?? 0;
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // Check if a case with the same number, year, and circuit already exists
  Future<bool> caseExists({
    required String number,
    required String year,
    required String circuit,
  }) async {
    final conn = await _connect();
    try {
      final rows = await conn.query(
        'SELECT COUNT(*) as count FROM `cases` WHERE `number` = ? AND `year` = ? AND `circuit` = ?',
        [number, year, circuit],
      );
      if (rows.isEmpty) return false;
      final count = rows.first[0] as int;
      return count > 0;
    } finally {
      await conn.close();
    }
  }

  // CRUD for cases
  Future<int> createCase(CaseRecord c) async {
    Future<int> insert(MySqlConnection conn) async {
      final result = await conn.query(
        'INSERT INTO `cases` (`traded_number`, `roll_number`, `number`, `year`, `circuit`, `plaintiff`, `defendant`, `decision`, `last_session_date`, `subject`) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          c.tradedNumber,
          c.rollNumber,
          c.number,
          c.year,
          c.circuit,
          c.plaintiff,
          c.defendant,
          c.decision,
          c.lastSessionDate?.toIso8601String().substring(0, 10),
          c.subject,
        ],
      );
      final newId = result.insertId ?? 0;
      // Persist first session automatically if provided
      if (newId > 0 && c.lastSessionDate != null) {
        try {
          await conn.query(
            'INSERT INTO `sessions` (`case_id`,`session_date`,`decision`) VALUES (?,?,?)',
            [
              newId,
              c.lastSessionDate!.toIso8601String().substring(0, 10),
              c.decision
            ],
          );
        } catch (_) {
          // ignore session insert failure to not block case creation
        }
      }
      return newId;
    }

    var conn = await _connect();
    try {
      return await insert(conn);
    } on MySqlException catch (e) {
      // Unknown column: attempt to migrate and retry once
      if (e.errorNumber == 1054 ||
          e.message.toLowerCase().contains('unknown column')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        return await insert(conn);
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<List<CaseRecord>> getCases() async {
    Future<List<CaseRecord>> run(MySqlConnection conn,
        {required bool withCol}) async {
      final select = withCol
          ? '''
              SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
                     (
                       SELECT MAX(s.`session_date`)
                       FROM `sessions` s
                       WHERE s.`case_id`=c.`id` AND (
                         c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                       )
                     ) AS prev_session_date,
                     c.`reserved_for_report`,
                     c.`subject`
              FROM `cases` c
              WHERE c.`reserved_for_report`=0
                AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id` = c.`id`)
              ORDER BY c.`id` DESC
            '''
          : '''
              SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
                     (
                       SELECT MAX(s.`session_date`)
                       FROM `sessions` s
                       WHERE s.`case_id`=c.`id` AND (
                         c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                       )
                     ) AS prev_session_date,
                     c.`subject`
              FROM `cases` c
              WHERE NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id` = c.`id`)
              ORDER BY c.`id` DESC
            ''';
      final rows = await conn.query(select);
      return rows.map((r) {
        return CaseRecord(
          id: r[0] as int,
          tradedNumber: _asString(r[1]) ?? '',
          rollNumber: _asString(r[2]) ?? '',
          number: _asString(r[3]) ?? '',
          year: _asString(r[4]) ?? '',
          circuit: _asString(r[5]) ?? '',
          plaintiff: _asString(r[6]) ?? '',
          defendant: _asString(r[7]) ?? '',
          decision: _asString(r[8]) ?? '',
          lastSessionDate:
              (r[9] != null) ? DateTime.tryParse(r[9].toString()) : null,
          prevSessionDate:
              (r[10] != null) ? DateTime.tryParse(r[10].toString()) : null,
          reservedForReport: withCol ? ((r[11] as int? ?? 0) == 1) : false,
          subject: withCol ? _asString(r[12]) : _asString(r[11]),
        );
      }).toList();
    }

    var conn = await _connect();
    try {
      return await run(conn, withCol: true);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        try {
          return await run(conn, withCol: true);
        } on MySqlException catch (_) {
          // fallback without column
          return await run(conn, withCol: false);
        }
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // Count of cases (excluding reserved unless specified) with graceful fallback if column missing.
  Future<int> getCasesCount({bool excludeReserved = true}) async {
    var conn = await _connect();
    try {
      final withColSql = excludeReserved
          ? 'SELECT COUNT(*) FROM `cases` c WHERE c.`reserved_for_report`=0 AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id`=c.`id` )'
          : 'SELECT COUNT(*) FROM `cases` c WHERE NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id`=c.`id` )';
      final noColSql =
          'SELECT COUNT(*) FROM `cases` c WHERE NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id`=c.`id` )';
      try {
        final r = await conn.query(withColSql);
        return r.first[0] as int? ?? 0;
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          await conn.close();
          await ensureTables();
          conn = await _connect();
          try {
            final r = await conn.query(withColSql);
            return r.first[0] as int? ?? 0;
          } on MySqlException catch (_) {
            final r = await conn.query(noColSql);
            return r.first[0] as int? ?? 0;
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // Limited slice of cases for initial lightweight loading on heavy pages (statistics)
  Future<List<CaseRecord>> getCasesLimited(int limit,
      {bool excludeReserved = true}) async {
    if (limit <= 0) return [];
    Future<List<CaseRecord>> run(MySqlConnection conn,
        {required bool withCol}) async {
      final sql = withCol
          ? (excludeReserved
              ? 'SELECT `id`, `traded_number`, `roll_number`, `number`, `year`, `circuit`, `plaintiff`, `defendant`, `decision`, `last_session_date`, `reserved_for_report`, `subject` FROM `cases` WHERE `reserved_for_report`=0 ORDER BY `id` DESC LIMIT ?'
              : 'SELECT `id`, `traded_number`, `roll_number`, `number`, `year`, `circuit`, `plaintiff`, `defendant`, `decision`, `last_session_date`, `reserved_for_report`, `subject` FROM `cases` ORDER BY `id` DESC LIMIT ?')
          : 'SELECT `id`, `traded_number`, `roll_number`, `number`, `year`, `circuit`, `plaintiff`, `defendant`, `decision`, `last_session_date`, `subject` FROM `cases` ORDER BY `id` DESC LIMIT ?';
      final rows = await conn.query(sql, [limit]);
      return rows
          .map((r) => CaseRecord(
                id: r[0] as int,
                tradedNumber: _asString(r[1]) ?? '',
                rollNumber: _asString(r[2]) ?? '',
                number: _asString(r[3]) ?? '',
                year: _asString(r[4]) ?? '',
                circuit: _asString(r[5]) ?? '',
                plaintiff: _asString(r[6]) ?? '',
                defendant: _asString(r[7]) ?? '',
                decision: _asString(r[8]) ?? '',
                lastSessionDate:
                    (r[9] != null) ? DateTime.tryParse(r[9].toString()) : null,
                reservedForReport:
                    withCol ? ((r[10] as int? ?? 0) == 1) : false,
                subject: withCol ? _asString(r[11]) : _asString(r[10]),
              ))
          .toList();
    }

    var conn = await _connect();
    try {
      return await run(conn, withCol: true);
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        try {
          return await run(conn, withCol: true);
        } on MySqlException catch (_) {
          return await run(conn, withCol: false);
        }
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> updateCase(CaseRecord c) async {
    if (c.id == null) return 0;
    final conn = await _connect();
    try {
      final result = await conn.query(
        'UPDATE `cases` SET `traded_number`=?, `roll_number`=?, `number`=?, `year`=?, `circuit`=?, `plaintiff`=?, `defendant`=?, `decision`=?, `last_session_date`=?, `subject`=? WHERE `id`=?',
        [
          c.tradedNumber,
          c.rollNumber,
          c.number,
          c.year,
          c.circuit,
          c.plaintiff,
          c.defendant,
          c.decision,
          c.lastSessionDate?.toIso8601String().substring(0, 10),
          c.subject,
          c.id
        ],
      );
      return result.affectedRows ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<int> deleteCase(int id) async {
    final conn = await _connect();
    try {
      final result = await conn.query('DELETE FROM `cases` WHERE `id`=?', [id]);
      return result.affectedRows ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<List<CaseRecord>> searchCases({
    String? number,
    String? year,
    String? circuit,
    String? plaintiff,
    String? defendant,
    String? decision,
    DateTime? sessionDate,
  }) async {
    final conn = await _connect();
    try {
      final where = <String>[];
      final params = <dynamic>[];

      // If both number & year provided, search by both together
      if ((number != null && number.isNotEmpty) &&
          (year != null && year.isNotEmpty)) {
        where.add('`number` = ?');
        params.add(number);
        where.add('`year` = ?');
        params.add(year);
      } else {
        // Otherwise ignore single number/year here; UI should validate
      }

      String like(String v) => '%${v.trim()}%';

      if (circuit != null && circuit.trim().isNotEmpty) {
        // Match exact circuit name only
        where.add('`circuit` = ?');
        params.add(circuit.trim());
      }
      if (plaintiff != null && plaintiff.trim().isNotEmpty) {
        where.add('`plaintiff` LIKE ?');
        params.add(like(plaintiff));
      }
      if (defendant != null && defendant.trim().isNotEmpty) {
        where.add('`defendant` LIKE ?');
        params.add(like(defendant));
      }
      if (decision != null && decision.trim().isNotEmpty) {
        where.add('`decision` LIKE ?');
        params.add(like(decision));
      }
      if (sessionDate != null) {
        // البحث في أي جلسة من جلسات القضية (في جدول sessions) أو في last_session_date
        where.add(
            '(`last_session_date` = ? OR EXISTS (SELECT 1 FROM `sessions` s WHERE s.`case_id` = c.`id` AND s.`session_date` = ?))');
        final dateStr = sessionDate.toIso8601String().substring(0, 10);
        params.add(dateStr);
        params.add(dateStr);
      }

      // Always exclude reserved_for_report cases from normal search
      where.add('`reserved_for_report`=0');

      final baseSqlWith = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
               (
                 SELECT MAX(s.`session_date`)
                 FROM `sessions` s
                 WHERE s.`case_id`=c.`id` AND (
                   c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                 )
               ) AS prev_session_date,
               c.`reserved_for_report`,
               c.`subject`
        FROM `cases` c
        WHERE ${where.join(' AND ')} AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id` = c.`id`)
        ORDER BY c.`id` DESC
      ''';
      final baseSqlNo = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
               (
                 SELECT MAX(s.`session_date`)
                 FROM `sessions` s
                 WHERE s.`case_id`=c.`id` AND (
                   c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                 )
               ) AS prev_session_date,
               c.`subject`
        FROM `cases` c
        WHERE ${where.where((w) => !w.contains('reserved_for_report')).join(' AND ')} AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id` = c.`id`)
        ORDER BY c.`id` DESC
      ''';

      Future<List<CaseRecord>> parse(Results rows, bool withCol) async {
        return rows
            .map((r) => CaseRecord(
                  id: r[0] as int,
                  tradedNumber: _asString(r[1]),
                  rollNumber: _asString(r[2]),
                  number: _asString(r[3]) ?? '',
                  year: _asString(r[4]) ?? '',
                  circuit: _asString(r[5]) ?? '',
                  plaintiff: _asString(r[6]) ?? '',
                  defendant: _asString(r[7]) ?? '',
                  decision: _asString(r[8]) ?? '',
                  lastSessionDate: (r[9] != null)
                      ? DateTime.tryParse(r[9].toString())
                      : null,
                  prevSessionDate: (r[10] != null)
                      ? DateTime.tryParse(r[10].toString())
                      : null,
                  reservedForReport:
                      withCol ? ((r[11] as int? ?? 0) == 1) : false,
                  subject: withCol ? _asString(r[12]) : _asString(r[11]),
                ))
            .toList();
      }

      try {
        final rows = await conn.query(baseSqlWith, params);
        return await parse(rows, true);
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          await ensureTables();
          try {
            final rows2 = await conn.query(baseSqlWith, params);
            return await parse(rows2, true);
          } on MySqlException catch (_) {
            final rows3 = await conn.query(baseSqlNo, params);
            return await parse(rows3, false);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // Search cases plus latest judgment type (optimized single query)
  Future<List<CaseWithJudgmentRecord>> searchCasesWithJudgment({
    String? number,
    String? year,
    String? plaintiff,
    String? defendant,
  }) async {
    final conn = await _connect();
    try {
      final where = <String>[];
      final params = <dynamic>[];
      bool hasNumber = number != null && number.trim().isNotEmpty;
      bool hasYear = year != null && year.trim().isNotEmpty;
      bool hasPlaintiff = plaintiff != null && plaintiff.trim().isNotEmpty;
      bool hasDefendant = defendant != null && defendant.trim().isNotEmpty;
      if (!((hasNumber && hasYear) || hasPlaintiff || hasDefendant)) {
        return <CaseWithJudgmentRecord>[];
      }
      String like(String v) => '%${v.trim()}%';
      if (hasNumber && hasYear) {
        where.add('c.`number` = ?');
        params.add(number.trim());
        where.add('c.`year` = ?');
        params.add(year.trim());
      }
      if (hasPlaintiff) {
        where.add('c.`plaintiff` LIKE ?');
        params.add(like(plaintiff));
      }
      if (hasDefendant) {
        where.add('c.`defendant` LIKE ?');
        params.add(like(defendant));
      }
      final whereSql = where.isEmpty ? '1=0' : where.join(' AND ');
      final sqlNature = '''
        SELECT c.id, c.`number`, c.`year`, c.`plaintiff`, c.`defendant`, c.`last_session_date`, j.`judgment_type`, j.`judgment_nature`, j.`appeal_end_date`
        FROM cases c
        LEFT JOIN (
          SELECT j1.case_id, j1.judgment_type, j1.judgment_nature, j1.appeal_end_date
          FROM judgments j1
          INNER JOIN (
            SELECT case_id, MAX(id) AS max_id FROM judgments GROUP BY case_id
          ) j2 ON j1.case_id = j2.case_id AND j1.id = j2.max_id
        ) j ON c.id = j.case_id
        WHERE $whereSql AND c.`reserved_for_report`=0
        ORDER BY c.id DESC
      ''';
      final sqlLegacy = sqlNature
          .replaceAll(', j.`judgment_nature`', '')
          .replaceAll(', j.`appeal_end_date`', '')
          .replaceAll(', j1.judgment_nature', '')
          .replaceAll(', j1.appeal_end_date', '')
          .replaceAll('j.`judgment_nature`', '') // remaining occurrences
          .replaceAll('j.`appeal_end_date`', '')
          .replaceAll(' j.`judgment_nature`', '')
          .replaceAll(' j.`appeal_end_date`', '')
          .replaceAll(' j1.judgment_nature', '');

      List<CaseWithJudgmentRecord> map(Results rows, bool hasNature) => rows
          .map((r) => CaseWithJudgmentRecord(
                id: r[0] as int,
                number: r[1] as String? ?? '',
                year: r[2] as String? ?? '',
                plaintiff: r[3] as String? ?? '',
                defendant: r[4] as String? ?? '',
                lastSessionDate:
                    r[5] != null ? DateTime.tryParse(r[5].toString()) : null,
                latestJudgmentType: r[6] as String?,
                latestJudgmentNature: hasNature ? r[7] as String? : null,
                appealEndDate: (hasNature && r.length > 8 && r[8] != null)
                    ? DateTime.tryParse(r[8].toString())
                    : null,
              ))
          .toList();

      try {
        final rows = await conn.query(sqlNature, params);
        return map(rows, true);
      } on MySqlException catch (e) {
        final msg = e.message.toLowerCase();
        if (e.errorNumber == 1054 &&
            (msg.contains('judgment_nature') ||
                msg.contains('appeal_end_date') ||
                msg.contains('reserved_for_report'))) {
          // try migration then retry nature query
          try {
            await ensureTables();
          } catch (_) {}
          try {
            final rows2 = await conn.query(sqlNature, params);
            return map(rows2, true);
          } catch (_) {
            // fallback to legacy without nature
            final rowsLegacy = await conn.query(sqlLegacy, params);
            return map(rowsLegacy, false);
          }
        } else if (e.errorNumber == 1054 &&
            (msg.contains('judgment_nature') ||
                msg.contains('appeal_end_date'))) {
          final rowsLegacy = await conn.query(sqlLegacy, params);
          return map(rowsLegacy, false);
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // Fetch judgments (final & nature='ضد') with appeal_end_date in [from, to]
  Future<List<JudgmentAppealDueRecord>> getJudgmentsAppealEndingSoon({
    required DateTime from,
    required DateTime to,
  }) async {
    final conn = await _connect();
    try {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      final sql = '''
        SELECT c.id, c.number, c.year, c.plaintiff, c.circuit, j.appeal_end_date
        FROM cases c
        JOIN (
          SELECT j1.case_id, j1.appeal_end_date, j1.judgment_type, j1.judgment_nature
          FROM judgments j1
          INNER JOIN (
            SELECT case_id, MAX(id) AS max_id FROM judgments GROUP BY case_id
          ) jm ON jm.case_id = j1.case_id AND jm.max_id = j1.id
        ) j ON j.case_id = c.id
        WHERE c.reserved_for_report=0
          AND j.judgment_type = 'حكم نهائي'
          AND j.judgment_nature = 'ضد'
          AND j.appeal_end_date IS NOT NULL
          AND j.appeal_end_date BETWEEN ? AND ?
        ORDER BY j.appeal_end_date ASC
      ''';
      List<JudgmentAppealDueRecord> map(Results rows) => rows.map((r) {
            final endDate = DateTime.tryParse(r[5].toString())!;
            final now = DateTime.now();
            final daysLeft = endDate
                .difference(DateTime(now.year, now.month, now.day))
                .inDays;
            return JudgmentAppealDueRecord(
              caseId: r[0] as int,
              number: _asString(r[1]) ?? '',
              year: _asString(r[2]) ?? '',
              plaintiff: _asString(r[3]) ?? '',
              circuit: _asString(r[4]) ?? '',
              appealEndDate: endDate,
              daysLeft: daysLeft,
            );
          }).toList();
      try {
        final rows = await conn.query(sql, [fromStr, toStr]);
        return map(rows);
      } on MySqlException catch (e) {
        // Handle legacy DBs missing reserved_for_report or judgment_nature columns
        if (e.errorNumber == 1054) {
          try {
            await ensureTables();
          } catch (_) {}
          final rows2 = await conn.query(sql, [fromStr, toStr]);
          return map(rows2);
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // List all cases with saved judgments (latest per case), excluding reserved
  Future<List<CaseWithJudgmentRecord>> getCasesWithSavedJudgments() async {
    final conn = await _connect();
    try {
      final sql = '''
        SELECT c.id, c.`number`, c.`year`, c.`plaintiff`, c.`defendant`, c.`last_session_date`, j.`judgment_type`, j.`judgment_nature`, j.`appeal_end_date`
        FROM cases c
        JOIN (
          SELECT j1.case_id, j1.judgment_type, j1.judgment_nature, j1.appeal_end_date
          FROM judgments j1
          INNER JOIN (
            SELECT case_id, MAX(id) AS max_id FROM judgments GROUP BY case_id
          ) j2 ON j1.case_id = j2.case_id AND j1.id = j2.max_id
        ) j ON c.id = j.case_id
        WHERE c.`reserved_for_report`=0
        ORDER BY c.id DESC
      ''';
      Future<List<CaseWithJudgmentRecord>> map(Results rows,
              {required bool hasExtra}) async =>
          rows
              .map((r) => CaseWithJudgmentRecord(
                    id: r[0] as int,
                    number: r[1] as String? ?? '',
                    year: r[2] as String? ?? '',
                    plaintiff: r[3] as String? ?? '',
                    defendant: r[4] as String? ?? '',
                    lastSessionDate: r[5] != null
                        ? DateTime.tryParse(r[5].toString())
                        : null,
                    latestJudgmentType: r[6] as String?,
                    latestJudgmentNature: hasExtra ? r[7] as String? : null,
                    appealEndDate: (hasExtra && r.length > 8 && r[8] != null)
                        ? DateTime.tryParse(r[8].toString())
                        : null,
                  ))
              .toList();

      try {
        final rows = await conn.query(sql);
        return await map(rows, hasExtra: true);
      } on MySqlException catch (e) {
        final msg = e.message.toLowerCase();
        // handle missing columns in older DBs
        if (e.errorNumber == 1054 &&
            (msg.contains('judgment_nature') ||
                msg.contains('appeal_end_date') ||
                msg.contains('reserved_for_report'))) {
          try {
            await ensureTables();
          } catch (_) {}
          try {
            final rows2 = await conn.query(sql);
            return await map(rows2, hasExtra: true);
          } catch (_) {
            final sqlLegacy = sql
                .replaceAll(', j.`judgment_nature`', '')
                .replaceAll(', j.`appeal_end_date`', '');
            final rowsLegacy = await conn.query(sqlLegacy);
            return await map(rowsLegacy, hasExtra: false);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // ====== Department (ملفات الشعبة) Support ======
  Future<int> reserveCaseForReport(int caseId) async {
    var conn = await _connect();
    try {
      final res = await conn.query(
          'UPDATE `cases` SET `reserved_for_report`=1 WHERE `id`=? AND `reserved_for_report`=0',
          [caseId]);
      return res.affectedRows ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final res = await conn.query(
            'UPDATE `cases` SET `reserved_for_report`=1 WHERE `id`=?',
            [caseId]);
        return res.affectedRows ?? 0;
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<int> unreserveCaseFromReport(int caseId) async {
    var conn = await _connect();
    try {
      final res = await conn.query(
          'UPDATE `cases` SET `reserved_for_report`=0 WHERE `id`=? AND `reserved_for_report`=1',
          [caseId]);
      return res.affectedRows ?? 0;
    } on MySqlException catch (e) {
      if (e.errorNumber == 1054 && e.message.contains('reserved_for_report')) {
        await conn.close();
        await ensureTables();
        conn = await _connect();
        final res = await conn.query(
            'UPDATE `cases` SET `reserved_for_report`=0 WHERE `id`=?',
            [caseId]);
        return res.affectedRows ?? 0;
      }
      rethrow;
    } finally {
      await conn.close();
    }
  }

  // إعادة الدعوى إلى المرافعة مع تحديد دائرة جديدة + جلسة وقرار جديدين (داخل معاملة واحدة)
  Future<void> repleadCaseToCircuit({
    required int caseId,
    required String circuitName,
    required DateTime sessionDate,
    required String decision,
  }) async {
    final conn = await _connect();
    try {
      await conn.transaction((tx) async {
        final dateStr = sessionDate.toIso8601String().substring(0, 10);
        try {
          await tx.query(
            'UPDATE `cases` SET `circuit`=?, `decision`=?, `last_session_date`=?, `reserved_for_report`=0 WHERE `id`=?',
            [circuitName, decision, dateStr, caseId],
          );
        } on MySqlException catch (e) {
          if (e.errorNumber == 1054 &&
              e.message.toLowerCase().contains('reserved_for_report')) {
            await tx.query(
              'UPDATE `cases` SET `circuit`=?, `decision`=?, `last_session_date`=? WHERE `id`=?',
              [circuitName, decision, dateStr, caseId],
            );
          } else {
            rethrow;
          }
        }
        await tx.query(
          'INSERT INTO `sessions` (`case_id`, `session_date`, `decision`) VALUES (?,?,?)',
          [caseId, dateStr, decision],
        );
      });
    } finally {
      await conn.close();
    }
  }

  Future<List<CaseRecord>> getReservedCasesForDepartment({
    String? number,
    String? year,
    String? plaintiff,
    String? defendant,
    String? circuit,
  }) async {
    var conn = await _connect();
    try {
      final where = <String>[];
      final params = <dynamic>[];
      String like(String v) => '%${v.trim()}%';

      // Filters
      if (number != null && number.trim().isNotEmpty) {
        where.add('`number` = ?');
        params.add(number.trim());
      }
      if (year != null && year.trim().isNotEmpty) {
        where.add('`year` = ?');
        params.add(year.trim());
      }
      if (plaintiff != null && plaintiff.trim().isNotEmpty) {
        where.add('`plaintiff` LIKE ?');
        params.add(like(plaintiff));
      }
      if (defendant != null && defendant.trim().isNotEmpty) {
        where.add('`defendant` LIKE ?');
        params.add(like(defendant));
      }
      if (circuit != null && circuit.trim().isNotEmpty) {
        // Match exact circuit name only
        where.add('`circuit` = ?');
        params.add(circuit.trim());
      }

      // Always restrict to reserved cases (department files)
      where.add('`reserved_for_report`=1');

      final baseWhere = where.isEmpty ? '1=1' : where.join(' AND ');

      final sqlWith = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
               (
                 SELECT MAX(s.`session_date`)
                 FROM `sessions` s
                 WHERE s.`case_id`=c.`id` AND (
                   c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                 )
               ) AS prev_session_date,
               c.`reserved_for_report`,
               c.`subject`
        FROM `cases` c
        WHERE $baseWhere
        ORDER BY c.`id` DESC
      ''';
      final sqlNo = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`,
               (
                 SELECT MAX(s.`session_date`)
                 FROM `sessions` s
                 WHERE s.`case_id`=c.`id` AND (
                   c.`last_session_date` IS NULL OR s.`session_date` < c.`last_session_date`
                 )
               ) AS prev_session_date,
               c.`subject`
        FROM `cases` c
        WHERE ${baseWhere.replaceAll(' AND `reserved_for_report`=1', '').replaceAll('`reserved_for_report`=1 AND ', '').replaceAll('`reserved_for_report`=1', '1=1')}
        ORDER BY c.`id` DESC
      ''';

      List<CaseRecord> parse(Results rows, bool withCol) => rows
          .map((r) => CaseRecord(
                id: r[0] as int,
                tradedNumber: _asString(r[1]),
                rollNumber: _asString(r[2]),
                number: _asString(r[3]) ?? '',
                year: _asString(r[4]) ?? '',
                circuit: _asString(r[5]) ?? '',
                plaintiff: _asString(r[6]) ?? '',
                defendant: _asString(r[7]) ?? '',
                decision: _asString(r[8]) ?? '',
                lastSessionDate:
                    (r[9] != null) ? DateTime.tryParse(r[9].toString()) : null,
                prevSessionDate: (r[10] != null)
                    ? DateTime.tryParse(r[10].toString())
                    : null,
                reservedForReport: withCol ? ((r[11] as int? ?? 0) == 1) : true,
                subject: withCol ? _asString(r[12]) : _asString(r[11]),
              ))
          .toList();

      try {
        final rows = await conn.query(sqlWith, params);
        return parse(rows, true);
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.toLowerCase().contains('reserved_for_report')) {
          // attempt migration then retry
          try {
            await ensureTables();
          } catch (_) {}
          try {
            final rows2 = await conn.query(sqlWith, params);
            return parse(rows2, true);
          } catch (_) {
            final rowsLegacy = await conn.query(sqlNo, params);
            return parse(rowsLegacy, false);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  Future<List<CaseRecord>> getCasesBySessionDateAndCircuit({
    required DateTime sessionDate,
    required String circuit,
  }) async {
    final dateStr = sessionDate.toIso8601String().substring(0, 10);
    var conn = await _connect();
    try {
      final sqlWith =
          'SELECT `id`,`number`,`year`,`circuit`,`plaintiff`,`defendant`,`decision`,`last_session_date`,`reserved_for_report`,`subject` FROM `cases` WHERE `last_session_date`=? AND `circuit`=? AND `reserved_for_report`=0 ORDER BY `id` DESC';
      final sqlNo =
          'SELECT `id`,`number`,`year`,`circuit`,`plaintiff`,`defendant`,`decision`,`last_session_date`,`subject` FROM `cases` WHERE `last_session_date`=? AND `circuit`=? ORDER BY `id` DESC';
      List<CaseRecord> parse(Results rows, bool withCol) => rows
          .map((r) => CaseRecord(
                id: r[0] as int,
                tradedNumber: null,
                rollNumber: null,
                number: _asString(r[1]) ?? '',
                year: _asString(r[2]) ?? '',
                circuit: _asString(r[3]) ?? '',
                plaintiff: _asString(r[4]) ?? '',
                defendant: _asString(r[5]) ?? '',
                decision: _asString(r[6]) ?? '',
                lastSessionDate:
                    r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                prevSessionDate: null,
                reservedForReport: withCol ? ((r[8] as int? ?? 0) == 1) : false,
                subject: withCol ? _asString(r[9]) : _asString(r[8]),
              ))
          .toList();

      try {
        final rows = await conn.query(sqlWith, [dateStr, circuit]);
        return parse(rows, true);
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          await ensureTables();
          try {
            final rows2 = await conn.query(sqlWith, [dateStr, circuit]);
            return parse(rows2, true);
          } on MySqlException catch (_) {
            final rows3 = await conn.query(sqlNo, [dateStr, circuit]);
            return parse(rows3, false);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  // Cases not migrated for more than [days] days (last_session_date older than today - days),
  // excluding reserved-for-report, struck-off, and cases with final judgment.
  Future<List<CaseRecord>> getStaleCases({int days = 4}) async {
    var conn = await _connect();
    try {
      final withCol = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`, c.`reserved_for_report`, c.`subject`
        FROM `cases` c
        WHERE c.`last_session_date` IS NOT NULL
          AND c.`last_session_date` < DATE_SUB(CURDATE(), INTERVAL ? DAY)
          AND c.`reserved_for_report`=0
          AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id`=c.`id`)
          AND NOT EXISTS (
            SELECT 1 FROM `judgments` j
            WHERE j.`case_id` = c.`id` AND j.`judgment_type` = 'حكم نهائي'
          )
        ORDER BY c.`last_session_date` ASC, c.`id` DESC
      ''';
      final noCol = '''
        SELECT c.`id`, c.`traded_number`, c.`roll_number`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`, c.`subject`
        FROM `cases` c
        WHERE c.`last_session_date` IS NOT NULL
          AND c.`last_session_date` < DATE_SUB(CURDATE(), INTERVAL ? DAY)
          AND NOT EXISTS (SELECT 1 FROM `struck_off_cases` so WHERE so.`case_id`=c.`id`)
          AND NOT EXISTS (
            SELECT 1 FROM `judgments` j
            WHERE j.`case_id` = c.`id` AND j.`judgment_type` = 'حكم نهائي'
          )
        ORDER BY c.`last_session_date` ASC, c.`id` DESC
      ''';
      List<CaseRecord> parse(Results rows, {required bool withCol}) => rows
          .map((r) => CaseRecord(
                id: r[0] as int,
                tradedNumber: _asString(r[1]),
                rollNumber: _asString(r[2]),
                number: _asString(r[3]) ?? '',
                year: _asString(r[4]) ?? '',
                circuit: _asString(r[5]) ?? '',
                plaintiff: _asString(r[6]) ?? '',
                defendant: _asString(r[7]) ?? '',
                decision: _asString(r[8]) ?? '',
                lastSessionDate:
                    (r[9] != null) ? DateTime.tryParse(r[9].toString()) : null,
                reservedForReport:
                    withCol ? ((r[10] as int? ?? 0) == 1) : false,
                subject: withCol ? _asString(r[11]) : _asString(r[10]),
              ))
          .toList();

      try {
        final rows = await conn.query(withCol, [days]);
        return parse(rows, withCol: true);
      } on MySqlException catch (e) {
        if (e.errorNumber == 1054 &&
            e.message.contains('reserved_for_report')) {
          try {
            await ensureTables();
          } catch (_) {}
          try {
            final rows2 = await conn.query(withCol, [days]);
            return parse(rows2, withCol: true);
          } catch (_) {
            final rows3 = await conn.query(noCol, [days]);
            return parse(rows3, withCol: false);
          }
        }
        rethrow;
      }
    } finally {
      await conn.close();
    }
  }

  Future<BulkMigrationResult> bulkAddSessionForCases({
    required List<int> caseIds,
    required DateTime newDate,
    String? decision,
  }) async {
    if (caseIds.isEmpty) {
      return BulkMigrationResult(total: 0, success: 0, failedCaseIds: const []);
    }
    final dateStr = newDate.toIso8601String().substring(0, 10);
    final failed = <int>[];
    var success = 0;
    final conn = await _connect();
    try {
      await conn.query('START TRANSACTION');
      for (final id in caseIds) {
        try {
          await conn.query(
            'INSERT INTO `sessions` (`case_id`,`session_date`,`decision`) VALUES (?,?,?)',
            [id, dateStr, decision],
          );
          await conn.query(
            'UPDATE `cases` SET `last_session_date`=?, `decision`=? WHERE `id`=?',
            [dateStr, decision, id],
          );
          success++;
        } catch (_) {
          failed.add(id);
        }
      }
      await conn.query('COMMIT');
    } catch (e) {
      try {
        await conn.query('ROLLBACK');
      } catch (_) {}
      rethrow;
    } finally {
      await conn.close();
    }
    return BulkMigrationResult(
        total: caseIds.length, success: success, failedCaseIds: failed);
  }

  // Batch fetch latest judgment type for given case IDs
  Future<Map<int, String>> getLatestJudgmentTypesForCases(
      List<int> caseIds) async {
    if (caseIds.isEmpty) return {};
    final conn = await _connect();
    try {
      // Use IN clause; chunk if large
      const chunkSize = 500;
      final result = <int, String>{};
      for (var i = 0; i < caseIds.length; i += chunkSize) {
        final chunk = caseIds.sublist(
            i, i + chunkSize > caseIds.length ? caseIds.length : i + chunkSize);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final sql = '''
          SELECT j.case_id, j.judgment_type
          FROM judgments j
          INNER JOIN (
            SELECT case_id, MAX(id) AS max_id FROM judgments WHERE case_id IN ($placeholders) GROUP BY case_id
          ) x ON j.case_id = x.case_id AND j.id = x.max_id
        ''';
        final rows = await conn.query(sql, chunk);
        for (final r in rows) {
          final cid = r[0] as int?;
          final jt = r[1] as String?;
          if (cid != null && jt != null) {
            result[cid] = jt;
          }
        }
      }
      return result;
    } finally {
      await conn.close();
    }
  }

  // ===== Struck-off register API =====
  Future<void> strikeOffCase(
      {required int caseId, DateTime? strikeDate}) async {
    final conn = await _connect();
    try {
      await conn.transaction((tx) async {
        // use provided strikeDate or last_session_date or today
        DateTime date = strikeDate ?? DateTime.now();
        final r = await tx.query(
            'SELECT `last_session_date` FROM `cases` WHERE `id`=? LIMIT 1',
            [caseId]);
        if (r.isNotEmpty && r.first[0] != null) {
          final d = DateTime.tryParse(r.first[0].toString());
          if (d != null) date = d;
        }
        final ds = date.toIso8601String().substring(0, 10);
        // record session
        await tx.query(
            'INSERT INTO `sessions` (`case_id`,`session_date`,`decision`) VALUES (?,?,?)',
            [caseId, ds, 'شطب الدعوى']);
        // update case
        await tx.query(
            'UPDATE `cases` SET `decision`=?, `last_session_date`=? WHERE `id`=?',
            ['شطب الدعوى', ds, caseId]);
        // add to register if not exists
        final ex = await tx.query(
            'SELECT 1 FROM `struck_off_cases` WHERE `case_id`=? LIMIT 1',
            [caseId]);
        if (ex.isEmpty) {
          await tx.query(
              'INSERT INTO `struck_off_cases` (`case_id`,`struck_off_date`) VALUES (?,?)',
              [caseId, ds]);
        }
      });
    } finally {
      await conn.close();
    }
  }

  Future<void> restoreCaseFromStruckOff(int caseId) async {
    final conn = await _connect();
    try {
      await conn
          .query('DELETE FROM `struck_off_cases` WHERE `case_id`=?', [caseId]);
    } finally {
      await conn.close();
    }
  }

  Future<List<StruckOffCaseRecord>> getStruckOffCases() async {
    final conn = await _connect();
    try {
      final rows = await conn.query('''
        SELECT c.`id`, c.`number`, c.`year`, c.`circuit`, c.`plaintiff`, c.`defendant`, c.`decision`, c.`last_session_date`, so.`struck_off_date`
        FROM `struck_off_cases` so
        JOIN `cases` c ON c.`id` = so.`case_id`
        ORDER BY so.`id` DESC
      ''');
      return rows
          .map((r) => StruckOffCaseRecord(
                caseId: r[0] as int,
                number: _asString(r[1]) ?? '',
                year: _asString(r[2]) ?? '',
                circuit: _asString(r[3]) ?? '',
                plaintiff: _asString(r[4]) ?? '',
                defendant: _asString(r[5]) ?? '',
                decision: _asString(r[6]) ?? '',
                lastSessionDate:
                    r[7] != null ? DateTime.tryParse(r[7].toString()) : null,
                struckOffDate:
                    r[8] != null ? DateTime.tryParse(r[8].toString()) : null,
              ))
          .toList();
    } finally {
      await conn.close();
    }
  }

  Future<int> getStruckOffCasesCount() async {
    final conn = await _connect();
    try {
      final rows = await conn.query('SELECT COUNT(*) FROM `struck_off_cases`');
      return (rows.first[0] as int?) ?? 0;
    } finally {
      await conn.close();
    }
  }

  // ====== Pending Files (ملفات تحت الرفع) ======
  Future<int> addPendingFile(PendingFileRecord file) async {
    final conn = await _connect();
    try {
      final result = await conn.query('''
        INSERT INTO `pending_files` (
          `file_number`, `file_year`, `receipt_date`, `plaintiff`, `defendant`,
          `legal_opinion`, `case_number_after_filing`, `case_year_after_filing`,
          `circuit_after_filing`, `first_session_date`, `notes`
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        file.fileNumber,
        file.fileYear,
        file.receiptDate.toIso8601String().substring(0, 10),
        file.plaintiff,
        file.defendant,
        file.legalOpinion,
        file.caseNumberAfterFiling,
        file.caseYearAfterFiling,
        file.circuitAfterFiling,
        file.firstSessionDate?.toIso8601String().substring(0, 10),
        file.notes,
      ]);
      return result.insertId ?? 0;
    } finally {
      await conn.close();
    }
  }

  Future<void> updatePendingFile(PendingFileRecord file) async {
    final conn = await _connect();
    try {
      await conn.query('''
        UPDATE `pending_files`
        SET `file_number` = ?, `file_year` = ?, `receipt_date` = ?,
            `plaintiff` = ?, `defendant` = ?, `legal_opinion` = ?,
            `case_number_after_filing` = ?, `case_year_after_filing` = ?,
            `circuit_after_filing` = ?, `first_session_date` = ?, `notes` = ?
        WHERE `id` = ?
      ''', [
        file.fileNumber,
        file.fileYear,
        file.receiptDate.toIso8601String().substring(0, 10),
        file.plaintiff,
        file.defendant,
        file.legalOpinion,
        file.caseNumberAfterFiling,
        file.caseYearAfterFiling,
        file.circuitAfterFiling,
        file.firstSessionDate?.toIso8601String().substring(0, 10),
        file.notes,
        file.id,
      ]);
    } finally {
      await conn.close();
    }
  }

  Future<void> deletePendingFile(int id) async {
    final conn = await _connect();
    try {
      await conn.query('DELETE FROM `pending_files` WHERE `id` = ?', [id]);
    } finally {
      await conn.close();
    }
  }

  Future<List<PendingFileRecord>> searchPendingFiles({
    String? fileNumber,
    String? fileYear,
    String? plaintiff,
    String? defendant,
  }) async {
    final conn = await _connect();
    try {
      String sql = '''
        SELECT `id`, `file_number`, `file_year`, `receipt_date`, `plaintiff`, `defendant`,
               `legal_opinion`, `case_number_after_filing`, `case_year_after_filing`,
               `circuit_after_filing`, `first_session_date`, `notes`, `created_at`, `updated_at`
        FROM `pending_files`
        WHERE 1=1
      ''';
      final params = <String>[];
      if (fileNumber != null && fileNumber.isNotEmpty) {
        sql += ' AND `file_number` LIKE ?';
        params.add('%$fileNumber%');
      }
      if (fileYear != null && fileYear.isNotEmpty) {
        sql += ' AND `file_year` = ?';
        params.add(fileYear);
      }
      if (plaintiff != null && plaintiff.isNotEmpty) {
        sql += ' AND `plaintiff` LIKE ?';
        params.add('%$plaintiff%');
      }
      if (defendant != null && defendant.isNotEmpty) {
        sql += ' AND `defendant` LIKE ?';
        params.add('%$defendant%');
      }
      sql += ' ORDER BY `id` DESC';

      final rows = await conn.query(sql, params);
      return rows.map((r) {
        return PendingFileRecord(
          id: r[0] as int,
          fileNumber: _asString(r[1]) ?? '',
          fileYear: _asString(r[2]) ?? '',
          receiptDate: DateTime.parse(r[3].toString()),
          plaintiff: _asString(r[4]) ?? '',
          defendant: _asString(r[5]) ?? '',
          legalOpinion: _asString(r[6]) ?? '',
          caseNumberAfterFiling: _asString(r[7]),
          caseYearAfterFiling: _asString(r[8]),
          circuitAfterFiling: _asString(r[9]),
          firstSessionDate:
              r[10] != null ? DateTime.tryParse(r[10].toString()) : null,
          notes: _asString(r[11]),
          createdAt: r[12] != null ? DateTime.tryParse(r[12].toString()) : null,
          updatedAt: r[13] != null ? DateTime.tryParse(r[13].toString()) : null,
        );
      }).toList();
    } finally {
      await conn.close();
    }
  }

  Future<List<PendingFileRecord>> getAllPendingFiles() async {
    final conn = await _connect();
    try {
      final rows = await conn.query('''
        SELECT `id`, `file_number`, `file_year`, `receipt_date`, `plaintiff`, `defendant`,
               `legal_opinion`, `case_number_after_filing`, `case_year_after_filing`,
               `circuit_after_filing`, `first_session_date`, `notes`, `created_at`, `updated_at`
        FROM `pending_files`
        ORDER BY `id` DESC
      ''');
      return rows.map((r) {
        return PendingFileRecord(
          id: r[0] as int,
          fileNumber: _asString(r[1]) ?? '',
          fileYear: _asString(r[2]) ?? '',
          receiptDate: DateTime.parse(r[3].toString()),
          plaintiff: _asString(r[4]) ?? '',
          defendant: _asString(r[5]) ?? '',
          legalOpinion: _asString(r[6]) ?? '',
          caseNumberAfterFiling: _asString(r[7]),
          caseYearAfterFiling: _asString(r[8]),
          circuitAfterFiling: _asString(r[9]),
          firstSessionDate:
              r[10] != null ? DateTime.tryParse(r[10].toString()) : null,
          notes: _asString(r[11]),
          createdAt: r[12] != null ? DateTime.tryParse(r[12].toString()) : null,
          updatedAt: r[13] != null ? DateTime.tryParse(r[13].toString()) : null,
        );
      }).toList();
    } finally {
      await conn.close();
    }
  }

  Future<int> getPendingFilesCount() async {
    final conn = await _connect();
    try {
      final rows = await conn.query('SELECT COUNT(*) FROM `pending_files`');
      return (rows.first[0] as int?) ?? 0;
    } finally {
      await conn.close();
    }
  }
}

class BulkMigrationResult {
  final int total;
  final int success;
  final List<int> failedCaseIds;
  const BulkMigrationResult({
    required this.total,
    required this.success,
    required this.failedCaseIds,
  });
}

class CaseRecord {
  final int? id;
  final String? tradedNumber; // رقم المتداول (اختياري)
  final String? rollNumber; // رقم الرول (اختياري)
  final String number;
  final String year;
  final String circuit;
  final String plaintiff;
  final String defendant;
  final String decision;
  final DateTime? lastSessionDate;
  final DateTime? prevSessionDate; // الجلسة السابقة مباشرة
  final bool reservedForReport;
  // إحصائيات: تواريخ إضافية
  final DateTime? memoCopyDate; // تاريخ نسخ المذكرة (مذكرة دفاع)
  final DateTime?
      memoSessionDate; // تاريخ جلسة تقديم/نسخ المذكرة (قد تساوي submit_date أو جلسة مرتبطة)
  final DateTime? judgmentSessionDate; // جلسة صدور الحكم النهائي
  final String? subject; // موضوع الدعوى (اختياري)

  CaseRecord({
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
    this.reservedForReport = false,
    this.memoCopyDate,
    this.memoSessionDate,
    this.judgmentSessionDate,
    this.subject,
  });
}

class CircuitRecord {
  final int? id;
  final String name;
  final String number;
  final String meetingDay;
  final String meetingTime;

  CircuitRecord({
    this.id,
    required this.name,
    required this.number,
    required this.meetingDay,
    required this.meetingTime,
  });
}

class AttachmentRecord {
  final int? id;
  final int caseId;
  final String type;
  final String filePath;
  final DateTime? copyDate;
  final String? copyRegisterNumber; // رقم القيد فى سجل النسخ (اختياري)
  final DateTime? submitDate;
  final DateTime? createdAt;

  AttachmentRecord({
    this.id,
    required this.caseId,
    required this.type,
    required this.filePath,
    this.copyDate,
    this.copyRegisterNumber,
    this.submitDate,
    this.createdAt,
  });
}

class SessionRecord {
  final int? id;
  final int caseId;
  final DateTime? sessionDate;
  final String decision;

  SessionRecord({
    this.id,
    required this.caseId,
    this.sessionDate,
    required this.decision,
  });
}

class JudgmentRecord {
  final int? id;
  final int caseId;
  final int? sessionId;
  final String judgmentType; // 'حكم تمهيدى' أو 'حكم نهائي'
  final String? registerNumber; // رقم القيد فى سجل الأحكام (للحكم النهائي)
  final String text; // منطوق الحكم
  final String?
      judgmentNature; // للحكم النهائي: 'ضد' أو 'صالح', للحكم التمهيدي: 'وقف جزائى' أو 'وقف تعليقى'
  final int? appealDeadlineDays; // 8/10/15/40/60 when nature='ضد' في حكم نهائي
  final DateTime? appealEndDate; // session_date + days للحكم النهائي
  final String? suspensionPeriod; // للوقف الجزائي: 'اسبوع' أو '15 يوم' أو 'شهر'
  final DateTime?
      renewalFromSuspensionDate; // تاريخ التجديد من الوقف الجزائى (اليوم التالي لانتهاء الوقف)
  final DateTime?
      renewalDeadlineDate; // تاريخ انتهاء ميعاد التجديد (شهر إلا يوم من تاريخ انتهاء الوقف)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  JudgmentRecord({
    this.id,
    required this.caseId,
    this.sessionId,
    required this.judgmentType,
    this.registerNumber,
    required this.text,
    this.judgmentNature,
    this.appealDeadlineDays,
    this.appealEndDate,
    this.suspensionPeriod,
    this.renewalFromSuspensionDate,
    this.renewalDeadlineDate,
    this.createdAt,
    this.updatedAt,
  });
}

class CaseWithJudgmentRecord {
  final int id;
  final String number;
  final String year;
  final String plaintiff;
  final String defendant;
  final DateTime? lastSessionDate;
  final String? latestJudgmentType; // null => لم يتم الحكم
  final String? latestJudgmentNature; // null if not final or not set
  final DateTime? appealEndDate; // null unless nature='ضد' and provided

  CaseWithJudgmentRecord({
    required this.id,
    required this.number,
    required this.year,
    required this.plaintiff,
    required this.defendant,
    required this.lastSessionDate,
    required this.latestJudgmentType,
    required this.latestJudgmentNature,
    this.appealEndDate,
  });
}

class MonthlyCaseSessionRecord {
  final int caseId;
  final String number;
  final String year;
  final String plaintiff;
  final String defendant;
  final DateTime? sessionDate;
  final String sessionDecision;
  final String circuit;

  MonthlyCaseSessionRecord({
    required this.caseId,
    required this.number,
    required this.year,
    required this.plaintiff,
    required this.defendant,
    required this.sessionDate,
    required this.sessionDecision,
    required this.circuit,
  });
}

class JudgmentAppealDueRecord {
  final int caseId;
  final String number;
  final String year;
  final String plaintiff;
  final String circuit;
  final DateTime appealEndDate;
  final int daysLeft;

  JudgmentAppealDueRecord({
    required this.caseId,
    required this.number,
    required this.year,
    required this.plaintiff,
    required this.circuit,
    required this.appealEndDate,
    required this.daysLeft,
  });
}

class StruckOffCaseRecord {
  final int caseId;
  final String number;
  final String year;
  final String circuit;
  final String plaintiff;
  final String defendant;
  final String decision;
  final DateTime? lastSessionDate;
  final DateTime? struckOffDate;

  StruckOffCaseRecord({
    required this.caseId,
    required this.number,
    required this.year,
    required this.circuit,
    required this.plaintiff,
    required this.defendant,
    required this.decision,
    required this.lastSessionDate,
    required this.struckOffDate,
  });
}

class PendingFileRecord {
  final int? id;
  final String fileNumber;
  final String fileYear;
  final DateTime receiptDate;
  final String plaintiff;
  final String defendant;
  final String
      legalOpinion; // 'اقامة الدعوى / الطعن بموجب صحيفة' أو 'حفظ الملف وعدم اقامة الدعوى / الطعن'
  final String? caseNumberAfterFiling;
  final String? caseYearAfterFiling;
  final String? circuitAfterFiling;
  final DateTime? firstSessionDate;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PendingFileRecord({
    this.id,
    required this.fileNumber,
    required this.fileYear,
    required this.receiptDate,
    required this.plaintiff,
    required this.defendant,
    required this.legalOpinion,
    this.caseNumberAfterFiling,
    this.caseYearAfterFiling,
    this.circuitAfterFiling,
    this.firstSessionDate,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });
}
