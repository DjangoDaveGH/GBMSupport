import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device currently has *some* network path (wifi/mobile/
/// ethernet). This is a reachability signal, not a guarantee Firestore is
/// reachable — good enough for deciding whether to attempt a draft-ticket
/// sync vs. queue it.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(
    (results) => !results.contains(ConnectivityResult.none),
  );
});
