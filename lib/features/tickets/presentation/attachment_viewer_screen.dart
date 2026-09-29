import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hyport/features/tickets/presentation/attachment_utils.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

/// Full-screen in-app viewer for a ticket's attachments — swiping between
/// [urls] the way a chat gallery would. Nothing here ever leaves the app to
/// a browser tab; the only way content leaves the device is the explicit
/// download action in the AppBar, which hands the bytes to the OS share
/// sheet ([downloadAttachment]).
class AttachmentViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const AttachmentViewerScreen({super.key, required this.urls, this.initialIndex = 0});

  @override
  State<AttachmentViewerScreen> createState() => _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState extends State<AttachmentViewerScreen> {
  late final PageController _pageController;
  late int _index;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    await downloadAttachment(context, widget.urls[_index]);
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = attachmentFileName(widget.urls[_index]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.urls.length > 1 ? '$fileName  (${_index + 1}/${widget.urls.length})' : fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded),
            onPressed: _downloading ? null : _download,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _AttachmentPage(url: widget.urls[i]),
      ),
    );
  }
}

class _AttachmentPage extends StatelessWidget {
  final String url;

  const _AttachmentPage({required this.url});

  @override
  Widget build(BuildContext context) {
    final fileName = attachmentFileName(url);
    switch (attachmentKind(fileName)) {
      case AttachmentKind.image:
        return _ImagePreview(url: url);
      case AttachmentKind.pdf:
        return _PdfPreview(url: url);
      case AttachmentKind.text:
        return _TextPreview(url: url);
      case AttachmentKind.other:
        return _UnsupportedPreview(url: url);
    }
  }
}

class _ImagePreview extends StatelessWidget {
  final String url;

  const _ImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(url),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorBuilder: (context, error, stackTrace) => const _PreviewError(
        message: "This image couldn't be loaded.",
      ),
    );
  }
}

class _PdfPreview extends StatefulWidget {
  final String url;

  const _PdfPreview({required this.url});

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late final Future<Uint8List> _bytesFuture;
  PdfControllerPinch? _controller;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _fetch();
  }

  Future<Uint8List> _fetch() async {
    final response = await http.get(Uri.parse(widget.url));
    if (response.statusCode != 200) {
      throw Exception('server returned ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return const _PreviewError(message: "This PDF couldn't be loaded.");
        }
        _controller ??= PdfControllerPinch(document: PdfDocument.openData(snapshot.data!));
        return PdfViewPinch(controller: _controller!);
      },
    );
  }
}

class _TextPreview extends StatefulWidget {
  final String url;

  const _TextPreview({required this.url});

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final Future<String> _textFuture;

  @override
  void initState() {
    super.initState();
    _textFuture = _fetch();
  }

  Future<String> _fetch() async {
    final response = await http.get(Uri.parse(widget.url));
    if (response.statusCode != 200) {
      throw Exception('server returned ${response.statusCode}');
    }
    return response.body;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _textFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return const _PreviewError(message: "This file couldn't be loaded.");
        }
        return Container(
          color: Colors.white,
          width: double.infinity,
          height: double.infinity,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snapshot.data!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        );
      },
    );
  }
}

class _UnsupportedPreview extends StatelessWidget {
  final String url;

  const _UnsupportedPreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final fileName = attachmentFileName(url);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(attachmentIcon(fileName), size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              "There's no in-app preview for this file type. Use the download button above to save and open it.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  final String message;

  const _PreviewError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
