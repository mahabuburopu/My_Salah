import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import 'supabase_service.dart';
import 'connectivity_service.dart';

/// Background sync engine.
///
/// Strategy:
/// 1. After every local DB write, call [syncIfOnline] (fire-and-forget).
/// 2. SyncService also listens for connectivity changes. When the device
///    regains internet, it automatically runs [fullSync] to push any
///    locally-queued records that were missed while offline.
/// 3. Only authenticated (non-guest) users' records are synced.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final DatabaseService _db = DatabaseService();
  final SupabaseService _supabase = SupabaseService.instance;
  final ConnectivityService _connectivity = ConnectivityService.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once in main() after Supabase and DB are initialized.
  /// Starts listening to connectivity changes for automatic background sync.
  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        debugPrint('SyncService: connectivity restored — running fullSync');
        await fullSync();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Tries to sync unsynced records if internet is available.
  /// Safe to call fire-and-forget — will not throw.
  Future<void> syncIfOnline() async {
    // Skip if no logged-in user (guest mode)
    if (!_supabase.isSignedIn) return;

    final online = await _connectivity.isOnline();
    if (!online) return;

    await fullSync();
  }

  /// Pushes ALL local records with is_synced=0 to Supabase.
  /// Idempotent: uses upsert with ON CONFLICT so duplicates are handled.
  Future<void> fullSync() async {
    if (_isSyncing) return; // prevent overlapping syncs
    if (!_supabase.isSignedIn) return;

    _isSyncing = true;
    try {
      final userId = _supabase.userId!;
      final unsynced = await _db.getUnsyncedRecords();

      if (unsynced.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('SyncService: pushing ${unsynced.length} records to Supabase');

      // Build the list for Supabase upsert
      final rows = unsynced.map((r) {
        return {
          'user_id': userId,
          'date': r['date'], // 'YYYY-MM-DD'
          'prayer_name': r['prayer_name'], // integer index
          'status': r['status'], // integer index
          'prayed_at': r['prayed_at'], // nullable ISO string
        };
      }).toList();

      final success = await _supabase.upsertPrayerRecords(rows);

      if (success) {
        final ids = unsynced.map((r) => r['id'] as int).toList();
        await _db.markRecordsSynced(ids);
        debugPrint('SyncService: ${ids.length} records marked synced');
      }
    } catch (e) {
      debugPrint('SyncService fullSync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Pulls ALL prayer records from Supabase and writes them to local SQLite.
  /// Call this once after a successful sign-in on a fresh device so that
  /// the user's full history is immediately available offline.
  Future<void> restoreFromCloud() async {
    if (!_supabase.isSignedIn) return;
    try {
      debugPrint('SyncService: restoring history from cloud...');
      final records = await _supabase.fetchAllPrayerRecords();
      if (records.isEmpty) {
        debugPrint('SyncService: no cloud records to restore');
        return;
      }
      await _db.bulkInsertSynced(records);
      debugPrint('SyncService: restored ${records.length} records from cloud');
    } catch (e) {
      debugPrint('SyncService restoreFromCloud error: $e');
    }
  }
}
