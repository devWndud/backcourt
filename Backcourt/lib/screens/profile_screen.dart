import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';
import 'player_setup_screen.dart';
import 'profile_edit_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.onSignOut,
    this.beforeDeleteAccount,
    this.repository,
    this.activeCourt = const CourtSummary(
      id: 'sample-unselected',
      name: '코트를 선택해 주세요',
      latitude: 37.5665,
      longitude: 126.978,
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
        builder: (context, profileSnapshot) =>
            StreamBuilder<UserActivityCounts>(
              stream: backend.watchMyActivityCounts(),
              builder: (context, activitySnapshot) =>
                  StreamBuilder<List<PostRecord>>(
                    stream: backend.watchMyPosts(),
                    builder: (context, postSnapshot) => _buildContent(
                      context,
                      profile: profileSnapshot.data,
                      posts: postSnapshot.data,
                      activity: activitySnapshot.data,
                    ),
                  ),
            ),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(
    BuildContext context, {
    AppUserProfile? profile,
    List<PostRecord>? posts,
    UserActivityCounts? activity,
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
                _ProfilePageHeader(
                  onSettings: () => _showSettings(context, profile),
                ),
                SizedBox(height: 20),
                _ProfileIntro(
                  profile: profile,
                  postCount: posts?.length ?? profile?.postCount ?? 0,
                  checkinCount:
                      activity?.checkins ?? profile?.checkinCount ?? 0,
                  meetupCount: activity?.meetups ?? profile?.meetupCount ?? 0,
                  onEdit: backend == null || profile == null
                      ? null
                      : () => _showProfileEditor(context, profile),
                ),
                SizedBox(height: 26),
                SectionTitle(
                  title: '기록',
                  trailing:
                      '${DateTime.now().year}.${DateTime.now().month.toString().padLeft(2, '0')}',
                ),
                SizedBox(height: 15),
                _MonthlyStats(
                  profile: profile,
                  repository: backend,
                  totalCheckins:
                      activity?.checkins ?? profile?.checkinCount ?? 0,
                ),
                SizedBox(height: 30),
                _PostsHeader(
                  count: posts?.length ?? profile?.postCount ?? 0,
                  onCreatePost: backend == null
                      ? null
                      : () => _showPostComposer(context),
                ),
                SizedBox(height: 12),
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
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverToBoxAdapter(child: _EmptyPosts()),
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

class _ProfilePageHeader extends StatelessWidget {
  const _ProfilePageHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'MY',
            style: TextStyle(
              fontSize: 25,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -.8,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('profile-settings-button'),
          tooltip: '설정',
          onPressed: onSettings,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.settings_outlined, size: 22),
        ),
      ],
    );
  }
}

class _PostsHeader extends StatelessWidget {
  const _PostsHeader({required this.count, required this.onCreatePost});

