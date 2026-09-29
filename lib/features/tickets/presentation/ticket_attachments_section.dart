import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/features/tickets/presentation/attachment_utils.dart';
import 'package:hyport/features/tickets/presentation/attachment_viewer_screen.dart';

/// Renders a ticket's `attachmentUrls` (files picked while creating the
/// ticket, see `new_ticket_screen.dart`) as a row of tappable thumbnails.
/// Tapping one opens [AttachmentViewerScreen] to view it in-app; each tile
/// also carries its own download button so a copy can be saved without
/// opening the viewer first. Renders nothing when there are no attachments.
class TicketAttachmentsSection extends StatelessWidget {
  final List<String> attachmentUrls;

  const TicketAttachmentsSection({super.key, required this.attachmentUrls});

  @override
  Widget build(BuildContext context) {
    if (attachmentUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attachments (${attachmentUrls.length})', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < attachmentUrls.length; i++)
              _AttachmentTile(
                url: attachmentUrls[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttachmentViewerScreen(urls: attachmentUrls, initialIndex: i),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final String url;
  final VoidCallback onTap;

  const _AttachmentTile({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fileName = attachmentFileName(url);
    final isImage = attachmentKind(fileName) == AttachmentKind.image;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: isImage
                      ? CachedNetworkImage(
                          imageUrl: url,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const SizedBox(
                            width: 80,
                            height: 80,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => const SizedBox(
                            width: 80,
                            height: 80,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: AppTheme.mist,
                          child: Icon(attachmentIcon(fileName), size: 30, color: AppTheme.navy),
                        ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _DownloadButton(url: url),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadButton extends StatefulWidget {
  final String url;

  const _DownloadButton({required this.url});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    await downloadAttachment(context, widget.url);
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _downloading ? null : _download,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _downloading
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                )
              : const Icon(Icons.download_rounded, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
