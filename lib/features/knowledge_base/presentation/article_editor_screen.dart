import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/knowledge_base/data/knowledge_base_providers.dart';
import 'package:hyport/features/knowledge_base/domain/knowledge_article.dart';
import 'package:uuid/uuid.dart';

/// Basic admin create/edit form for support staff (Section 5: "no editing
/// UI needed in MVP beyond a basic admin create/edit form").
class ArticleEditorScreen extends ConsumerStatefulWidget {
  /// When true, renders just the content with no Scaffold/AppBar of its
  /// own — for embedding inside DesktopShell. See NotificationsScreen's
  /// doc comment for why.
  final bool embedded;

  const ArticleEditorScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ArticleEditorScreen> createState() => _ArticleEditorScreenState();
}

class _ArticleEditorScreenState extends ConsumerState<ArticleEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagsController = TextEditingController();
  TicketCategory _category = TicketCategory.generalEnquiry;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit(ArticleStatus status) async {
    if (!_formKey.currentState!.validate()) return;
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    if (appUser == null) return;

    setState(() => _submitting = true);
    try {
      final article = KnowledgeArticle(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        category: _category,
        tags: _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        attachmentUrls: const [],
        publishedBy: appUser.id,
        publishedAt: DateTime.now(),
        status: status,
      );
      await ref.read(knowledgeBaseRepositoryProvider).create(article);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save article: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TicketCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: TicketCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Body', alignLabelWithHint: true),
              maxLines: 10,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter article content' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(labelText: 'Tags (comma-separated)'),
            ),
            const SizedBox(height: 24),
            if (_submitting)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _submit(ArticleStatus.draft),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _submit(ArticleStatus.review),
                      child: const Text('Submit for Review'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _submit(ArticleStatus.published),
                      child: const Text('Publish'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('New Article')), body: body);
  }
}
