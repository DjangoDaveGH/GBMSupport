import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/dashboard/data/report_view_repository.dart';
import 'package:hyport/features/dashboard/domain/report_view.dart';

final reportViewRepositoryProvider = Provider<ReportViewRepository>((ref) {
  return ReportViewRepository(ref.watch(firestoreProvider));
});

final recentReportViewsProvider = StreamProvider.autoDispose.family<List<ReportView>, String>((ref, uid) {
  return ref.watch(reportViewRepositoryProvider).watchRecent(uid);
});
