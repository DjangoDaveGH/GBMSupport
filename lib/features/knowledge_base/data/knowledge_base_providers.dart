import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_repository.dart';
import 'package:hyport/features/knowledge_base/domain/knowledge_article.dart';

final knowledgeBaseRepositoryProvider = Provider<KnowledgeBaseRepository>((ref) {
  return KnowledgeBaseRepository(ref.watch(firestoreProvider));
});

// autoDispose: see the comment on ticketDetailProvider — same class of bug
// (a listener keyed independent of viewer identity outlives its creator's
// session otherwise).
final articleListProvider =
    StreamProvider.autoDispose.family<List<KnowledgeArticle>, TicketCategory?>((ref, category) {
  return ref.watch(knowledgeBaseRepositoryProvider).watchAll(category: category);
});

final articleDetailProvider = StreamProvider.autoDispose.family<KnowledgeArticle?, String>((ref, articleId) {
  return ref.watch(knowledgeBaseRepositoryProvider).watchOne(articleId);
});
