import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hyport/core/routing/app_router.dart';
import 'package:hyport/core/services/global_keys.dart';
import 'package:hyport/core/services/local_notification_service.dart';
import 'package:hyport/core/services/push_notification_listener.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/tickets/data/draft_ticket_repository.dart';
import 'package:hyport/features/tickets/presentation/offline_sync_listener.dart';
import 'package:hyport/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await DraftTicketRepository.openBox();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LocalNotificationService.init();
  // Web's IndexedDB-backed persistence is unreliable on Safari/iOS (private
  // browsing, backgrounded tabs, and PWA+tab lock conflicts can leave the
  // IndexedDB connection hung instead of erroring), which silently stalls
  // every Firestore read/write — including ticket submission. Native
  // platforms don't have this failure mode, so only skip it on web.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  }

  runApp(const ProviderScope(child: HyportApp()));
}

class HyportApp extends ConsumerWidget {
  const HyportApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return OfflineSyncListener(
      child: PushNotificationListener(
        child: MaterialApp.router(
          title: 'GBMS Support',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: router,
        ),
      ),
    );
  }
}
