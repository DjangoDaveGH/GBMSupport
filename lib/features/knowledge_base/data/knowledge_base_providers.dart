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
// session otherwise). Keyed on (category, canEdit) rather than just
// category — canEdit decides whether the query can even ask for
// unpublished articles at all (see watchAll's publishedOnly doc comment),
// not just how the result is displayed.
typedef ArticleListQuery = ({TicketCategory? category, bool canEdit});

final articleListProvider =
    StreamProvider.autoDispose.family<List<KnowledgeArticle>, ArticleListQuery>((ref, query) {
  return ref
      .watch(knowledgeBaseRepositoryProvider)
      .watchAll(category: query.category, publishedOnly: !query.canEdit);
});

final articleDetailProvider = StreamProvider.autoDispose.family<KnowledgeArticle?, String>((ref, articleId) {
  return ref.watch(knowledgeBaseRepositoryProvider).watchOne(articleId);
});
