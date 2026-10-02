import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/prayer.dart';
import '../models/prayer_record.dart';

class DatabaseService {
  // ── Singleton ────────────────────────────────────────────
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const String _dbName = 'my_salah.db';
  static const int _dbVersion = 3; // v3 adds is_synced column

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE prayer_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        prayer_name INTEGER NOT NULL,
        status INTEGER NOT NULL,
        prayed_at TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE(date, prayer_name)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_prayer_records_date ON prayer_records(date)');

    // v2: users table (for future auth migration from SharedPreferences)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        gender TEXT DEFAULT 'Male',
        age TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add index (safe to ignore if already exists)
      try {
        await db.execute(
            'CREATE INDEX idx_prayer_records_date ON prayer_records(date)');
      } catch (_) {}

      // Add users table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT UNIQUE NOT NULL,
          password_hash TEXT NOT NULL,
          gender TEXT DEFAULT 'Male',
          age TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // v3: add is_synced column to track cloud sync status
      try {
        await db.execute(
            'ALTER TABLE prayer_records ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
      } catch (_) {} // safe if column already exists (e.g. fresh install)
    }
  }

  // Insert or update a prayer record (always marks is_synced=0 so SyncService
  // will push it to Supabase on the next background sync)
  Future<void> savePrayerRecord(PrayerRecord record) async {
    try {
      final db = await database;
      final map = record.toMap();
      map['is_synced'] = 0; // needs to be pushed to cloud
      await db.insert(
        'prayer_records',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      debugPrint('DB Error savePrayerRecord: $e\n$stack');
    }
  }

  /// Wipes all local prayer records. Use this when signing out or switching accounts.
  Future<void> clearAllRecords() async {
    try {
      final db = await database;
      await db.delete('prayer_records');
      debugPrint('DB: Cleared all local prayer records.');
    } catch (e) {
      debugPrint('DB Error clearAllRecords: $e');
    }
  }

  /// Bulk-inserts records downloaded from Supabase into the local DB.
  /// Each record is marked is_synced=1 (already in cloud — no need to re-push).
  /// Uses IGNORE conflict so locally-edited records are NOT overwritten.
  Future<void> bulkInsertSynced(List<Map<String, dynamic>> records) async {
    try {
      final db = await database;
      final batch = db.batch();
      for (final r in records) {
        batch.insert(
          'prayer_records',
          {
            'date': r['date'],
            'prayer_name': r['prayer_name'],
            'status': r['status'],
            'prayed_at': r['prayed_at'],
            'is_synced': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    } catch (e, stack) {
      debugPrint('DB Error bulkInsertSynced: $e\n$stack');
    }
  }

  // Get all prayer records for a specific date
  Future<List<PrayerRecord>> getPrayerRecordsForDate(DateTime date) async {
    try {
      final db = await database;
      final dateStr = date.toIso8601String().substring(0, 10);
      final maps = await db.query(
        'prayer_records',
        where: 'date = ?',
        whereArgs: [dateStr],
      );
      return maps.map((m) => PrayerRecord.fromMap(m)).toList();
    } catch (e, stack) {
      debugPrint('DB Error getPrayerRecordsForDate: $e\n$stack');
      return [];
    }
  }

  // Get prayer records for a date range
  Future<List<PrayerRecord>> getPrayerRecordsInRange(
      DateTime start, DateTime end) async {
    try {
      final db = await database;
      final startStr = start.toIso8601String().substring(0, 10);
      final endStr = end.toIso8601String().substring(0, 10);
      final maps = await db.query(
        'prayer_records',
        where: 'date >= ? AND date <= ?',
        whereArgs: [startStr, endStr],
      );
      return maps.map((m) => PrayerRecord.fromMap(m)).toList();
    } catch (e, stack) {
      debugPrint('DB Error getPrayerRecordsInRange: $e\n$stack');
      return [];
    }
  }

  // Get total prayer counts grouped by status
  Future<Map<String, int>> getPrayerStats() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT status, COUNT(*) as count 
        FROM prayer_records 
        GROUP BY status
      ''');

      Map<String, int> stats = {'onTime': 0, 'qaza': 0, 'missed': 0};
      for (final row in result) {
        final statusIndex = row['status'] as int;
        if (statusIndex < 0 || statusIndex >= PrayerStatus.values.length) {
          continue;
        }
        final status = PrayerStatus.values[statusIndex];
        final count = row['count'] as int;
        switch (status) {
          case PrayerStatus.onTime:
            stats['onTime'] = count;
            break;
          case PrayerStatus.qaza:
            stats['qaza'] = count;
            break;
          case PrayerStatus.missed:
            stats['missed'] = count;
            break;
          default:
            break;
        }
      }
      return stats;
    } catch (e, stack) {
      debugPrint('DB Error getPrayerStats: $e\n$stack');
      return {'onTime': 0, 'qaza': 0, 'missed': 0};
    }
  }

  // Get last 7 days prayer counts (combined)
  Future<List<Map<String, dynamic>>> getLast7DaysCounts() async {
    try {
      final db = await database;
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 6));
      final result = await db.rawQuery('''
        SELECT date, COUNT(*) as count 
        FROM prayer_records 
        WHERE date >= ? AND date <= ? AND (status = ? OR status = ?)
        GROUP BY date
        ORDER BY date ASC
      ''', [
        startDate.toIso8601String().substring(0, 10),
        endDate.toIso8601String().substring(0, 10),
        PrayerStatus.onTime.index,
        PrayerStatus.qaza.index,
      ]);
      return result
          .map((r) => {'date': r['date'], 'count': r['count']})
          .toList();
    } catch (e, stack) {
      debugPrint('DB Error getLast7DaysCounts: $e\n$stack');
      return [];
    }
  }

  /// Get last 7 days with ON-TIME and QAZA counts SEPARATELY.
  /// Returns list of {date, onTime, qaza} — one entry per day.
  Future<List<Map<String, dynamic>>> getLast7DaysCountsSeparate() async {
    try {
      final db = await database;
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 6));
      final result = await db.rawQuery('''
        SELECT
          date,
          SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS onTime,
          SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS qaza
        FROM prayer_records
        WHERE date >= ? AND date <= ?
        GROUP BY date
        ORDER BY date ASC
      ''', [
        PrayerStatus.onTime.index,
        PrayerStatus.qaza.index,
        startDate.toIso8601String().substring(0, 10),
        endDate.toIso8601String().substring(0, 10),
      ]);
      return result
          .map((r) => {
                'date': r['date'] as String,
                'onTime': (r['onTime'] as int?) ?? 0,
                'qaza': (r['qaza'] as int?) ?? 0,
              })
          .toList();
    } catch (e, stack) {
      debugPrint('DB Error getLast7DaysCountsSeparate: $e\n$stack');
      return [];
    }
  }

  /// Calculate current prayer streak — SINGLE SQL QUERY (fixed from 365 queries).
  Future<int> getCurrentStreak() async {
    try {
      final db = await database;
      // Fetch up to 365 days grouped, ordered newest first
      final result = await db.rawQuery('''
        SELECT
          date,
          SUM(CASE WHEN status = ${PrayerStatus.missed.index} THEN 1 ELSE 0 END) AS missed,
          COUNT(*) AS total
        FROM prayer_records
        GROUP BY date
        ORDER BY date DESC
        LIMIT 365
      ''');

      int streak = 0;
      for (final row in result) {
        final missed = (row['missed'] as int?) ?? 0;
        final total = (row['total'] as int?) ?? 0;
        if (total == 0 || missed > 0) break;
        streak++;
      }
      return streak;
    } catch (e, stack) {
      debugPrint('DB Error getCurrentStreak: $e\n$stack');
      return 0;
    }
  }

  /// Returns all prayer records where is_synced = 0.
  /// Used by SyncService to batch-push unsynced data to Supabase.
  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    try {
      final db = await database;
      return await db.query(
        'prayer_records',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
    } catch (e, stack) {
      debugPrint('DB Error getUnsyncedRecords: $e\n$stack');
      return [];
    }
  }

  /// Marks a list of records as synced (is_synced = 1).
  /// Called by SyncService after successful Supabase upsert.
  Future<void> markRecordsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final placeholders = ids.map((_) => '?').join(',');
      await db.rawUpdate(
        'UPDATE prayer_records SET is_synced = 1 WHERE id IN ($placeholders)',
        ids,
      );
    } catch (e, stack) {
      debugPrint('DB Error markRecordsSynced: $e\n$stack');
    }
  }
}
