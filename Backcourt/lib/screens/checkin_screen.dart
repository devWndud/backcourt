import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
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
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  bool _checkedIn = false;
  bool _checking = false;
  double? _distanceMeters;
  int _stampPulse = 0;
  StreamSubscription<CheckinRecord?>? _checkinSubscription;

  @override
  void initState() {
    super.initState();
    _bindTodayCheckin();
  }

  @override
  void didUpdateWidget(covariant CheckinScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.activeCourt.id != widget.activeCourt.id) {
      setState(() {
        _checkedIn = false;
        _distanceMeters = null;
      });
      _bindTodayCheckin();
    }
  }

  void _bindTodayCheckin() {
    _checkinSubscription?.cancel();
    final repository = widget.repository;
    if (repository == null) return;
    _checkinSubscription = repository
        .watchTodayCheckin(widget.activeCourt.id)
        .listen((record) {
          if (!mounted) return;
          setState(() {
            _checkedIn = record != null;
            _distanceMeters = record?.distanceMeters;
          });
        });
  }

  @override
  void dispose() {
    _checkinSubscription?.cancel();
    super.dispose();
  }

  Future<void> _performCheckIn() async {
    if (_checking || _checkedIn) return;
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _checkedIn = true;
        _distanceMeters = 42;
        _stampPulse += 1;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() => _checking = true);
    try {
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
        widget.activeCourt.latitude,
        widget.activeCourt.longitude,
      );
      await repository.checkIn(
        court: widget.activeCourt,
        actualLatitude: position.latitude,
        actualLongitude: position.longitude,
        distanceMeters: distance,
      );
      if (mounted) {
        setState(() {
          _distanceMeters = distance;
          _stampPulse += 1;
        });
      }
      HapticFeedback.mediumImpact();
      _show('체크인 완료');
    } on TimeoutException {
      _show('현재 위치를 확인하지 못했어요. 다시 시도해주세요.');
    } catch (error) {
      _show(error is BackcourtException ? error.message : '체크인에 실패했어요.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        '체크인',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 28,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Text(
                      '${now.month}월 ${now.day}일',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 22),
                _CheckInPanel(
                  court: widget.activeCourt,
                  checkedIn: _checkedIn,
                  checking: _checking,
                  distanceMeters: _distanceMeters,
                  onCheckIn: _performCheckIn,
                ),
                SizedBox(height: 30),
                const _SectionHeader(title: '이번 달'),
                SizedBox(height: 12),
                _MonthlyCourtCard(
                  repository: widget.repository,
                  activeCourt: widget.activeCourt,
                  checkedIn: _checkedIn,
                  stampPulse: _stampPulse,
                ),
                SizedBox(height: 30),
                const _SectionHeader(title: '플레이 기록'),
                SizedBox(height: 12),
                _PlayRecordCard(
                  repository: widget.repository,
                  activeCourt: widget.activeCourt,
                  checkedIn: _checkedIn,
                ),
                SizedBox(height: 30),
                _SectionHeader(title: '체크인 랭킹', trailing: '${now.month}월'),
                SizedBox(height: 12),
                _AttendanceRankingCard(repository: widget.repository),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );
}

class _CheckInPanel extends StatelessWidget {
  const _CheckInPanel({
    required this.court,
    required this.checkedIn,
    required this.checking,
    required this.distanceMeters,
    required this.onCheckIn,
  });

