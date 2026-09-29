import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device currently has *some* network path (wifi/mobile/
/// ethernet). This is a reachability signal, not a guarantee Firestore is
/// reachable — good enough for deciding whether to attempt a draft-ticket
/// sync vs. queue it.
///
/// Seeded with an explicit checkConnectivity() read before switching to the
/// change stream — onConnectivityChanged alone doesn't fire until the OS
/// reports its first change, leaving this in AsyncLoading in the meantime.
/// Every consumer treats that as "assume online" (`.valueOrNull ?? true`),
/// which is masked on native by Firestore's offline cache but not on web
/// (persistence is deliberately disabled there, see main.dart) — a ticket
/// submitted right after a cold start while genuinely offline could take
/// the online path instead of queuing and be lost instead of saved as a
/// draft.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield !initial.contains(ConnectivityResult.none);
  yield* connectivity.onConnectivityChanged.map(
    (results) => !results.contains(ConnectivityResult.none),
  );
});
