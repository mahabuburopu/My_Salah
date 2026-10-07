import 'package:connectivity_plus/connectivity_plus.dart';

/// Lightweight wrapper around connectivity_plus.
/// Used by SyncService to decide whether to push data to Supabase.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  /// Returns true if the device has any active internet connection.
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Stream that emits whenever connectivity changes.
  /// Useful for triggering background sync when connection is restored.
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;
}