  final CourtSummary court;
  final bool checkedIn;
  final bool checking;
  final double? distanceMeters;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: checkedIn
              ? AppColors.success.withValues(alpha: .28)
              : AppColors.text.withValues(alpha: .07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.6,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: checkedIn ? AppColors.success : AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            checkedIn
                ? '${now.month}.${now.day} 체크인 완료'
                : '코트 100m 안에서 체크인할 수 있어요',
            style: TextStyle(
              color: checkedIn ? AppColors.success : AppColors.soft,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (checkedIn && distanceMeters != null) ...[
            SizedBox(height: 4),
            Text(
              '코트에서 ${distanceMeters!.round()}m',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
          SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              key: const ValueKey('check-in-button'),
              onPressed: checkedIn || checking ? null : onCheckIn,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.text,
                foregroundColor: AppColors.inverseText,
                disabledBackgroundColor: checkedIn
                    ? AppColors.success.withValues(alpha: .12)
                    : AppColors.text.withValues(alpha: .08),
                disabledForegroundColor: checkedIn
                    ? AppColors.success
                    : AppColors.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: checking
                  ? SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(
                        color: AppColors.inverseText,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      checkedIn ? '체크인 완료' : 'GPS로 체크인',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 12),
          Center(
            child: Text(
              checkedIn ? '리뷰 작성 가능 · 48시간' : '코트별 하루 한 번',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyCourtCard extends StatelessWidget {
  const _MonthlyCourtCard({
    required this.repository,
    required this.activeCourt,
    required this.checkedIn,
    required this.stampPulse,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;
  final bool checkedIn;
  final int stampPulse;

  @override
  Widget build(BuildContext context) {
    final repository = this.repository;
    if (repository == null) {
      return _MonthlyCourtSurface(
        court: activeCourt,
        count: checkedIn ? 5 : 4,
        stampPulse: stampPulse,
      );
    }
    return StreamBuilder<int>(
      stream: repository.watchMyMonthlyCourtCheckinCount(activeCourt.id),
      builder: (context, snapshot) => _MonthlyCourtSurface(
        court: activeCourt,
        count: snapshot.data ?? 0,
        stampPulse: stampPulse,
        loading: snapshot.connectionState == ConnectionState.waiting,
      ),
    );
  }
}

class _MonthlyCourtSurface extends StatelessWidget {
  const _MonthlyCourtSurface({
    required this.court,
    required this.count,
    required this.stampPulse,
    this.loading = false,
  });

  final CourtSummary court;
  final int count;
  final int stampPulse;
  final bool loading;

  String get _status {
    if (count >= 12) return '이번 달 완성';
    if (count >= 10) return '코트 단골';
    if (count >= 5) return '자주 가는 코트';
    return '체크인 중';
  }

  String get _next {
    if (count >= 12) return '다음 달에 다시 시작';
    if (count >= 10) return '완성까지 ${12 - count}회';
    if (count >= 5) return '코트 단골까지 ${10 - count}회';
    return '자주 가는 코트까지 ${5 - count}회';
  }

  @override
  Widget build(BuildContext context) {
    final visibleCount = count.clamp(0, 12);
    return Container(
      key: const ValueKey('court-pass-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.text.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      court.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.soft,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      _status,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.7,
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: loading ? '-' : '$visibleCount',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                      ),
                    ),
                    TextSpan(
                      text: ' / 12',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          TweenAnimationBuilder<double>(
            key: ValueKey('${stampPulse}_$visibleCount'),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            tween: Tween(end: visibleCount.toDouble()),
            builder: (context, progress, _) => Row(
              children: List.generate(12, (index) {
                final filled = index < progress;
                return Expanded(
                  child: Container(
                    height: 30,
                    margin: EdgeInsets.only(right: index == 11 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: filled
                          ? AppColors.accent
                          : AppColors.text.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(height: 14),
          Text(
            _next,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayRecordCard extends StatefulWidget {
  const _PlayRecordCard({
    required this.repository,
    required this.activeCourt,
    required this.checkedIn,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;
  final bool checkedIn;

  @override
  State<_PlayRecordCard> createState() => _PlayRecordCardState();
}

class _PlayRecordCardState extends State<_PlayRecordCard> {
  StreamSubscription<ActivePlaySession?>? _sessionSubscription;
  ActivePlaySession? _activeSession;
  Timer? _ticker;
  bool _sessionLoaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bindSession();
  }

  @override
  void didUpdateWidget(covariant _PlayRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _bindSession();
  }

  void _bindSession() {
    _sessionSubscription?.cancel();
    _ticker?.cancel();
    _activeSession = null;
    _sessionLoaded = widget.repository == null;
    final repository = widget.repository;
    if (repository == null) return;
    _sessionSubscription = repository.watchActivePlaySession().listen(
      (session) {
        if (!mounted) return;
        _ticker?.cancel();
        setState(() {
          _activeSession = session;
          _sessionLoaded = true;
        });
        if (session != null) {
          _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _sessionLoaded = true);
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  Duration get _elapsed {
    final session = _activeSession;
    if (session == null) return Duration.zero;
    final elapsed = DateTime.now().difference(session.startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _toggleSession() async {
    if (_busy || !_sessionLoaded) return;
    final repository = widget.repository;
    if (repository == null) return;
    if (_activeSession == null && !widget.checkedIn) {
      _show('GPS 체크인 필요');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_activeSession == null) {
        await repository.startPlaySession(court: widget.activeCourt);
        _show('플레이 기록 시작');
      } else {
        final minutes = await repository.endPlaySession();
        _show('${_formatPlayMinutes(minutes)} 기록');
      }
    } catch (error) {
      _show(error is BackcourtException ? error.message : '플레이 기록 저장 실패');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      const preview = [
        MonthlyPlayStat(
          uid: '1',
          displayName: '민준킴',
          monthKey: 'preview',
          totalMinutes: 1120,
          sessionCount: 12,
        ),
        MonthlyPlayStat(
          uid: '2',
          displayName: '농구하는준',
          monthKey: 'preview',
          totalMinutes: 870,
          sessionCount: 9,
        ),
        MonthlyPlayStat(
          uid: '3',
          displayName: '수아',
          monthKey: 'preview',
          totalMinutes: 745,
          sessionCount: 8,
        ),
      ];
      return _PlayRecordSurface(
        stats: preview,
        activeCourt: widget.activeCourt,
        currentUid: 'preview',
        activeSession: null,
        elapsed: Duration.zero,
        checkedIn: widget.checkedIn,
        busy: false,
        loaded: true,
        onToggle: null,
      );
    }
    return StreamBuilder<List<MonthlyPlayStat>>(
      stream: repository.watchMonthlyPlayRanking(widget.activeCourt),
      builder: (context, snapshot) => _PlayRecordSurface(
        stats: snapshot.data ?? const [],
        activeCourt: widget.activeCourt,
        currentUid: repository.currentUid,
        activeSession: _activeSession,
        elapsed: _elapsed,
        checkedIn: widget.checkedIn,
        busy: _busy,
        loaded:
            _sessionLoaded &&
            snapshot.connectionState != ConnectionState.waiting,
        onToggle: _toggleSession,
      ),
    );
  }
}

class _PlayRecordSurface extends StatelessWidget {
  const _PlayRecordSurface({
    required this.stats,
    required this.activeCourt,
    required this.currentUid,
    required this.activeSession,
    required this.elapsed,
    required this.checkedIn,
    required this.busy,
    required this.loaded,
    required this.onToggle,
  });

  final List<MonthlyPlayStat> stats;
  final CourtSummary activeCourt;
  final String currentUid;
  final ActivePlaySession? activeSession;
  final Duration elapsed;
  final bool checkedIn;
  final bool busy;
  final bool loaded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    MonthlyPlayStat? mine;
    var myRank = 0;
    for (var index = 0; index < stats.length; index++) {
      if (stats[index].uid == currentUid) {
        mine = stats[index];
        myRank = index + 1;
        break;
      }
    }
    final activeMinutes = activeSession?.courtId == activeCourt.id
        ? elapsed.inMinutes
        : 0;
    final totalMinutes = (mine?.totalMinutes ?? 0) + activeMinutes;
    final canStart = activeSession != null || checkedIn;

    return Container(
      key: const ValueKey('court-ranking-summary-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.text.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activeCourt.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  _formatPlayMinutes(totalMinutes),
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4,
                  ),
                ),
              ),
              Text(
                myRank == 0 ? '순위 -' : '$myRank위',
                style: TextStyle(
                  color: myRank == 1 ? AppColors.accent : AppColors.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (activeSession != null) ...[
            SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '기록 중',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _formatStopwatch(elapsed),
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 22),
          Text(
            '이 코트 상위 기록',
            style: TextStyle(
              color: AppColors.soft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 7),
          if (!loaded)
            SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (stats.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '아직 기록이 없어요',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            )
          else
            for (var index = 0; index < math.min(3, stats.length); index++)
              _SimpleRankRow(
                rank: index + 1,
                name: stats[index].uid == currentUid
                    ? '${stats[index].displayName} · 나'
                    : stats[index].displayName,
                value: _formatPlayMinutes(stats[index].totalMinutes),
                highlighted: stats[index].uid == currentUid,
              ),
          SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const ValueKey('toggle-play-session'),
              onPressed: busy || !loaded || !canStart ? null : onToggle,
              style: FilledButton.styleFrom(
                backgroundColor: activeSession == null
                    ? AppColors.text
                    : AppColors.accent,
                foregroundColor: activeSession == null
                    ? AppColors.inverseText
                    : AppColors.onAccent,
                disabledBackgroundColor: AppColors.text.withValues(alpha: .07),
                disabledForegroundColor: AppColors.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: busy
                  ? SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        color: activeSession == null
                            ? AppColors.inverseText
                            : AppColors.onAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      activeSession != null
                          ? '기록 종료'
                          : checkedIn
                          ? '플레이 기록 시작'
                          : '체크인 후 기록 가능',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceRankingCard extends StatelessWidget {
  const _AttendanceRankingCard({this.repository});

  final BackcourtRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repository = this.repository;
    if (repository != null) {
      return StreamBuilder<List<RankingEntry>>(
        stream: repository.watchMonthlyRanking(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _AttendanceRankingSurface(
            users: snapshot.data!,
            currentUid: repository.currentUid,
          );
        },
      );
    }
    return const _AttendanceRankingSurface(
      users: [
        RankingEntry(uid: '1', displayName: '민준킴', count: 18),
        RankingEntry(uid: '2', displayName: '농구하는준', count: 16),
        RankingEntry(uid: '3', displayName: '수아', count: 13),
        RankingEntry(uid: 'preview', displayName: '나', count: 7),
      ],
      currentUid: 'preview',
    );
  }
}

class _AttendanceRankingSurface extends StatelessWidget {
  const _AttendanceRankingSurface({
    required this.users,
    required this.currentUid,
  });

  final List<RankingEntry> users;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Text(
            '아직 체크인 기록이 없어요',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      );
    }
    final top = users.take(5).toList(growable: false);
    RankingEntry? mine;
    for (final user in users) {
      if (user.uid == currentUid) {
        mine = user;
        break;
      }
    }
    final myRank = users.indexWhere((user) => user.uid == currentUid) + 1;
    final mineVisible = top.any((user) => user.uid == currentUid);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.text.withValues(alpha: .07)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < top.length; index++)
            _SimpleRankRow(
              rank: index + 1,
              name: top[index].uid == currentUid
                  ? '${top[index].displayName} · 나'
                  : top[index].displayName,
              value: '${top[index].count}회',
              highlighted: top[index].uid == currentUid,
              divider: index != top.length - 1,
            ),
          if (mine != null && !mineVisible) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1),
            ),
            _SimpleRankRow(
              rank: myRank,
              name: '${mine.displayName} · 나',
              value: '${mine.count}회',
              highlighted: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SimpleRankRow extends StatelessWidget {
  const _SimpleRankRow({
    required this.rank,
    required this.name,
    required this.value,
    required this.highlighted,
    this.divider = false,
  });

  final int rank;
  final String name;
  final String value;
  final bool highlighted;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank == 1 ? AppColors.accent : AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ? AppColors.text : AppColors.soft,
                  fontSize: 13,
                  fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: highlighted ? AppColors.accent : AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      if (divider) Divider(height: 1),
    ],
  );
}

String _formatPlayMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return hours == 0 ? '$rest분' : '$hours시간 ${rest.toString().padLeft(2, '0')}분';
}

String _formatStopwatch(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
