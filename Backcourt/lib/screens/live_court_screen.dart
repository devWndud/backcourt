import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

void showLiveCourtInfo(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 12, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHandle(),
            SizedBox(height: 24),
            Text(
              'LIVE 안내',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 10),
            Text(
              '현재 인원과 코트 상태를 실시간으로 공유합니다.',
              style: TextStyle(color: AppColors.soft, height: 1.55),
            ),
            SizedBox(height: 18),
            _InfoRow(icon: Icons.gps_fixed_rounded, text: '코트 100m 안에서 등록'),
            _InfoRow(icon: Icons.timer_outlined, text: '90분 후 자동 종료'),
            _InfoRow(icon: Icons.bolt_rounded, text: '실시간 반영'),
          ],
        ),
      ),
    ),
  );
}

class LiveCourtScreen extends StatefulWidget {
  const LiveCourtScreen({
    super.key,
    this.repository,
    this.embedded = false,
    this.activeCourt = const CourtSummary(
      id: 'sample-0',
      name: '한강 시민공원 농구장',
      latitude: 37.5272,
      longitude: 126.9347,
    ),
  });

  final BackcourtRepository? repository;
  final bool embedded;
  final CourtSummary activeCourt;

  @override
  State<LiveCourtScreen> createState() => _LiveCourtScreenState();
}

class _LiveCourtScreenState extends State<LiveCourtScreen> {
  Timer? _expiryTicker;
  final Set<String> _previewArrivals = <String>{};
  LiveCourtStatus? _previewStatus;

  @override
  void initState() {
    super.initState();
    _expiryTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTicker?.cancel();
    super.dispose();
  }

  String? get _currentUid => widget.repository?.currentUid;

