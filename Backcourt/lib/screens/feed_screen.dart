import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';
import '../widgets/media_gallery.dart';
import 'user_profile_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    this.repository,
    this.activeCourt = const CourtSummary(
      id: 'sample-0',
      name: '한강 시민공원 농구장',
      latitude: 37.5272,
      longitude: 126.9347,
    ),
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _selectedFeed = 0;
  final Set<String> _demoLikes = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  Future<List<AppUserProfile>>? _searchFuture;
  Position? _feedLocation;
  bool _locatingNearby = false;

  static final _demoPosts = <PostRecord>[
    PostRecord(
      id: 'demo-1',
      uid: 'demo',
      authorName: '농구하는준',
      courtId: 'sample-0',
      courtName: '한강 시민공원 농구장',
      text: '오늘 한강 바람도 좋고 코트 상태도 최고 🏀',
      media: const [],
      likeUids: const ['a', 'b'],
      createdAt: DateTime.now(),
    ),
  ];

  bool get _isSearching => _searchQuery.isNotEmpty;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      _searchFuture = null;
    });
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || query != _searchController.text.trim()) return;
      final repository = widget.repository;
      setState(() {
        _searchFuture = repository?.searchPublicProfiles(query);
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchQuery = '';
      _searchFuture = null;
    });
  }

  void _openSearchProfile(AppUserProfile profile) {
    final repository = widget.repository;
    if (repository == null || profile.uid == repository.currentUid) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          repository: repository,
          uid: profile.uid,
          fallbackName: profile.displayName,
          fallbackUsername: profile.username,
          fallbackPhotoUrl: profile.photoUrl,
        ),
      ),
    );
  }

  Future<void> _openComposer() async {
    final repository = widget.repository;
    if (repository == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Firebase 연결 필요')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          PostComposerSheet(repository: repository, court: widget.activeCourt),
    );
  }

  Future<void> _toggleLike(PostRecord post) async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        if (!_demoLikes.add(post.id)) _demoLikes.remove(post.id);
      });
      return;
    }
    try {
      await repository.togglePostLike(post);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '좋아요 처리 실패',
          ),
        ),
      );
    }
  }

  Future<void> _selectFeed(int value) async {
    setState(() => _selectedFeed = value);
    if (value != 2 || _feedLocation != null || _locatingNearby) return;
    setState(() => _locatingNearby = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const BackcourtException('주변 피드는 위치 권한이 필요해요.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _feedLocation = position);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '현재 위치를 확인하지 못했어요.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locatingNearby = false);
    }
  }

  List<PostRecord> _filterPosts(
    List<PostRecord> posts,
    Set<String> blockedUids,
    Set<String> followingUids,
  ) {
    final visible = posts
        .where((post) => !blockedUids.contains(post.uid))
        .toList(growable: false);
    if (_selectedFeed == 0) return visible;
    if (_selectedFeed == 1) {
      return visible
          .where((post) => followingUids.contains(post.uid))
          .toList(growable: false);
    }
    if (_selectedFeed == 3) {
      return visible
          .where((post) => post.courtId == widget.activeCourt.id)
          .toList(growable: false);
    }
    final location = _feedLocation;
    if (location == null) return const [];
    return visible
        .where((post) {
          final latitude = post.latitude;
          final longitude = post.longitude;
          if (latitude == null || longitude == null) return false;
          return Geolocator.distanceBetween(
                location.latitude,
                location.longitude,
                latitude,
                longitude,
              ) <=
              5000;
        })
        .toList(growable: false);
  }

  Stream<List<PostRecord>> _postStream(BackcourtRepository repository) {
    if (_selectedFeed == 3) {
      return repository.watchCourtPosts(widget.activeCourt.id);
    }
    final location = _feedLocation;
    if (_selectedFeed == 2 && location != null) {
      return repository.watchNearbyPosts(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    }
    if (_selectedFeed == 2) return Stream.value(const <PostRecord>[]);
    return repository.watchPosts();
  }

  void _openUserProfile(PostRecord post) {
    final repository = widget.repository;
    if (repository == null || post.uid == repository.currentUid) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          repository: repository,
          uid: post.uid,
          fallbackName: post.authorName,
          fallbackUsername: post.authorUsername,
          fallbackPhotoUrl: post.authorPhotoUrl,
        ),
      ),
    );
  }

  Future<void> _openComments(PostRecord post) async {
    final repository = widget.repository;
    if (repository == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          PostCommentsSheet(repository: repository, post: post),
    );
  }

  Future<void> _openPostActions(PostRecord post) async {
    final repository = widget.repository;
    if (repository == null) return;
    final action = await showModalBottomSheet<_PostAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PostActionsSheet(
        mine: post.uid == repository.currentUid,
        authorName: post.authorName,
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case _PostAction.delete:
          final confirmed = await _confirmDeletePost();
          if (!confirmed) return;
          await repository.deletePost(post);
          _showMessage('게시물 삭제 완료');
        case _PostAction.report:
          final reason = await _pickReportReason();
          if (reason == null) return;
          await repository.reportPost(post, reason);
          _showMessage('신고 접수 완료');
        case _PostAction.block:
          await repository.blockUser(post.uid, displayName: post.authorName);
          _showMessage('${post.authorName} 차단 완료');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error is BackcourtException ? error.message : '처리 실패');
    }
  }

  Future<bool> _confirmDeletePost() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('게시물 삭제'),
          content: Text('삭제한 게시물은 다시 복구할 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('삭제'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _pickReportReason() => showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ReportReasonSheet(),
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverList.list(
              children: [
                PageHeader(
                  eyebrow: 'FEED',
                  title: '피드',
                  action: RoundIconButton(
                    icon: Icons.add_a_photo_outlined,
                    light: true,
                    onTap: _openComposer,
                  ),
                ),
                SizedBox(height: 18),
                _AccountSearchBar(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
                if (!_isSearching) ...[
                  SizedBox(height: 22),
                  _FeedTabs(selected: _selectedFeed, onChanged: _selectFeed),
                  if (_selectedFeed == 2 || _selectedFeed == 3) ...[
                    SizedBox(height: 20),
                    _ActiveCourtBanner(
                      court: widget.activeCourt,
                      nearby: _selectedFeed == 2,
                      locating: _locatingNearby,
                    ),
                  ],
                ],
                SizedBox(height: 20),
              ],
            ),
          ),
          if (_isSearching)
            repository == null
                ? const SliverToBoxAdapter(
                    child: _FeedMessage(label: '계정 검색은 로그인 후 사용할 수 있어요.'),
                  )
                : _ProfileSearchSliver(
                    future: _searchFuture,
                    onTap: _openSearchProfile,
                  )
          else if (repository == null)
            _PostSliver(
              posts: _filterPosts(_demoPosts, const {}, const {}),
              currentUid: null,
              demoLikes: _demoLikes,
              onLike: _toggleLike,
              onComment: _openComments,
              onMore: _openPostActions,
              onAuthor: _openUserProfile,
            )
          else
            StreamBuilder<Set<String>>(
              stream: repository.watchBlockedUserIds(),
              builder: (context, blockedSnapshot) => StreamBuilder<Set<String>>(
                stream: repository.watchFollowingUserIds(),
                builder: (context, followingSnapshot) =>
                    StreamBuilder<List<PostRecord>>(
                      stream: _postStream(repository),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const SliverToBoxAdapter(
                            child: _FeedMessage(label: '피드 불러오기 실패'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        return _PostSliver(
                          posts: _filterPosts(
                            snapshot.data!,
                            blockedSnapshot.data ?? const {},
                            followingSnapshot.data ?? const {},
                          ),
                          currentUid: repository.currentUid,
                          demoLikes: const {},
                          onLike: _toggleLike,
                          onComment: _openComments,
                          onMore: _openPostActions,
                          onAuthor: _openUserProfile,
                        );
                      },
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountSearchBar extends StatelessWidget {
  const _AccountSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.text.withValues(alpha: .06)),
    ),
    child: TextField(
      key: const ValueKey('feed-account-search'),
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: '이름 또는 @아이디',
        hintStyle: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppColors.muted,
          size: 22,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.muted,
                    size: 19,
                  ),
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );
}

class _ProfileSearchSliver extends StatelessWidget {
  const _ProfileSearchSliver({required this.future, required this.onTap});

  final Future<List<AppUserProfile>>? future;
  final ValueChanged<AppUserProfile> onTap;

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return FutureBuilder<List<AppUserProfile>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SliverToBoxAdapter(
            child: _FeedMessage(label: '검색 결과를 불러오지 못했어요.'),
          );
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final profiles = snapshot.data!;
        if (profiles.isEmpty) {
          return const SliverToBoxAdapter(
            child: _FeedMessage(label: '검색 결과 없음'),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverList.separated(
            itemCount: profiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTap(profile),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        UserAvatar(size: 44, photoUrl: profile.photoUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (profile.username?.isNotEmpty == true) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@${profile.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['최신', '팔로잉', '내 주변', '코트'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = selected == index;
        return GestureDetector(
          onTap: () => onChanged(index),
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labels[index],
                  style: TextStyle(
                    color: active ? AppColors.text : AppColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: active ? 24 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _ActiveCourtBanner extends StatelessWidget {
  const _ActiveCourtBanner({
    required this.court,
    required this.nearby,
    required this.locating,
  });

  final CourtSummary court;
  final bool nearby;
  final bool locating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.text.withValues(alpha: .07)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.accent,
          child: Icon(
            nearby ? Icons.near_me_rounded : Icons.sports_basketball_rounded,
            color: AppColors.text,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nearby ? '내 주변' : '현재 선택 코트',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              SizedBox(height: 3),
              Text(
                nearby
                    ? locating
                          ? '위치 확인 중'
                          : '반경 5km'
                    : court.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PostSliver extends StatelessWidget {
  const _PostSliver({
    required this.posts,
    required this.currentUid,
    required this.demoLikes,
    required this.onLike,
    required this.onComment,
    required this.onMore,
    required this.onAuthor,
  });

  final List<PostRecord> posts;
  final String? currentUid;
  final Set<String> demoLikes;
  final ValueChanged<PostRecord> onLike;
  final ValueChanged<PostRecord> onComment;
  final ValueChanged<PostRecord> onMore;
  final ValueChanged<PostRecord> onAuthor;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const SliverToBoxAdapter(child: _FeedMessage(label: '게시물 없음'));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      sliver: SliverList.separated(
        itemCount: posts.length,
        separatorBuilder: (_, _) => SizedBox(height: 16),
        itemBuilder: (context, index) {
          final post = posts[index];
          final liked = currentUid == null
              ? demoLikes.contains(post.id)
              : post.likeUids.contains(currentUid);
          return _PostCard(
            post: post,
            liked: liked,
            likeCount:
                post.likeUids.length + (currentUid == null && liked ? 1 : 0),
            onLike: () => onLike(post),
            onComment: () => onComment(post),
            onMore: () => onMore(post),
            onAuthor: () => onAuthor(post),
          );
        },
      ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 120),
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(label, style: TextStyle(color: AppColors.muted)),
    ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.liked,
    required this.likeCount,
    required this.onLike,
    required this.onComment,
    required this.onMore,
    required this.onAuthor,
  });

  final PostRecord post;
  final bool liked;
  final int likeCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onMore;
  final VoidCallback onAuthor;

  String get _timeLabel {
    final difference = DateTime.now().difference(post.createdAt);
    if (difference.inMinutes < 1) return '방금';
    if (difference.inHours < 1) return '${difference.inMinutes}분';
    if (difference.inDays < 1) return '${difference.inHours}시간';
    return '${difference.inDays}일';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onAuthor,
                    borderRadius: BorderRadius.circular(18),
                    child: Row(
                      children: [
                        UserAvatar(size: 36, photoUrl: post.authorPhotoUrl),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.authorName,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${post.courtName} · $_timeLabel',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('post-menu-${post.id}'),
                  onPressed: onMore,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_horiz_rounded, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (post.media.isNotEmpty)
            AspectRatio(
              aspectRatio: 1.1,
              child: MediaGallery(media: post.media),
            )
          else
            AspectRatio(
              aspectRatio: 1.8,
              child: ColoredBox(
                color: AppColors.surfaceHigh,
                child: Center(
                  child: Icon(
                    Icons.sports_basketball_rounded,
                    size: 52,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onLike,
                      child: Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: liked ? AppColors.accent : AppColors.text,
                      ),
                    ),
                    SizedBox(width: 7),
                    Text('$likeCount'),
                    SizedBox(width: 20),
                    GestureDetector(
                      key: ValueKey('post-comments-${post.id}'),
                      onTap: onComment,
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 21),
                          if (post.commentCount > 0) ...[
                            SizedBox(width: 7),
                            Text('${post.commentCount}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (post.text.isNotEmpty) ...[
                  SizedBox(height: 11),
                  Text(post.text, style: TextStyle(fontSize: 12, height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _PostAction { delete, report, block }

class _PostActionsSheet extends StatelessWidget {
  const _PostActionsSheet({required this.mine, required this.authorName});

  final bool mine;
  final String authorName;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: backcourtSheetDecoration(),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 11, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BackcourtSheetHeader(
              eyebrow: mine ? 'MY POST' : 'POST',
              title: mine ? '게시물 관리' : authorName,
              onClose: () => Navigator.pop(context),
            ),
            SizedBox(height: 16),
            if (mine)
              _PostActionRow(
                icon: Icons.delete_outline_rounded,
                label: '게시물 삭제',
                danger: true,
                onTap: () => Navigator.pop(context, _PostAction.delete),
              )
            else ...[
              _PostActionRow(
                icon: Icons.flag_outlined,
                label: '게시물 신고',
                onTap: () => Navigator.pop(context, _PostAction.report),
              ),
              SizedBox(height: 8),
              _PostActionRow(
                icon: Icons.block_rounded,
                label: '사용자 차단',
                danger: true,
                onTap: () => Navigator.pop(context, _PostAction.block),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PostActionRow extends StatelessWidget {
  const _PostActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceHigh,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: danger ? AppColors.accent : AppColors.text,
            ),
            SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: danger ? AppColors.accent : AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _ReportReasonSheet extends StatelessWidget {
  const _ReportReasonSheet();

  static const _reasons = ['스팸 · 광고', '욕설 · 괴롭힘', '위험 · 불법 내용', '기타 부적절한 내용'];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: backcourtSheetDecoration(),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 11, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackcourtSheetHeader(
              eyebrow: 'REPORT',
              title: '신고 사유',
              onClose: () => Navigator.pop(context),
            ),
            SizedBox(height: 16),
            for (var index = 0; index < _reasons.length; index++) ...[
              _PostActionRow(
                icon: Icons.flag_outlined,
                label: _reasons[index],
                onTap: () => Navigator.pop(context, _reasons[index]),
              ),
              if (index != _reasons.length - 1) SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ),
  );
}

class PostCommentsSheet extends StatefulWidget {
  const PostCommentsSheet({
    super.key,
    required this.repository,
    required this.post,
  });

  final BackcourtRepository repository;
  final PostRecord post;

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repository.createComment(
        post: widget.post,
        text: _controller.text,
      );
      _controller.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '댓글 등록 실패',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CommentRecord comment) async {
    try {
      await widget.repository.deleteComment(comment);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '댓글 삭제 실패',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .82,
    minChildSize: .58,
    maxChildSize: .96,
    expand: false,
    builder: (context, scrollController) => AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: backcourtSheetDecoration(),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
                child: BackcourtSheetHeader(
                  eyebrow: widget.post.courtName,
                  title: '댓글',
                  onClose: () => Navigator.pop(context),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<Set<String>>(
                  stream: widget.repository.watchBlockedUserIds(),
                  builder: (context, blockedSnapshot) =>
                      StreamBuilder<List<CommentRecord>>(
                        stream: widget.repository.watchComments(widget.post.id),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          }
                          final blocked = blockedSnapshot.data ?? const {};
                          final comments = snapshot.data!
                              .where(
                                (comment) => !blocked.contains(comment.uid),
                              )
                              .toList(growable: false);
                          if (comments.isEmpty) {
                            return Center(
                              child: Text(
                                '댓글 없음',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                            itemCount: comments.length,
                            separatorBuilder: (_, _) => SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              return _CommentTile(
                                comment: comment,
                                mine:
                                    comment.uid == widget.repository.currentUid,
                                onDelete: () => _delete(comment),
                              );
                            },
                          );
                        },
                      ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  MediaQuery.paddingOf(context).bottom + 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.text.withValues(alpha: .06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('comment-field'),
                        controller: _controller,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: '댓글',
                          counterText: '',
                        ),
                      ),
                    ),
                    SizedBox(width: 9),
                    IconButton.filled(
                      key: const ValueKey('submit-comment'),
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                      ),
                      icon: _sending
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onAccent,
                              ),
                            )
                          : Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.mine,
    required this.onDelete,
  });

  final CommentRecord comment;
  final bool mine;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      UserAvatar(size: 34, photoUrl: comment.authorPhotoUrl),
      SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment.authorName,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              comment.text,
              style: TextStyle(
                color: AppColors.soft,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      if (mine)
        IconButton(
          onPressed: onDelete,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, color: AppColors.muted, size: 17),
        ),
    ],
  );
}

class PostComposerSheet extends StatefulWidget {
  const PostComposerSheet({
    super.key,
    required this.repository,
    required this.court,
  });

  final BackcourtRepository repository;
  final CourtSummary court;

  @override
  State<PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<PostComposerSheet> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  XFile? _video;
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 2160,
      maxHeight: 2160,
      limit: 6,
    );
    if (!mounted) return;
    setState(() {
      _images
        ..clear()
        ..addAll(files);
    });
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (video != null && mounted) setState(() => _video = video);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.repository.createPost(
        court: widget.court,
        text: _textController.text,
        images: _images,
        video: _video,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '게시물 등록 실패',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .88,
    minChildSize: .62,
    maxChildSize: .96,
    expand: false,
    builder: (context, controller) => AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: backcourtSheetDecoration(),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
                child: BackcourtSheetHeader(
                  eyebrow: 'NEW POST',
                  title: '새 게시물',
                  onClose: () => Navigator.pop(context),
                ),
              ),
              SizedBox(height: 19),
              Expanded(
                child: ListView(
                  controller: controller,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  children: [
                    BackcourtContextCard(
                      title: widget.court.name,
                      caption: '선택 코트',
                      icon: Icons.location_on_rounded,
                      badge: 'PUBLIC',
                    ),
                    SizedBox(height: 23),
                    const BackcourtSectionLabel(
                      title: '내용',
                      trailing: '글 또는 미디어',
                    ),
                    SizedBox(height: 10),
                    _PostTextField(controller: _textController),
                    SizedBox(height: 23),
                    const BackcourtSectionLabel(
                      title: '미디어',
                      trailing: '사진 6 · 영상 1',
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: BackcourtMediaAction(
                            icon: Icons.add_photo_alternate_rounded,
                            title: '사진 ${_images.length}/6',
                            caption: _images.isEmpty
                                ? '갤러리에서 선택'
                                : '선택 완료 · 다시 고르기',
                            active: _images.isNotEmpty,
                            onTap: _pickImages,
                          ),
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: BackcourtMediaAction(
                            icon: Icons.video_library_rounded,
                            title: _video == null ? '영상' : '영상 선택됨',
                            caption: _video == null ? '최대 30초' : '다시 고르기',
                            active: _video != null,
                            onTap: _pickVideo,
                          ),
                        ),
                      ],
                    ),
                    if (_images.isNotEmpty || _video != null) ...[
                      SizedBox(height: 12),
                      _PostMediaPreview(
                        images: _images,
                        video: _video,
                        onRemoveImage: (image) =>
                            setState(() => _images.remove(image)),
                        onRemoveVideo: () => setState(() => _video = null),
                      ),
                    ],
                    SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.text.withValues(alpha: .035),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: AppColors.text.withValues(alpha: .055),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.public_rounded,
                            color: AppColors.accent,
                            size: 19,
                          ),
                          SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              '전체 공개',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.lock_open_rounded,
                            color: AppColors.muted,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppColors.muted,
                          size: 11,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '사진 10MB · 영상 100MB · 커뮤니티 가이드 적용',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  22,
                  13,
                  22,
                  MediaQuery.paddingOf(context).bottom + 13,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.text.withValues(alpha: .06),
                    ),
                  ),
                ),
                child: BackcourtPrimaryAction(
                  label: '게시하기',
                  loading: _saving,
                  icon: Icons.arrow_upward_rounded,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PostTextField extends StatelessWidget {
  const _PostTextField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.text.withValues(alpha: .06)),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            minLines: 7,
            maxLines: 10,
            maxLength: 1500,
            autofocus: false,
            style: TextStyle(fontSize: 13, height: 1.55),
            decoration: InputDecoration(
              hintText: '내용 입력',
              hintStyle: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.55,
              ),
              filled: false,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 16, 16, 32),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 11,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${value.text.length}/1500',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMediaPreview extends StatelessWidget {
  const _PostMediaPreview({
    required this.images,
    required this.video,
    required this.onRemoveImage,
    required this.onRemoveVideo,
  });

  final List<XFile> images;
  final XFile? video;
  final ValueChanged<XFile> onRemoveImage;
  final VoidCallback onRemoveVideo;

  @override
  Widget build(BuildContext context) {
    final itemCount = images.length + (video == null ? 0 : 1);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(width: 9),
        itemBuilder: (context, index) {
          final isVideo = index >= images.length;
          final image = isVideo ? null : images[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: isVideo
                    ? Container(
                        width: 92,
                        height: 92,
                        color: AppColors.surfaceHigh,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.accent,
                              size: 29,
                            ),
                            SizedBox(height: 5),
                            Text(
                              'VIDEO',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Image.file(
                        File(image!.path),
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: AppColors.surfaceHigh,
                          child: SizedBox.square(
                            dimension: 92,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 5,
                right: 5,
                child: GestureDetector(
                  onTap: isVideo ? onRemoveVideo : () => onRemoveImage(image!),
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: AppColors.inverseText.withValues(alpha: .74),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.text,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