  final int count;
  final VoidCallback? onCreatePost;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('게시물', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        IconButton(
          key: const ValueKey('profile-new-post-button'),
          tooltip: '새 게시물',
          onPressed: onCreatePost,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add_rounded, size: 24),
        ),
      ],
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
            title: Text('계정 탈퇴'),
            content: Text('프로필과 게시물을 포함한 계정 데이터가 삭제돼요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('탈퇴'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
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

  Future<void> _editPlayerSetup(BuildContext context) async {
    final backend = repository;
    final currentProfile = profile;
    if (backend == null || currentProfile == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlayerSetupScreen(
          repository: backend,
          profile: currentProfile,
          editing: true,
        ),
      ),
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
              SizedBox(height: 21),
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
              SizedBox(height: 24),
              const BackcourtSectionLabel(title: '앱 환경'),
              SizedBox(height: 9),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: AppColors.text.withValues(alpha: .06),
                  ),
                ),
                child: Column(
                  children: [
                    if (repository != null && profile != null) ...[
                      _SettingsRow(
                        icon: Icons.sports_basketball_rounded,
                        title: '내 플레이',
                        subtitle: '홈코트 · 포지션 · 스타일',
                        value: '수정',
                        onTap: () => _editPlayerSetup(context),
                      ),
                      _SettingsDivider(),
                    ],
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
                    _SettingsRow(
                      icon: BackcourtThemeController.instance.isLight
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      title: '화면 스타일',
                      subtitle: BackcourtThemeController.instance.isLight
                          ? '라이트 모드'
                          : '다크 모드',
                      value: BackcourtThemeController.instance.isLight
                          ? 'LIGHT'
                          : 'DARK',
                      trailing: Switch.adaptive(
                        key: const ValueKey('theme-mode-switch'),
                        value: BackcourtThemeController.instance.isLight,
                        onChanged: BackcourtThemeController.instance.setLight,
                      ),
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
              SizedBox(height: 14),
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
                          child: Icon(
                            Icons.logout_rounded,
                            color: AppColors.accent,
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
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
                        Icon(
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
                SizedBox(height: 10),
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
                        color: AppColors.text.withValues(alpha: .025),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: AppColors.text.withValues(alpha: .055),
                        ),
                      ),
                      child: Row(
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
              SizedBox(height: 18),
              Center(
                child: Text(
                  'BACK TO THE COURT · BACKCOURT',
                  style: TextStyle(
                    color: AppColors.muted,
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
            SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<BlockedUserRecord>>(
                stream: repository.watchBlockedUsers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final users = snapshot.data!;
                  if (users.isEmpty) {
                    return Center(
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
                    separatorBuilder: (_, _) => SizedBox(height: 9),
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
                            UserAvatar(size: 36),
                            SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                user.displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  repository.unblockUser(user.blockedUid),
                              child: Text('해제'),
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
    color: AppColors.text.withValues(alpha: .055),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

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
              color: AppColors.text.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.soft, size: 17),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else ...[
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
              SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.accent,
                size: 16,
              ),
            ],
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
    required this.checkinCount,
    required this.meetupCount,
    required this.onEdit,
  });

  final AppUserProfile? profile;
  final int postCount;
  final int checkinCount;
  final int meetupCount;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName ?? '빽코트 플레이어';
    final username = profile?.username;
    final bio = profile?.bio.trim() ?? '';
    final playLabels = [
      if (profile?.position case final position?) _positionLabel(position),
      ...?profile?.playStyles.map(_playStyleLabel),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProfileAvatar(photoUrl: profile?.photoUrl, onTap: onEdit),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    username?.isNotEmpty == true ? '@$username' : '@아이디 추가',
                    style: TextStyle(
                      color: username?.isNotEmpty == true
                          ? AppColors.soft
                          : AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 9),
                  Text(
                    bio.isNotEmpty ? bio : '소개 추가',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bio.isNotEmpty ? AppColors.soft : AppColors.muted,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (playLabels.isNotEmpty) ...[
                    SizedBox(height: 7),
                    Text(
                      playLabels.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Stat(
                value: '$postCount',
                label: '게시물',
                align: CrossAxisAlignment.center,
              ),
            ),
            const _VerticalDivider(height: 30, horizontalMargin: 0),
            Expanded(
              child: Stat(
                value: '$checkinCount',
                label: '체크인',
                align: CrossAxisAlignment.center,
              ),
            ),
            const _VerticalDivider(height: 30, horizontalMargin: 0),
            Expanded(
              child: Stat(
                value: '$meetupCount',
                label: '약속',
                align: CrossAxisAlignment.center,
              ),
            ),
          ],
        ),
        SizedBox(height: 17),
        SizedBox(
          width: double.infinity,
          child: _ProfileActionButton(
            key: const ValueKey('profile-edit-button'),
            label: '프로필 편집',
            onTap: onEdit,
          ),
        ),
      ],
    );
  }

  String _positionLabel(String value) => switch (value) {
    'guard' => '가드',
    'forward' => '포워드',
    'center' => '센터',
    _ => value,
  };

  String _playStyleLabel(String value) => switch (value) {
    'shooting' => '슛',
    'drive' => '돌파',
    'passing' => '패스',
    'defense' => '수비',
    'rebound' => '리바운드',
    _ => value,
  };
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.onTap});

  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const fallback = DefaultProfileImage();
    final avatar = Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.accent,
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
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthlyStats extends StatelessWidget {
  const _MonthlyStats({this.profile, this.repository, this.totalCheckins = 0});

  final AppUserProfile? profile;
  final BackcourtRepository? repository;
  final int totalCheckins;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: repository?.watchMyMonthlyCheckinCount(),
      builder: (context, checkinSnapshot) => StreamBuilder<List<RankingEntry>>(
        stream: repository?.watchMonthlyRanking(),
        builder: (context, rankingSnapshot) {
          final rankings = rankingSnapshot.data ?? const [];
          final uid = profile?.uid;
          final index = uid == null
              ? -1
              : rankings.indexWhere((entry) => entry.uid == uid);
          final badgeProgress = totalCheckins % 10;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Stat(
                      value: '${checkinSnapshot.data ?? 0}회',
                      label: '이번 달 체크인',
                    ),
                  ),
                  const _VerticalDivider(height: 34),
                  Expanded(
                    child: Stat(
                      value: index < 0 ? '—' : '${index + 1}위',
                      label: '전국 순위',
                      align: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '다음 배지',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$badgeProgress / 10',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: List.generate(
                  10,
                  (dotIndex) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: dotIndex == 9 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: dotIndex < badgeProgress
                            ? AppColors.accent
                            : AppColors.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
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

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({this.height = 32, this.horizontalMargin = 18});

  final double height;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
    color: AppColors.line,
  );
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Center(
        child: Text(
          '게시물 없음',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          errorBuilder: (_, _, _) => ColoredBox(
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
              color: AppColors.onMedia.withValues(alpha: .7),
              size: 25,
            ),
          ),
          if (item?.type == 'video')
            Positioned(
              top: 7,
              right: 7,
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: AppColors.text,
                size: 15,
              ),
            ),
        ],
      ),
    );
  }
}
