import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_providers.dart';
import 'package:hyport/features/knowledge_base/domain/knowledge_article.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 34 — same articleListProvider data as the mobile
/// Knowledge Base, laid out as a category sidebar + article list instead
/// of a horizontal chip row + card grid.
class DesktopKnowledgeBaseScreen extends ConsumerStatefulWidget {
  const DesktopKnowledgeBaseScreen({super.key});

  @override
  ConsumerState<DesktopKnowledgeBaseScreen> createState() => _DesktopKnowledgeBaseScreenState();
}

class _DesktopKnowledgeBaseScreenState extends ConsumerState<DesktopKnowledgeBaseScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  TicketCategory? _category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    final canEdit = appUser?.role.hasBackOfficeAccess ?? false;
    final allArticlesAsync = ref.watch(articleListProvider(null));
    final scopedArticlesAsync = ref.watch(articleListProvider(_category));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: allArticlesAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: BrandedLoaderCenter()),
                error: (e, _) => Text('Error: $e'),
                data: (all) {
                  final visible = canEdit ? all : all.where((a) => a.status == ArticleStatus.published).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryTile(label: 'All Categories', count: visible.length, selected: _category == null, onTap: () => setState(() => _category = null)),
                      for (final c in TicketCategory.values)
                        _CategoryTile(
                          label: c.label,
                          count: visible.where((a) => a.category == c).length,
                          selected: _category == c,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _search = v),
                        decoration: const InputDecoration(hintText: 'Search articles…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => context.push('/knowledge-base/new'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New Article'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: scopedArticlesAsync.when(
                    loading: () => const BrandedLoaderCenter(),
                    error: (e, _) => Center(child: Text('Could not load articles: $e')),
                    data: (articles) {
                      final visible = canEdit ? articles : articles.where((a) => a.status == ArticleStatus.published).toList();
                      final search = _search.toLowerCase();
                      final filtered = search.isEmpty
                          ? visible
                          : visible.where((a) => a.title.toLowerCase().contains(search) || a.tags.any((t) => t.toLowerCase().contains(search))).toList();
                      if (filtered.isEmpty) {
                        return const EmptyState(icon: Icons.menu_book_outlined, message: 'No articles found.');
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _ArticleRow(article: filtered[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.navy : AppTheme.ink, fontSize: 13.5),
                ),
              ),
              Text('$count', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final KnowledgeArticle article;

  const _ArticleRow({required this.article});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                  decoration: BoxDecoration(color: AppTheme.accentBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Icon(categoryIcon(article.category), size: 18, color: AppTheme.accentBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        'Updated ${DateFormat.yMMMd().format(article.publishedAt)} · ${article.viewCount} views',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (article.status != ArticleStatus.published)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(article.status.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.gold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
