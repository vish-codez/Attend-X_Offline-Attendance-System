import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendance_model.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_local.db');

    _db = await openDatabase(
      path,
      version: 2, // bumped version to run migration
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        student_id INTEGER NOT NULL,
        student_name TEXT,
        subject_id INTEGER NOT NULL,
        subject_name TEXT,
        teacher_id INTEGER NOT NULL,
        attendance_date TEXT NOT NULL,
        time_slot TEXT,
        status TEXT NOT NULL DEFAULT 'PRESENT',
        marked_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE otp_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        otp TEXT NOT NULL,
        subject_id INTEGER NOT NULL,
        teacher_id INTEGER NOT NULL,
        time_slot TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        is_used INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Cache table for subject names
    await db.execute('''
      CREATE TABLE subject_cache (
        subject_id INTEGER PRIMARY KEY,
        subject_name TEXT NOT NULL,
        subject_code TEXT,
        department_name TEXT,
        year_of_study INTEGER
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_attendance_synced ON attendance_records(is_synced)');
  }

  // Migration: add new columns to existing installs
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add student_name and subject_name columns if they don't exist
      try {
        await db.execute(
            'ALTER TABLE attendance_records ADD COLUMN student_name TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE attendance_records ADD COLUMN subject_name TEXT');
      } catch (_) {}

      // Create subject_cache table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS subject_cache (
            subject_id INTEGER PRIMARY KEY,
            subject_name TEXT NOT NULL,
            subject_code TEXT,
            department_name TEXT,
            year_of_study INTEGER
          )
        ''');
      } catch (_) {}
    }
  }

  Database get db => _db!;

  // ── Attendance ────────────────────────────────────────────────
  Future<int> insertAttendance(AttendanceRecord record) async {
    return await db.insert(
      'attendance_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<AttendanceRecord>> getUnsyncedRecords() async {
    final rows = await db.query(
      'attendance_records',
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<void> markAsSynced(List<String> syncIds) async {
    if (syncIds.isEmpty) return;
    final placeholders = syncIds.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE attendance_records SET is_synced = 1 WHERE sync_id IN ($placeholders)',
      syncIds,
    );
  }

  Future<List<AttendanceRecord>> getAttendanceByStudent(int studentId) async {
    final rows = await db.query(
      'attendance_records',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'attendance_date DESC, marked_at DESC',
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<bool> hasAlreadyMarked(
      int studentId, int subjectId, String date, String timeSlot) async {
    final rows = await db.query(
      'attendance_records',
      where:
      'student_id = ? AND subject_id = ? AND attendance_date = ? AND time_slot = ?',
      whereArgs: [studentId, subjectId, date, timeSlot],
    );
    return rows.isNotEmpty;
  }

  Future<List<AttendanceRecord>> getAttendanceByDate(String date) async {
    final rows = await db.query(
      'attendance_records',
      where: 'attendance_date = ?',
      whereArgs: [date],
      orderBy: 'marked_at ASC',
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  // ── Subject cache — store subject names for offline display ──
  Future<void> cacheSubjects(List<dynamic> subjects) async {
    final batch = db.batch();
    for (final s in subjects) {
      final dept = s['department'];
      batch.insert(
        'subject_cache',
        {
          'subject_id': s['id'],
          'subject_name': s['name'] ?? '',
          'subject_code': s['code'] ?? '',
          'department_name': dept != null ? dept['name'] : '',
          'year_of_study': s['yearOfStudy'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<String?> getSubjectName(int subjectId) async {
    final rows = await db.query(
      'subject_cache',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
    );
    if (rows.isEmpty) return null;
    return rows.first['subject_name'] as String?;
  }

  Future<Map<int, String>> getAllCachedSubjectNames() async {
    final rows = await db.query('subject_cache');
    return {
      for (final r in rows)
        (r['subject_id'] as int): (r['subject_name'] as String)
    };
  }

  // ── OTP Sessions ──────────────────────────────────────────────
  Future<int> saveOtpSession({
    required String otp,
    required int subjectId,
    required int teacherId,
    required String timeSlot,
    required DateTime expiresAt,
  }) async {
    return await db.insert('otp_sessions', {
      'otp': otp,
      'subject_id': subjectId,
      'teacher_id': teacherId,
      'time_slot': timeSlot,
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'is_used': 0,
    });
  }

  Future<Map<String, dynamic>?> validateLocalOtp(String otp) async {
    final rows = await db.query(
      'otp_sessions',
      where: 'otp = ? AND is_used = 0',
      whereArgs: [otp],
    );
    if (rows.isEmpty) return null;
    final session = rows.first;
    final expiresAt = DateTime.parse(session['expires_at'] as String);
    if (DateTime.now().isAfter(expiresAt)) return null;
    return session;
  }

  Future<void> markOtpUsed(int sessionId) async {
    await db.update(
      'otp_sessions',
      {'is_used': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}