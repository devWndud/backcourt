import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';
import 'profile_edit_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.onSignOut,
    this.beforeDeleteAccount,
    this.repository,
    this.activeCourt = const CourtSummary(
      id: 'sample-0',
      name: '한강 시민공원 농구장',
      latitude: 37.5272,
      longitude: 126.9347,
    ),
  });

  final Future<void> Function()? onSignOut;
  final Future<void> Function()? beforeDeleteAccount;
  final BackcourtRepository? repository;
  final CourtSummary activeCourt;

  @override
  Widget build(BuildContext context) {
    final backend = repository;
    if (backend != null) {
      return StreamBuilder<AppUserProfile?>(
        stream: backend.watchCurrentProfile(),
        builder: (context, profileSnapshot) {
          return StreamBuilder<List<FavoriteCourtRecord>>(
            stream: backend.watchFavoriteCourts(),
            builder: (context, favoriteSnapshot) =>
                StreamBuilder<List<PostRecord>>(
                  stream: backend.watchMyPosts(),
                  builder: (context, postSnapshot) => _buildContent(
                    context,
                    profile: profileSnapshot.data,
                    posts: postSnapshot.data,
                    favorites: favoriteSnapshot.data,
                  ),
                ),
          );
        },
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(
    BuildContext context, {
    AppUserProfile? profile,
    List<PostRecord>? posts,
    List<FavoriteCourtRecord>? favorites,
  }) {
    final backend = repository;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverList.list(
              children: [
                PageHeader(
                  eyebrow: 'PROFILE',
                  title: 'MY',
                  action: RoundIconButton(
                    key: const ValueKey('profile-settings-button'),
                    icon: Icons.settings_outlined,
                    onTap: () => _showSettings(context, profile),
                  ),
                ),
                const SizedBox(height: 23),
                _ProfileIntro(
                  profile: profile,
                  postCount: posts?.length ?? profile?.postCount ?? 0,
                  onEdit: backend == null || profile == null
                      ? null
                      : () => _showProfileEditor(context, profile),
                  onCreatePost: backend == null
                      ? null
                      : () => _showPostComposer(context),
                ),
                const SizedBox(height: 22),
                _CourtPassport(profile: profile),
                if (favorites?.isNotEmpty == true) ...[
                  const SizedBox(height: 28),
                  SectionTitle(
                    title: '내 코트',
                    trailing: '${favorites!.length}개',
                  ),
                  const SizedBox(height: 13),
                  _FavoriteCourts(
                    favorites: favorites,
                    onRemove: backend == null
                        ? null
                        : (favorite) =>
                              backend.toggleFavoriteCourt(favorite.court),
                  ),
                ],
                const SizedBox(height: 28),
                SectionTitle(
                  title: '플레이 기록',
                  trailing:
                      '${DateTime.now().year}.${DateTime.now().month.toString().padLeft(2, '0')}',
                ),
                const SizedBox(height: 13),
                _MonthlyStats(profile: profile, repository: backend),
                const SizedBox(height: 28),
                SectionTitle(
                  title: '게시물',
                  trailing: '${posts?.length ?? profile?.postCount ?? 0}개',
                ),
                const SizedBox(height: 13),
              ],
            ),
          ),
          if (posts?.isEmpty != true)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ProfilePost(
                    index: index,
                    media: posts == null || posts[index].media.isEmpty
                        ? null
                        : posts[index].media.first,
                  ),
                  childCount: posts?.length ?? 0,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverToBoxAdapter(
                child: _EmptyPosts(
                  onCreatePost: backend == null
                      ? null
                      : () => _showPostComposer(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, AppUserProfile? profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SettingsSheet(
        profile: profile,
        repository: repository,
        beforeDeleteAccount: beforeDeleteAccount,
        onSignOut: onSignOut == null
            ? null
            : () async {
                Navigator.pop(sheetContext);
                await onSignOut!();
              },
      ),
    );
  }

  Future<void> _showProfileEditor(
    BuildContext context,
    AppUserProfile profile,
  ) async {
    final backend = repository;
    if (backend == null) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ProfileEditSheet(repository: backend, profile: profile),
    );
  }

  Future<void> _showPostComposer(BuildContext context) async {
    final backend = repository;
    if (backend == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          PostComposerSheet(repository: backend, court: activeCourt),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.profile,
    required this.repository,
    required this.onSignOut,
    required this.beforeDeleteAccount,
  });

  final AppUserProfile? profile;
  final BackcourtRepository? repository;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? beforeDeleteAccount;

  Future<void> _deleteAccount(BuildContext context) async {
    final backend = repository;
    if (backend == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('계정 탈퇴'),
            content: const Text('프로필과 게시물을 포함한 계정 데이터가 삭제돼요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('탈퇴'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2.5,
        ),
      ),
    );
    try {
      await beforeDeleteAccount?.call();
      await backend.deleteAccount();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '계정 탈퇴 실패',
          ),
        ),
      );
    }
  }

  Future<void> _showBlockedUsers(BuildContext context) async {
    final backend = repository;
    if (backend == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BlockedUsersSheet(repository: backend),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: backcourtSheetDecoration(),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 11, 22, bottom > 0 ? 10 : 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackcourtSheetHeader(
                eyebrow: 'SETTINGS',
                title: '설정',
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 21),
              BackcourtContextCard(
                title: profile?.displayName ?? '빽코트 플레이어',
                caption: profile?.username?.isNotEmpty == true
                    ? '@${profile!.username}'
                    : '내 빽코트 계정',
                icon: Icons.person_rounded,
                badge: profile?.role == 'operator' || profile?.role == 'admin'
                    ? 'OPERATOR'
                    : 'PLAYER',
              ),
              const SizedBox(height: 24),
              const BackcourtSectionLabel(title: '앱 환경'),
              const SizedBox(height: 9),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .06),
                  ),
                ),
                child: Column(
                  children: [
                    _SettingsRow(
                      icon: Icons.location_on_rounded,
                      title: '앱 권한',
                      subtitle: '위치 · 사진 · 카메라',
                      value: '설정 열기',
                      onTap: () => Geolocator.openAppSettings(),
                    ),
                    if (repository != null) ...[
                      _SettingsDivider(),
                      _SettingsRow(
                        icon: Icons.block_rounded,
                        title: '차단 계정',
                        subtitle: '숨긴 사용자',
                        value: '관리',
                        onTap: () => _showBlockedUsers(context),
                      ),
                    ],
                    _SettingsDivider(),
                    const _SettingsRow(
                      icon: Icons.dark_mode_rounded,
                      title: '화면 스타일',
                      subtitle: '다크',
                      value: 'DARK',
                    ),
                    _SettingsDivider(),
                    const _SettingsRow(
                      icon: Icons.info_outline_rounded,
                      title: '앱 버전',
                      subtitle: 'iOS · Android',
                      value: '1.0.0',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSignOut,
                  borderRadius: BorderRadius.circular(17),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .075),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: .16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: AppColors.accent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '로그아웃',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                '현재 기기',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.accent,
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (repository != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('delete-account-button'),
                    onTap: () => _deleteAccount(context),
                    borderRadius: BorderRadius.circular(17),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .025),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .055),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.person_off_outlined,
                            color: AppColors.muted,
                            size: 18,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '계정 탈퇴',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.muted,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'BACK TO THE COURT · BACKCOURT',
                  style: TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedUsersSheet extends StatelessWidget {
  const _BlockedUsersSheet({required this.repository});

  final BackcourtRepository repository;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .62,
    minChildSize: .42,
    maxChildSize: .88,
    expand: false,
    builder: (context, controller) => DecoratedBox(
      decoration: backcourtSheetDecoration(),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
              child: BackcourtSheetHeader(
                eyebrow: 'PRIVACY',
                title: '차단 계정',
                onClose: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<BlockedUserRecord>>(
                stream: repository.watchBlockedUsers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final users = snapshot.data!;
                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        '차단한 계정 없음',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      8,
                      22,
                      MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                              initials: user.displayName.characters
                                  .take(2)
                                  .toString(),
                              size: 36,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  repository.unblockUser(user.blockedUid),
                              child: const Text('해제'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 62,
    color: Colors.white.withValues(alpha: .055),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.soft, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: onTap == null ? AppColors.muted : AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: onTap == null ? .5 : 0,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.accent,
              size: 16,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: content,
      ),
    );
  }
}

class _ProfileIntro extends StatelessWidget {
  const _ProfileIntro({
    required this.profile,
    required this.postCount,
    required this.onEdit,
    required this.onCreatePost,
  });

  final AppUserProfile? profile;
  final int postCount;
  final VoidCallback? onEdit;
  final VoidCallback? onCreatePost;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName ?? '빽코트 플레이어';
    final username = profile?.username;
    final bio = profile?.bio.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProfileAvatar(
              displayName: displayName,
              photoUrl: profile?.photoUrl,
              onTap: onEdit,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Stat(
                    value: '$postCount',
                    label: '게시물',
                    align: CrossAxisAlignment.center,
                  ),
                  Stat(
                    value: '${profile?.checkinCount ?? 0}',
                    label: '출석',
                    align: CrossAxisAlignment.center,
                  ),
                  Stat(
                    value: '${profile?.liveCourtCount ?? 0}',
                    label: 'LIVE',
                    align: CrossAxisAlignment.center,
                  ),
                  Stat(
                    value: '${profile?.meetupCount ?? 0}',
                    label: '약속',
                    align: CrossAxisAlignment.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Text(
          displayName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          username?.isNotEmpty == true ? '@$username' : '@아이디 추가',
          style: TextStyle(
            color: username?.isNotEmpty == true
                ? AppColors.soft
                : AppColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          bio.isNotEmpty ? bio : '소개 추가',
          style: TextStyle(
            color: bio.isNotEmpty ? AppColors.soft : AppColors.muted,
            fontSize: 11,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ProfileActionButton(
                key: const ValueKey('profile-edit-button'),
                label: '프로필 편집',
                icon: Icons.edit_rounded,
                onTap: onEdit,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ProfileActionButton(
                key: const ValueKey('profile-new-post-button'),
                label: '새 게시물',
                icon: Icons.add_photo_alternate_outlined,
                accented: true,
                onTap: onCreatePost,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.displayName,
    required this.photoUrl,
    required this.onTap,
  });

  final String displayName;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.accentSoft,
      child: Center(
        child: Text(
          displayName.characters.take(2).toString(),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final avatar = Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent, Color(0xFFFFB15C)],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: photoUrl?.isNotEmpty == true
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accented = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          height: 43,
          decoration: BoxDecoration(
            color: accented
                ? AppColors.accent.withValues(alpha: .12)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: accented
                  ? AppColors.accent.withValues(alpha: .25)
                  : Colors.white.withValues(alpha: .065),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: accented ? AppColors.accent : AppColors.soft,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: accented ? AppColors.accent : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteCourts extends StatelessWidget {
  const _FavoriteCourts({required this.favorites, required this.onRemove});

  final List<FavoriteCourtRecord> favorites;
  final ValueChanged<FavoriteCourtRecord>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 68,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: favorites.length,
      separatorBuilder: (_, _) => const SizedBox(width: 9),
      itemBuilder: (context, index) {
        final favorite = favorites[index];
        return Container(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
          padding: const EdgeInsets.fromLTRB(14, 11, 7, 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.accent.withValues(alpha: .16)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.bookmark_rounded,
                  color: AppColors.accent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  favorite.court.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '제거',
                onPressed: onRemove == null ? null : () => onRemove!(favorite),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.muted,
                  size: 16,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _CourtPassport extends StatelessWidget {
  const _CourtPassport({this.profile});

  final AppUserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final checkins = profile?.checkinCount ?? 0;
    final level = checkins ~/ 10 + 1;
    final levelProgress = (checkins % 10) / 10;
    final remaining = 10 - (checkins % 10);
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFE8E8E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COURT PASSPORT',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '코트 러너 · LV. $level',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: levelProgress,
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(Colors.black),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '다음 레벨까지 출석 $remaining회',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sports_basketball_rounded,
              color: AppColors.accent,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyStats extends StatelessWidget {
  const _MonthlyStats({this.profile, this.repository});

  final AppUserProfile? profile;
  final BackcourtRepository? repository;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
      ),
      child: StreamBuilder<int>(
        stream: repository?.watchMyMonthlyCheckinCount(),
        builder: (context, checkinSnapshot) =>
            StreamBuilder<List<RankingEntry>>(
              stream: repository?.watchMonthlyRanking(),
              builder: (context, rankingSnapshot) {
                final rankings = rankingSnapshot.data ?? const [];
                final uid = profile?.uid;
                final index = uid == null
                    ? -1
                    : rankings.indexWhere((entry) => entry.uid == uid);
                return Row(
                  children: [
                    Expanded(
                      child: Stat(
                        value: '${checkinSnapshot.data ?? 0}회',
                        label: '이번 달 출석',
                      ),
                    ),
                    const _VerticalDivider(),
                    Expanded(
                      child: Stat(
                        value: index < 0 ? '—' : '${index + 1}위',
                        label: '전국 출석 랭킹',
                        align: CrossAxisAlignment.center,
                      ),
                    ),
                    const _VerticalDivider(),
                    Expanded(
                      child: Stat(
                        value: '${profile?.liveCourtCount ?? 0}회',
                        label: '현장 신호',
                        align: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: AppColors.line,
  );
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts({required this.onCreatePost});

  final VoidCallback? onCreatePost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            '게시물 없음',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onCreatePost,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('새 게시물'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePost extends StatelessWidget {
  const _ProfilePost({required this.index, this.media});

  final int index;
  final MediaItem? media;

  @override
  Widget build(BuildContext context) {
    final item = media;
    if (item != null && item.type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.network(
          item.url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: AppColors.surfaceHigh,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      );
    }
    const colors = [
      [Color(0xFF596A4B), Color(0xFF252C21)],
      [Color(0xFF41536A), Color(0xFF1B222D)],
      [Color(0xFF735540), Color(0xFF2B2019)],
      [Color(0xFF6E6E6E), Color(0xFF242424)],
    ];
    final palette = colors[index % colors.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              index.isEven
                  ? Icons.sports_basketball_rounded
                  : Icons.sports_rounded,
              color: Colors.white.withValues(alpha: .55),
              size: 25,
            ),
          ),
          if (item?.type == 'video')
            const Positioned(
              top: 7,
              right: 7,
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
        ],
      ),
    );
  }
}
