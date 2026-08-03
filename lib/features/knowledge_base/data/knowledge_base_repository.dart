import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/knowledge_base/domain/knowledge_article.dart';

class KnowledgeBaseRepository {
  final FirebaseFirestore _db;

  KnowledgeBaseRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _articles => _db.collection('knowledge_articles');

  Stream<List<KnowledgeArticle>> watchAll({TicketCategory? category}) {
    Query<Map<String, dynamic>> query = _articles;
    if (category != null) {
      query = query.where('category', isEqualTo: category.wireValue);
    }
    query = query.orderBy('publishedAt', descending: true);
    return query.snapshots().map(
          (snap) => snap.docs.map((d) => KnowledgeArticle.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<KnowledgeArticle?> watchOne(String id) {
    return _articles.doc(id).snapshots().map(
          (doc) => doc.exists ? KnowledgeArticle.fromMap(doc.id, doc.data()!) : null,
        );
  }

  Future<void> create(KnowledgeArticle article) {
    return _articles.doc(article.id).set(article.toMap());
  }

  Future<void> update(String id, Map<String, dynamic> changes) {
    return _articles.doc(id).update(changes);
  }

  Future<void> delete(String id) {
    return _articles.doc(id).delete();
  }

  /// Fire-and-forget view counter, incremented once per article open. Any
  /// signed-in reader may bump this (see firestore.rules' onlyFieldsChanged
  /// carve-out) — it's the one field on an article a non-editor can write.
  Future<void> incrementViewCount(String id) {
    return _articles.doc(id).update({'viewCount': FieldValue.increment(1)});
  }
}
