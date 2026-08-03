import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_providers.dart';
import 'package:hyport/features/knowledge_base/domain/knowledge_article.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart'
    show categoryIcon;
import 'package:hyport/core/widgets/branded_loader.dart';

String _compactViews(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}k';
  }
  final v = n / 1000000;
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}m';
}

class KnowledgeBaseScreen extends ConsumerStatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  ConsumerState<KnowledgeBaseScreen> createState() =>
      _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends ConsumerState<KnowledgeBaseScreen> {
  static const _featuredCategories = <TicketCategory>[
    TicketCategory.access,
    TicketCategory.smartView,
    TicketCategory.budgetForms,
    TicketCategory.reports,
    TicketCategory.workflow,
    TicketCategory.metadata,
  ];

  TicketCategory? _category;
  String _search = '';
  ArticleStatus? _statusTab;
  final _allArticlesKey = GlobalKey();

  void _scrollToAllArticles() {
    final ctx = _allArticlesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articleListProvider(_category));
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final canEdit = appUser?.role.hasBackOfficeAccess ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),
          onPressed: () => context.go('/home'),
        ),
        centerTitle: true,
        title: Text(
          'Knowledge Base',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.navyDark,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/knowledge-base/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Article'),
            )
          : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.035,
                child: Image.asset(
                  'assets/images/bg_hex_pattern.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          articlesAsync.when(
            loading: () => const BrandedLoaderCenter(),
            error: (e, _) => Center(child: Text('Could not load articles: $e')),
            data: (rawArticles) {
              // Drafts/review copies are only ever visible to editors — everyone
              // else only ever sees what's actually published.
              final visible = canEdit
                  ? rawArticles
                  : rawArticles
                        .where((a) => a.status == ArticleStatus.published)
                        .toList();
              final byStatus = canEdit && _statusTab != null
                  ? visible.where((a) => a.status == _statusTab).toList()
                  : visible;

              final search = _search.toLowerCase();
              final filtered = search.isEmpty
                  ? byStatus
                  : byStatus
                        .where(
                          (a) =>
                              a.title.toLowerCase().contains(search) ||
                              a.tags.any(
                                (t) => t.toLowerCase().contains(search),
                              ),
                        )
                        .toList();

              final popular =
                  (_category == null && search.isEmpty && _statusTab == null)
                  ? ([...visible]
                          ..sort((a, b) => b.viewCount.compareTo(a.viewCount)))
                        .take(2)
                        .toList()
                  : <KnowledgeArticle>[];

              final categoryCounts = <TicketCategory, int>{
                for (final c in TicketCategory.values)
                  c: visible.where((a) => a.category == c).length,
              };

              return ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 96),
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search articles, guides...',
                      hintStyle: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(
                            color: AppTheme.ink.withValues(alpha: 0.28),
                            fontSize: 17,
                          ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 30,
                        color: AppTheme.ink.withValues(alpha: 0.42),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      filled: false,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.navy.withValues(alpha: 0.30),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.accentBlue,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 32),
                  // 2-column grid of category tiles (mockup screen), every
                  // TicketCategory kept reachable (not just the 6 pictured) —
                  // dropping the other 6 here would only leave search as a way
                  // to reach their articles, a real capability regression.
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 26,
                    childAspectRatio: 1.15,
                    children: _featuredCategories
                        .map(
                          (c) => _CategoryGridTile(
                            category: c,
                            count: categoryCounts[c] ?? 0,
                            selected: _category == c,
                            onTap: () => setState(
                              () => _category = _category == c ? null : c,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (popular.isNotEmpty) ...[
                    const SizedBox(height: 64),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Popular Articles',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppTheme.navyDark,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: _scrollToAllArticles,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accentBlue,
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: Colors.white),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.navy.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: popular
                            .map((a) => _PopularArticleTile(article: a))
                            .toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  Text(
                    key: _allArticlesKey,
                    _category == null && search.isEmpty && _statusTab == null
                        ? 'All Articles'
                        : 'Results',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (filtered.isEmpty)
                    const EmptyState(
                      icon: Icons.menu_book_outlined,
                      message: 'No articles found.',
                    )
                  else
                    ...filtered.map(
                      (a) => _ArticleTile(
                        article: a,
                        scheme: scheme,
                        showStatus: canEdit,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryGridTile extends StatelessWidget {
  final TicketCategory category;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryGridTile({
    required this.category,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      elevation: selected ? 1 : 2,
      shadowColor: AppTheme.navy.withValues(alpha: 0.14),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? AppTheme.navy : Colors.white),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                categoryIcon(category),
                size: 34,
                color: selected ? Colors.white : AppTheme.accentBlue,
              ),
              const SizedBox(height: 7),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? Colors.white : AppTheme.navyDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count Article${count == 1 ? '' : 's'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? Colors.white70 : AppTheme.ink,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularArticleTile extends StatelessWidget {
  final KnowledgeArticle article;

  const _PopularArticleTile({required this.article});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.push('/knowledge-base/${article.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  categoryIcon(article.category),
                  size: 18,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_compactViews(article.viewCount)} views',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.accentBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusColor(ArticleStatus status) => switch (status) {
  ArticleStatus.published => StatusColors.resolved,
  ArticleStatus.review => AppTheme.gold,
  ArticleStatus.draft => StatusColors.closed,
};

class _ArticleTile extends StatelessWidget {
  final KnowledgeArticle article;
  final ColorScheme scheme;
  final bool showStatus;

  const _ArticleTile({
    required this.article,
    required this.scheme,
    this.showStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.push('/knowledge-base/${article.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    categoryIcon(article.category),
                    size: 18,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              article.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (showStatus &&
                              article.status != ArticleStatus.published) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  article.status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                article.status.label,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: _statusColor(article.status),
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              article.category.label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (article.viewCount > 0) ...[
                            Icon(
                              Icons.visibility_outlined,
                              size: 13,
                              color: scheme.outline,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${article.viewCount}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