  List<LiveCourtStatus> get _previewStatuses {
    final now = DateTime.now();
    return [
      ?_previewStatus,
      LiveCourtStatus(
        id: 'preview-live-1',
        uid: 'preview-user-1',
        displayName: '농구하는 준',
        username: 'hoop.jun',
        courtId: widget.activeCourt.id,
        courtName: widget.activeCourt.name,
        latitude: widget.activeCourt.latitude,
        longitude: widget.activeCourt.longitude,
        activity: LiveCourtActivity.looking,
        playerCount: 5,
        neededPlayers: 1,
        distanceMeters: 24,
        arrivalUids: _previewArrivals.contains('preview-live-1')
            ? const ['preview-me']
            : const [],
        startedAt: now.subtract(const Duration(minutes: 18)),
        updatedAt: now.subtract(const Duration(minutes: 4)),
        expiresAt: now.add(const Duration(minutes: 72)),
      ),
      LiveCourtStatus(
        id: 'preview-live-2',
        uid: 'preview-user-2',
        displayName: '민재',
        courtId: 'preview-court-2',
        courtName: '여의도공원 농구코트',
        latitude: 37.5267,
        longitude: 126.9225,
        activity: LiveCourtActivity.playing,
        playerCount: 8,
        neededPlayers: 0,
        distanceMeters: 31,
        arrivalUids: const [],
        startedAt: now.subtract(const Duration(minutes: 26)),
        updatedAt: now.subtract(const Duration(minutes: 7)),
        expiresAt: now.add(const Duration(minutes: 64)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) return _buildContent(_previewStatuses);
    return StreamBuilder<List<LiveCourtStatus>>(
      stream: repository.watchLiveCourtStatusesNear(widget.activeCourt),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildContent(const [], error: true);
        }
        if (!snapshot.hasData) {
          return SafeArea(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildContent(snapshot.data!);
      },
    );
  }

  Widget _buildContent(List<LiveCourtStatus> values, {bool error = false}) {
    final statuses = values.where((status) => status.isActive).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final selectedStatuses = statuses
        .where((status) => status.courtId == widget.activeCourt.id)
        .toList();
    final myStatus = _currentUid == null
        ? _previewStatus
        : statuses.cast<LiveCourtStatus?>().firstWhere(
            (status) => status?.uid == _currentUid,
            orElse: () => null,
          );
    final mySelectedStatus = myStatus?.courtId == widget.activeCourt.id
        ? myStatus
        : null;
    final groups = _groupStatuses(statuses)
      ..removeWhere((group) => group.courtId == widget.activeCourt.id);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, widget.embedded ? 12 : 20, 20, 0),
            sliver: SliverList.list(
              children: [
                if (!widget.embedded) ...[
                  PageHeader(
                    eyebrow: 'PLAY',
                    title: '플레이',
                    action: RoundIconButton(
                      icon: Icons.info_outline_rounded,
                      onTap: () => showLiveCourtInfo(context),
                    ),
                  ),
                  SizedBox(height: 18),
                ],
                if (!widget.embedded) ...[
                  _SelectedCourtBar(court: widget.activeCourt),
                  SizedBox(height: 12),
                ],
                _LiveHero(
                  statuses: selectedStatuses,
                  hasMyStatus: mySelectedStatus != null,
                  error: error,
                  onTap: () => _showStatusSheet(myStatus),
                ),
                if (selectedStatuses.isNotEmpty) ...[
                  SizedBox(height: 24),
                  SectionTitle(
                    title: '지금 이 코트',
                    trailing: '${selectedStatuses.length}명 공유 중',
                  ),
                  SizedBox(height: 11),
                  for (var index = 0; index < selectedStatuses.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: index == selectedStatuses.length - 1 ? 0 : 10,
                      ),
                      child: _LiveStatusCard(
                        status: selectedStatuses[index],
                        isMine:
                            selectedStatuses[index].uid == _currentUid ||
                            selectedStatuses[index].id == _previewStatus?.id,
                        hasJoined: selectedStatuses[index].arrivalUids.contains(
                          _currentUid ?? 'preview-me',
                        ),
                        onJoin: () => _toggleArrival(selectedStatuses[index]),
                        onEdit: () => _showStatusSheet(selectedStatuses[index]),
                        onEnd: _endMyStatus,
                      ),
                    ),
                ],
                if (groups.isNotEmpty) ...[
                  SizedBox(height: 28),
                  SectionTitle(title: '근처 LIVE', trailing: '${groups.length}곳'),
                  SizedBox(height: 11),
                ],
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: groups.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverList.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10),
                    itemBuilder: (context, index) => _OtherCourtCard(
                      group: groups[index],
                      distanceLabel: _distanceLabel(groups[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<_LiveCourtGroup> _groupStatuses(List<LiveCourtStatus> statuses) {
    final grouped = <String, List<LiveCourtStatus>>{};
    for (final status in statuses) {
      grouped.putIfAbsent(status.courtId, () => []).add(status);
    }
    final result = grouped.values.map(_LiveCourtGroup.new).toList();
    result.sort((a, b) {
      final looking = b.neededPlayers.compareTo(a.neededPlayers);
      if (looking != 0) return looking;
      return b.latestUpdate.compareTo(a.latestUpdate);
    });
    return result;
  }

  String _distanceLabel(_LiveCourtGroup group) {
    final meters = Geolocator.distanceBetween(
      widget.activeCourt.latitude,
      widget.activeCourt.longitude,
      group.latitude,
      group.longitude,
    );
    return meters < 1000
        ? '${meters.round()}m'
        : '${(meters / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _toggleArrival(LiveCourtStatus status) async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        if (!_previewArrivals.add(status.id)) {
          _previewArrivals.remove(status.id);
        }
      });
      return;
    }
    try {
      await repository.toggleLiveCourtArrival(status);
    } catch (error) {
      _showMessage(error is BackcourtException ? error.message : '합류 처리 실패');
    }
  }

  Future<void> _endMyStatus() async {
    final repository = widget.repository;
    try {
      if (repository == null) {
        setState(() => _previewStatus = null);
      } else {
        await repository.endLiveCourtStatus();
      }
      _showMessage('LIVE 종료');
    } catch (_) {
      _showMessage('LIVE 종료 실패');
    }
  }

  Future<void> _showStatusSheet(LiveCourtStatus? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _LiveStatusSheet(
        repository: widget.repository,
        court: widget.activeCourt,
        existing: existing?.courtId == widget.activeCourt.id ? existing : null,
        onPreviewSaved: (status) => setState(() => _previewStatus = status),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SelectedCourtBar extends StatelessWidget {
  const _SelectedCourtBar({required this.court});

  final CourtSummary court;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: AppColors.text.withValues(alpha: .07)),
    ),
    child: Row(
      children: [
        Icon(Icons.place_rounded, color: AppColors.accent, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            court.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _LiveHero extends StatelessWidget {
  const _LiveHero({
    required this.statuses,
    required this.hasMyStatus,
    required this.error,
    required this.onTap,
  });

  final List<LiveCourtStatus> statuses;
  final bool hasMyStatus;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final group = statuses.isEmpty ? null : _LiveCourtGroup(statuses);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.text.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _BlinkingDot(),
              SizedBox(width: 7),
              Text(
                'LIVE',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('live-court-publish-button'),
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  backgroundColor: AppColors.surfaceHigh,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: Icon(
                  hasMyStatus ? Icons.tune_rounded : Icons.add_rounded,
                  size: 17,
                ),
                label: Text(hasMyStatus ? '내 상태 수정' : '내 상태 올리기'),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            error
                ? '상태를 불러오지 못했어요'
                : group == null
                ? '아직 조용해요'
                : '지금 ${group.playerCount}명',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: 7),
          Text(
            group == null
                ? '현장에 있다면 첫 상태를 남겨보세요'
                : group.neededPlayers > 0
                ? '${group.neededPlayers}명 더 필요해요 · ${group.arrivalCount}명 오는 중'
                : '${group.primaryActivity.label} · ${group.arrivalCount}명 오는 중',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (group != null) ...[
            SizedBox(height: 17),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (group.playerCount / 10).clamp(.12, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .35, end: 1).animate(_controller),
    child: const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: SizedBox(width: 8, height: 8),
    ),
  );
}

class _LiveStatusCard extends StatelessWidget {
  const _LiveStatusCard({
    required this.status,
    required this.isMine,
    required this.hasJoined,
    required this.onJoin,
    required this.onEdit,
    required this.onEnd,
  });

  final LiveCourtStatus status;
  final bool isMine;
  final bool hasJoined;
  final VoidCallback onJoin;
  final VoidCallback onEdit;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: status.isLooking
            ? AppColors.accent.withValues(alpha: .24)
            : AppColors.text.withValues(alpha: .06),
      ),
    ),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              initials: status.displayName.characters.first.toUpperCase(),
              size: 40,
              color: status.activity.color,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          status.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        SizedBox(width: 6),
                        Text(
                          '나',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    '${_relativeTime(status.updatedAt)} · GPS 인증',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            _ActivityBadge(activity: status.activity),
          ],
        ),
        SizedBox(height: 13),
        Row(
          children: [
            Icon(Icons.groups_2_outlined, color: AppColors.muted, size: 17),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                [
                  '현재 ${status.playerCount}명',
                  if (status.isLooking) '${status.neededPlayers}명 모집',
                  if (status.arrivalUids.isNotEmpty)
                    '${status.arrivalUids.length}명 오는 중',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isMine) ...[
              SizedBox(width: 8),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  minimumSize: const Size(48, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text('수정'),
              ),
              IconButton(
                tooltip: 'LIVE 종료',
                onPressed: onEnd,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.stop_circle_outlined, size: 18),
              ),
            ] else if (status.isLooking) ...[
              SizedBox(width: 8),
              FilledButton(
                onPressed: onJoin,
                style: FilledButton.styleFrom(
                  backgroundColor: hasJoined
                      ? AppColors.surfaceHigh
                      : AppColors.accent,
                  foregroundColor: hasJoined
                      ? AppColors.text
                      : AppColors.onAccent,
                  minimumSize: const Size(66, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: Text(hasJoined ? '도착 예정 · 취소' : '15분 뒤 도착'),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({required this.activity});

  final LiveCourtActivity activity;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: activity.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(activity.icon, color: activity.color, size: 14),
        SizedBox(width: 5),
        Text(
          activity.label,
          style: TextStyle(
            color: activity.color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _OtherCourtCard extends StatelessWidget {
  const _OtherCourtCard({required this.group, required this.distanceLabel});

  final _LiveCourtGroup group;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.text.withValues(alpha: .06)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: group.primaryActivity.color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            group.primaryActivity.icon,
            color: group.primaryActivity.color,
          ),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.courtName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 5),
              Text(
                '$distanceLabel · 현재 ${group.playerCount}명',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (group.neededPlayers > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${group.neededPlayers}명 모집',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        else
          _ActivityBadge(activity: group.primaryActivity),
      ],
    ),
  );
}

class _LiveStatusSheet extends StatefulWidget {
  const _LiveStatusSheet({
    required this.repository,
    required this.court,
    required this.existing,
    required this.onPreviewSaved,
  });

  final BackcourtRepository? repository;
  final CourtSummary court;
  final LiveCourtStatus? existing;
  final ValueChanged<LiveCourtStatus> onPreviewSaved;

  @override
  State<_LiveStatusSheet> createState() => _LiveStatusSheetState();
}

class _LiveStatusSheetState extends State<_LiveStatusSheet> {
  late LiveCourtActivity _activity =
      widget.existing?.activity ?? LiveCourtActivity.looking;
  late int _playerCount = widget.existing?.playerCount ?? 3;
  late int _neededPlayers = widget.existing?.neededPlayers ?? 1;
  bool _saving = false;

  bool get _showsPlayers => _activity != LiveCourtActivity.wet;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repository = widget.repository;
      if (repository == null) {
        final now = DateTime.now();
        widget.onPreviewSaved(
          LiveCourtStatus(
            id: 'preview-me-live',
            uid: 'preview-me',
            displayName: '나',
            courtId: widget.court.id,
            courtName: widget.court.name,
            latitude: widget.court.latitude,
            longitude: widget.court.longitude,
            activity: _activity,
            playerCount: _showsPlayers ? _playerCount : 0,
            neededPlayers: _activity == LiveCourtActivity.looking
                ? _neededPlayers
                : 0,
            distanceMeters: 18,
            arrivalUids: const [],
            startedAt: now,
            updatedAt: now,
            expiresAt: now.add(const Duration(minutes: 90)),
          ),
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const BackcourtException('위치 서비스를 켜주세요.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const BackcourtException('설정에서 위치 권한을 허용해주세요.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.court.latitude,
        widget.court.longitude,
      );
      await repository.publishLiveCourtStatus(
        court: widget.court,
        activity: _activity,
        playerCount: _showsPlayers ? _playerCount : 0,
        neededPlayers: _activity == LiveCourtActivity.looking
            ? _neededPlayers
            : 0,
        distanceMeters: distance,
      );
      if (mounted) Navigator.pop(context);
    } on TimeoutException {
      _show('현재 위치를 확인하지 못했어요. 다시 시도해주세요.');
    } catch (error) {
      _show(error is BackcourtException ? error.message : 'LIVE 등록 실패');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom +
          20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.existing == null ? 'LIVE 등록' : 'LIVE 수정',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: 5),
                    Text(
                      '90분 후 자동 종료',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded),
              ),
            ],
          ),
          SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Icon(Icons.place_rounded, color: AppColors.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.court.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  'GPS 100m',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 22),
          Text(
            '지금 상황',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final activity in LiveCourtActivity.values)
                    SizedBox(
                      width: width,
                      child: _ActivityOption(
                        activity: activity,
                        selected: activity == _activity,
                        onTap: () => setState(() => _activity = activity),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_showsPlayers) ...[
            SizedBox(height: 23),
            _NumberSlider(
              label: '현재 코트 인원',
              valueLabel: '$_playerCount명',
              value: _playerCount.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              onChanged: (value) =>
                  setState(() => _playerCount = value.round()),
            ),
          ],
          if (_activity == LiveCourtActivity.looking) ...[
            SizedBox(height: 18),
            _NumberSlider(
              label: '더 필요한 인원',
              valueLabel: '$_neededPlayers명',
              value: _neededPlayers.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (value) =>
                  setState(() => _neededPlayers = value.round()),
            ),
          ],
          SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.success,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '현재 위치는 저장되지 않음',
                    style: TextStyle(color: AppColors.soft, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('live-court-submit-button'),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.inverseText,
                      ),
                    )
                  : Icon(Icons.sensors_rounded),
              label: Text(_saving ? '위치 확인 중...' : 'GPS 확인 후 등록'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final LiveCourtActivity activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? activity.color.withValues(alpha: .16)
        : AppColors.surfaceHigh,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? activity.color
                : AppColors.text.withValues(alpha: .05),
          ),
        ),
        child: Row(
          children: [
            Icon(
              activity.icon,
              size: 21,
              color: selected ? activity.color : AppColors.muted,
            ),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                activity.label,
                style: TextStyle(
                  color: selected ? AppColors.text : AppColors.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: activity.color),
          ],
        ),
      ),
    ),
  );
}

class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              valueLabel,
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        activeColor: AppColors.accent,
        onChanged: onChanged,
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

class _LiveCourtGroup {
  _LiveCourtGroup(this.statuses)
    : courtId = statuses.first.courtId,
      courtName = statuses.first.courtName,
      latitude = statuses.first.latitude,
      longitude = statuses.first.longitude,
      latestUpdate = statuses
          .map((status) => status.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      playerCount = statuses
          .map((status) => status.playerCount)
          .fold<int>(0, math.max),
      neededPlayers = statuses
          .map((status) => status.neededPlayers)
          .fold<int>(0, math.max),
      arrivalCount = statuses
          .expand((status) => status.arrivalUids)
          .toSet()
          .length,
      primaryActivity = statuses.any((status) => status.isLooking)
          ? LiveCourtActivity.looking
          : statuses.first.activity;

  final List<LiveCourtStatus> statuses;
  final String courtId;
  final String courtName;
  final double latitude;
  final double longitude;
  final DateTime latestUpdate;
  final int playerCount;
  final int neededPlayers;
  final int arrivalCount;
  final LiveCourtActivity primaryActivity;
}

extension on LiveCourtActivity {
  IconData get icon => switch (this) {
    LiveCourtActivity.shooting => Icons.sports_basketball_rounded,
    LiveCourtActivity.playing => Icons.sports_score_rounded,
    LiveCourtActivity.looking => Icons.person_add_alt_1_rounded,
    LiveCourtActivity.full => Icons.groups_rounded,
    LiveCourtActivity.wet => Icons.water_drop_rounded,
  };

  Color get color => switch (this) {
    LiveCourtActivity.shooting => const Color(0xFFFFB067),
    LiveCourtActivity.playing => AppColors.success,
    LiveCourtActivity.looking => AppColors.accent,
    LiveCourtActivity.full => const Color(0xFF9EC7FF),
    LiveCourtActivity.wet => const Color(0xFF73D4FF),
  };
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return '방금 업데이트';
  if (difference.inMinutes < 60) return '${difference.inMinutes}분 전';
  return '${difference.inHours}시간 전';
}
