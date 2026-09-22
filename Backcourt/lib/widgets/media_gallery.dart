import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../backend/models.dart';
import '../theme/app_theme.dart';

class MediaGallery extends StatefulWidget {
  const MediaGallery({super.key, required this.media});

  final List<MediaItem> media;

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      PageView.builder(
        itemCount: widget.media.length,
        onPageChanged: (value) => setState(() => _page = value),
        itemBuilder: (context, index) => MediaPreview(
          media: widget.media[index],
          onTap: () =>
              showMediaViewer(context, widget.media, initialIndex: index),
        ),
      ),
      if (widget.media.length > 1)
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${_page + 1}/${widget.media.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ],
  );
}

class MediaPreview extends StatelessWidget {
  const MediaPreview({super.key, required this.media, this.onTap});

  final MediaItem media;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: media.type == 'video'
        ? ColoredBox(
            color: AppColors.surfaceHigh,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.movie_outlined, color: AppColors.muted, size: 38),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .68),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 35,
                  ),
                ),
              ],
            ),
          )
        : Image.network(
            media.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
              color: AppColors.surfaceHigh,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
  );
}

class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    super.key,
    required this.media,
    required this.allMedia,
  });

  final MediaItem media;
  final List<MediaItem> allMedia;

  @override
  Widget build(BuildContext context) => MediaPreview(
    media: media,
    onTap: () => showMediaViewer(
      context,
      allMedia,
      initialIndex: allMedia.indexOf(media).clamp(0, allMedia.length - 1),
    ),
  );
}

Future<void> showMediaViewer(
  BuildContext context,
  List<MediaItem> media, {
  int initialIndex = 0,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _MediaViewer(media: media, initialIndex: initialIndex),
  ),
);

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({required this.media, required this.initialIndex});

  final List<MediaItem> media;
  final int initialIndex;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_page + 1} / ${widget.media.length}'),
    ),
    body: PageView.builder(
      controller: _controller,
      itemCount: widget.media.length,
      onPageChanged: (value) => setState(() => _page = value),
      itemBuilder: (context, index) {
        final item = widget.media[index];
        return item.type == 'video'
            ? _NetworkVideo(url: item.url)
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(item.url, fit: BoxFit.contain),
                ),
              );
      },
    ),
  );
}

class _NetworkVideo extends StatefulWidget {
  const _NetworkVideo({required this.url});

  final String url;

  @override
  State<_NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<_NetworkVideo> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  late final Future<void> _ready = _controller.initialize();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (snapshot.hasError) {
        return const Center(
          child: Text('영상을 불러오지 못했어요.', style: TextStyle(color: Colors.white)),
        );
      }
      return GestureDetector(
        onTap: () => setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        }),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
            if (!_controller.value.isPlaying)
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .58),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
          ],
        ),
      );
    },
  );
}
