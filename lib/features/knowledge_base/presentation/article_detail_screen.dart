import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_providers.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';
import 'package:hyport/core/widgets/branded_loader.dart';

class ArticleDetailScreen extends ConsumerStatefulWidget {
  final String articleId;

  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const ArticleDetailScreen({super.key, required this.articleId, this.embedded = false});

  @override
  ConsumerState<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget — a failed/late increment shouldn't block reading the
    // article, so no loading/error state is threaded through for this.
    ref.read(knowledgeBaseRepositoryProvider).incrementViewCount(widget.articleId);
  }

  @override
  Widget build(BuildContext context) {
    final articleAsync = ref.watch(articleDetailProvider(widget.articleId));

    final body = articleAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load article: $e')),
        data: (article) {
          if (article == null) return const Center(child: Text('Article not found.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accentBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(categoryIcon(article.category), size: 19, color: AppTheme.accentBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(article.title, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 3),
                              Text(
                                '${article.category.label} · ${DateFormat.yMMMd().format(article.publishedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 15, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 5),
                        Text(
                          '${article.viewCount} view${article.viewCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(article.body, style: Theme.of(context).textTheme.bodyLarge),
                    if (article.tags.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: article.tags
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text('#$t', style: Theme.of(context).textTheme.labelMedium),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Article')), body: body);
  }
}
