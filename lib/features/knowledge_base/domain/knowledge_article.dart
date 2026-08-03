import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';

class KnowledgeArticle {
  final String id;
  final String title;
  final String body;
  final TicketCategory category;
  final List<String> tags;
  final List<String> attachmentUrls;
  final String publishedBy;
  final DateTime publishedAt;
  final int viewCount;
  final ArticleStatus status;

  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.tags,
    required this.attachmentUrls,
    required this.publishedBy,
    required this.publishedAt,
    this.viewCount = 0,
    this.status = ArticleStatus.published,
  });

  factory KnowledgeArticle.fromMap(String id, Map<String, dynamic> map) {
    return KnowledgeArticle(
      id: id,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      category: TicketCategory.fromWire(map['category'] as String? ?? 'general_enquiry'),
      tags: List<String>.from(map['tags'] as List? ?? []),
      attachmentUrls: List<String>.from(map['attachmentUrls'] as List? ?? []),
      publishedBy: map['publishedBy'] as String? ?? '',
      publishedAt: (map['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      viewCount: (map['viewCount'] as num?)?.toInt() ?? 0,
      status: ArticleStatus.fromWire(map['status'] as String? ?? 'published'),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'category': category.wireValue,
        'tags': tags,
        'attachmentUrls': attachmentUrls,
        'publishedBy': publishedBy,
        'publishedAt': Timestamp.fromDate(publishedAt),
        'viewCount': viewCount,
        'status': status.wireValue,
      };
}
