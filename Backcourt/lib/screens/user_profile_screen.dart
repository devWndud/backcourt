import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.repository,
    required this.uid,
    required this.fallbackName,
    this.fallbackUsername,
    this.fallbackPhotoUrl,
  });

  final BackcourtRepository repository;
  final String uid;
  final String fallbackName;
  final String? fallbackUsername;
  final String? fallbackPhotoUrl;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '처리하지 못했어요.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleFriend(FriendshipRecord? friendship) async {
    if (friendship == null) {
      await _run(() => widget.repository.sendFriendRequest(widget.uid));
      return;
    }
    if (friendship.status == FriendshipStatus.pending &&
        friendship.targetUid == widget.repository.currentUid) {
      await _run(() => widget.repository.acceptFriendRequest(friendship));
      return;
    }
    final remove =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              friendship.status == FriendshipStatus.accepted
                  ? '친구 삭제'
                  : '친구 요청 취소',
            ),
            content: Text(
              friendship.status == FriendshipStatus.accepted
                  ? '${widget.fallbackName}님을 친구에서 삭제할까요?'
                  : '보낸 친구 요청을 취소할까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('아니요'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('확인'),
              ),
            ],
          ),
        ) ??
        false;
    if (remove) {
      await _run(() => widget.repository.removeFriendship(widget.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<AppUserProfile?>(
          stream: widget.repository.watchPublicProfile(widget.uid),
          builder: (context, profileSnapshot) {
            final profile = profileSnapshot.data;
            final name = profile?.displayName ?? widget.fallbackName;
            final username = profile?.username ?? widget.fallbackUsername;
            final photoUrl = profile?.photoUrl ?? widget.fallbackPhotoUrl;
            return StreamBuilder<List<PostRecord>>(
              stream: widget.repository.watchUserPosts(widget.uid),
              builder: (context, postSnapshot) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      ),
                      Expanded(
                        child: Text(
                          username?.isNotEmpty == true ? '@$username' : name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SizedBox(width: 48),
                    ],
                  ),
                  SizedBox(height: 26),
                  Center(child: UserAvatar(size: 86, photoUrl: photoUrl)),
                  SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.5,
                    ),
                  ),
                  if (username?.isNotEmpty == true) ...[
                    SizedBox(height: 3),
                    Text(
                      '@$username',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (profile?.bio.trim().isNotEmpty == true) ...[
                    SizedBox(height: 12),
                    Text(
                      profile!.bio,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.soft,
                        height: 1.45,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  SizedBox(height: 24),
                  _SocialCounts(
                    repository: widget.repository,
                    uid: widget.uid,
                    postCount: postSnapshot.data?.length ?? 0,
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: StreamBuilder<bool>(
                          stream: widget.repository.watchIsFollowing(
                            widget.uid,
                          ),
                          builder: (context, snapshot) {
                            final following = snapshot.data ?? false;
                            return _ProfileButton(
                              label: following ? '팔로잉' : '팔로우',
                              filled: !following,
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => widget.repository.toggleFollow(
                                        widget.uid,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: StreamBuilder<FriendshipRecord?>(
                          stream: widget.repository.watchFriendshipWith(
                            widget.uid,
                          ),
                          builder: (context, snapshot) {
                            final friendship = snapshot.data;
                            final label = switch (friendship?.status) {
                              FriendshipStatus.accepted => '친구',
                              FriendshipStatus.pending
                                  when friendship?.targetUid ==
                                      widget.repository.currentUid =>
                                '요청 수락',
                              FriendshipStatus.pending => '요청됨',
                              _ => '친구 추가',
                            };
                            return _ProfileButton(
                              label: label,
                              onPressed: _busy
                                  ? null
                                  : () => _handleFriend(friendship),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                  Row(
                    children: [
                      Text(
                        '게시물',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: 7),
                      Text(
                        '${postSnapshot.data?.length ?? 0}',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _PostGrid(posts: postSnapshot.data ?? const []),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SocialCounts extends StatelessWidget {
  const _SocialCounts({
    required this.repository,
    required this.uid,
    required this.postCount,
  });

  final BackcourtRepository repository;
  final String uid;
  final int postCount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Count(value: postCount, label: '게시물'),
      ),
      Expanded(
        child: StreamBuilder<int>(
          stream: repository.watchFollowerCount(uid),
          builder: (_, snapshot) =>
              _Count(value: snapshot.data ?? 0, label: '팔로워'),
        ),
      ),
      Expanded(
        child: StreamBuilder<int>(
          stream: repository.watchFollowingCount(uid),
          builder: (_, snapshot) =>
              _Count(value: snapshot.data ?? 0, label: '팔로잉'),
        ),
      ),
    ],
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.text,
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: BorderSide(color: AppColors.text.withValues(alpha: .12)),
            ),
            child: Text(label),
          ),
  );
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.posts});

  final List<PostRecord> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '아직 게시물이 없어요',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final post = posts[index];
        final media = post.media.isEmpty ? null : post.media.first;
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: ColoredBox(
            color: AppColors.surfaceHigh,
            child: media == null
                ? Icon(Icons.sports_basketball_rounded, color: AppColors.accent)
                : media.type == 'video'
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: AppColors.surfaceHigh),
                      Icon(
                        Icons.play_circle_fill_rounded,
                        color: AppColors.text,
                      ),
                    ],
                  )
                : Image.network(media.url, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

Future<void> showFriendsSheet(
  BuildContext context,
  BackcourtRepository repository,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _FriendsSheet(repository: repository),
);

class _FriendsSheet extends StatelessWidget {
  const _FriendsSheet({required this.repository});

  final BackcourtRepository repository;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .68,
    minChildSize: .5,
    maxChildSize: .92,
    expand: false,
    builder: (context, controller) => DecoratedBox(
      decoration: backcourtSheetDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 11, 22, 8),
            child: BackcourtSheetHeader(
              eyebrow: 'SOCIAL',
              title: '친구',
              onClose: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FriendshipRecord>>(
              stream: repository.watchIncomingFriendRequests(),
              builder: (context, requestSnapshot) =>
                  StreamBuilder<List<FriendshipRecord>>(
                    stream: repository.watchFriends(),
                    builder: (context, friendSnapshot) {
                      final requests = requestSnapshot.data ?? const [];
                      final friends = friendSnapshot.data ?? const [];
                      if (requests.isEmpty && friends.isEmpty) {
                        return Center(
                          child: Text(
                            '피드에서 플레이어를 눌러 친구를 추가해보세요.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }
                      return ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                        children: [
                          if (requests.isNotEmpty) ...[
                            _SheetLabel('받은 요청 ${requests.length}'),
                            SizedBox(height: 8),
                            for (final request in requests)
                              _FriendRow(
                                repository: repository,
                                uid: request.requesterUid,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          repository.removeFriendship(
                                            request.requesterUid,
                                          ),
                                      child: Text('삭제'),
                                    ),
                                    FilledButton(
                                      onPressed: () => repository
                                          .acceptFriendRequest(request),
                                      child: Text('수락'),
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(height: 24),
                          ],
                          if (friends.isNotEmpty) ...[
                            _SheetLabel('친구 ${friends.length}'),
                            SizedBox(height: 8),
                            for (final friendship in friends)
                              _FriendRow(
                                repository: repository,
                                uid: friendship.otherUid(repository.currentUid),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900));
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.repository,
    required this.uid,
    this.trailing,
  });

  final BackcourtRepository repository;
  final String uid;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppUserProfile?>(
    stream: repository.watchPublicProfile(uid),
    builder: (context, snapshot) {
      final profile = snapshot.data;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: UserAvatar(size: 42, photoUrl: profile?.photoUrl),
        title: Text(
          profile?.displayName ?? '플레이어',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        subtitle: profile?.username?.isNotEmpty == true
            ? Text('@${profile!.username}')
            : null,
        trailing: trailing,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(
              repository: repository,
              uid: uid,
              fallbackName: profile?.displayName ?? '플레이어',
              fallbackUsername: profile?.username,
              fallbackPhotoUrl: profile?.photoUrl,
            ),
          ),
        ),
      );
    },
  );
}
