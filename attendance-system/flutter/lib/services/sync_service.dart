import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/database_service.dart';
import 'api_service.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  bool _isSyncing = false;

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Syncs all unsynced records to the central server.
  /// Returns a result map with inserted/skipped/failed counts.
  Future<SyncResult> syncPendingRecords() async {
    if (_isSyncing) return SyncResult(0, 0, 0, 'Sync already in progress');

    final online = await isOnline();
    if (!online) return SyncResult(0, 0, 0, 'No internet connection');

    _isSyncing = true;

    try {
      final unsyncedRecords = await DatabaseService.instance.getUnsyncedRecords();
      if (unsyncedRecords.isEmpty) {
        return SyncResult(0, 0, 0, 'Nothing to sync');
      }

      final jsonRecords = unsyncedRecords.map((r) => r.toSyncJson()).toList();
      final result = await ApiService.instance.syncAttendance(jsonRecords);

      final inserted = result['inserted'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      final failed = result['failed'] as int? ?? 0;

      // Mark successfully synced records
      if (inserted + skipped > 0) {
        final syncedIds = unsyncedRecords
            .take(inserted + skipped)
            .map((r) => r.syncId)
            .toList();
        await DatabaseService.instance.markAsSynced(syncedIds);
      }

      return SyncResult(inserted, skipped, failed,
          'Sync complete: $inserted inserted, $skipped skipped, $failed failed');
    } catch (e) {
      return SyncResult(0, 0, 0, 'Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }
}

class SyncResult {
  final int inserted;
  final int skipped;
  final int failed;
  final String message;

  const SyncResult(this.inserted, this.skipped, this.failed, this.message);
  bool get hasError => failed > 0;
}
