import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

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

class _CheckinScreenState extends State<CheckinScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _checkedIn = false;
  bool _checking = false;
  double? _distanceMeters;
  StreamSubscription<CheckinRecord?>? _checkinSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _bindTodayCheckin();
  }

  @override
  void didUpdateWidget(covariant CheckinScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.activeCourt.id != widget.activeCourt.id) {
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
    _pulseController.dispose();
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
      });
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
      if (mounted) setState(() => _distanceMeters = distance);
      _show('출석 완료');
    } on TimeoutException {
      _show('현재 위치를 확인하지 못했어요. 다시 시도해주세요.');
    } catch (error) {
      _show(error is BackcourtException ? error.message : '출석 인증에 실패했어요.');
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
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            sliver: SliverList.list(
              children: [
                PageHeader(
                  eyebrow: 'CHECK-IN',
                  title: _checkedIn ? '출석 완료' : '출석',
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: _checkedIn
                          ? AppColors.success.withValues(alpha: .35)
                          : Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _checkedIn
                                  ? AppColors.success
                                  : AppColors.accent,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              _checkedIn
                                  ? Icons.check_rounded
                                  : Icons.sports_basketball_rounded,
                              color: _checkedIn ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.activeCourt.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _distanceMeters == null
                                      ? 'GPS · 100m 이내'
                                      : 'GPS · ${_distanceMeters!.round()}m',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_distanceMeters == null
                                          ? Colors.white
                                          : AppColors.success)
                                      .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _distanceMeters == null ? 'GPS' : '인증됨',
                              style: TextStyle(
                                color: _distanceMeters == null
                                    ? AppColors.soft
                                    : AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 270,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) => CustomPaint(
                            painter: _RadarPainter(
                              progress: _pulseController.value,
                              complete: _checkedIn,
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  color: _checkedIn
                                      ? AppColors.success
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_checkedIn
                                                  ? AppColors.success
                                                  : Colors.white)
                                              .withValues(alpha: .2),
                                      blurRadius: 32,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _checkedIn
                                      ? Icons.check_rounded
                                      : Icons.near_me_rounded,
                                  color: Colors.black,
                                  size: 38,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _checkedIn
                            ? '${DateTime.now().month}.${DateTime.now().day} 출석 완료'
                            : '출석 가능',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _checkedIn ? '리뷰 작성 · 48시간' : '코트별 1일 1회',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('check-in-button'),
                        onPressed: _checkedIn || _checking
                            ? null
                            : _performCheckIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: _checkedIn
                              ? AppColors.surfaceHigh
                              : Colors.white,
                          disabledBackgroundColor: AppColors.surfaceHigh,
                          disabledForegroundColor: AppColors.soft,
                        ),
                        child: Center(
                          child: _checking
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_checkedIn ? '완료' : 'GPS 출석'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _CourtKingCard(
                  repository: widget.repository,
                  activeCourt: widget.activeCourt,
                  checkedIn: _checkedIn,
                ),
                const SizedBox(height: 28),
                const SectionTitle(title: '이번 달 랭킹'),
                const SizedBox(height: 13),
                _RankingCard(repository: widget.repository),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtKingCard extends StatefulWidget {
  const _CourtKingCard({
    required this.repository,
    required this.activeCourt,
    required this.checkedIn,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;
  final bool checkedIn;

  @override
  State<_CourtKingCard> createState() => _CourtKingCardState();
}

class _CourtKingCardState extends State<_CourtKingCard> {
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
  void didUpdateWidget(covariant _CourtKingCard oldWidget) {
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
      _show('GPS 출석 필요');
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
      return _CourtKingSurface(
        stats: preview,
        activeCourt: widget.activeCourt,
        currentUid: 'preview',
        activeSession: null,
        elapsed: Duration.zero,
        checkedIn: widget.checkedIn,
        busy: false,
        sessionLoaded: true,
        onToggle: null,
      );
    }

    return StreamBuilder<List<MonthlyPlayStat>>(
      stream: repository.watchMonthlyPlayRanking(widget.activeCourt),
      builder: (context, snapshot) => _CourtKingSurface(
        stats: snapshot.data ?? const [],
        activeCourt: widget.activeCourt,
        currentUid: repository.currentUid,
        activeSession: _activeSession,
        elapsed: _elapsed,
        checkedIn: widget.checkedIn,
        busy: _busy,
        sessionLoaded:
            _sessionLoaded &&
            snapshot.connectionState != ConnectionState.waiting,
        onToggle: _toggleSession,
      ),
    );
  }
}

class _CourtKingSurface extends StatelessWidget {
  const _CourtKingSurface({
    required this.stats,
    required this.activeCourt,
    required this.currentUid,
    required this.activeSession,
    required this.elapsed,
    required this.checkedIn,
    required this.busy,
    required this.sessionLoaded,
    required this.onToggle,
  });

  final List<MonthlyPlayStat> stats;
  final CourtSummary activeCourt;
  final String currentUid;
  final ActivePlaySession? activeSession;
  final Duration elapsed;
  final bool checkedIn;
  final bool busy;
  final bool sessionLoaded;
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
    final month = DateTime.now().month;

    return Container(
      key: const ValueKey('court-king-card'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1B16), Color(0xFF171412), Color(0xFF121212)],
          stops: [0, .52, 1],
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: .24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: .07),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -26,
            child: Icon(
              Icons.emoji_events_rounded,
              size: 132,
              color: AppColors.accent.withValues(alpha: .055),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.black,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COURT KING',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '코트의 제왕',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$month월 시즌',
                        style: const TextStyle(
                          color: AppColors.soft,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${activeCourt.name} · 이번 달',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatPlayMinutes(totalMinutes),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 29,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: .22),
                        ),
                      ),
                      child: Text(
                        myRank == 0 ? '랭킹  -' : '랭킹  #$myRank',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (activeSession != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: .18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PLAYING NOW',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                activeSession!.courtName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.soft,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatStopwatch(elapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      '이 코트 TOP 3',
                      style: TextStyle(
                        color: AppColors.soft,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${mine?.sessionCount ?? 0}번의 플레이',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                if (!sessionLoaded)
                  const SizedBox(
                    height: 62,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (stats.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Text(
                      '기록 없음',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (
                        var index = 0;
                        index < math.min(3, stats.length);
                        index++
                      )
                        _CourtKingRankRow(
                          rank: index + 1,
                          stat: stats[index],
                          me: stats[index].uid == currentUid,
                        ),
                    ],
                  ),
                const SizedBox(height: 17),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const ValueKey('toggle-play-session'),
                    onPressed: busy || !sessionLoaded || !canStart
                        ? null
                        : onToggle,
                    style: FilledButton.styleFrom(
                      backgroundColor: activeSession == null
                          ? Colors.white
                          : AppColors.accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: .08,
                      ),
                      disabledForegroundColor: AppColors.muted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            activeSession == null
                                ? Icons.play_arrow_rounded
                                : Icons.stop_rounded,
                          ),
                    label: Text(
                      activeSession != null
                          ? '플레이 종료'
                          : checkedIn
                          ? '플레이 시작'
                          : '출석 후 시작',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtKingRankRow extends StatelessWidget {
  const _CourtKingRankRow({
    required this.rank,
    required this.stat,
    required this.me,
  });

  final int rank;
  final MonthlyPlayStat stat;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: me
            ? AppColors.accent.withValues(alpha: .09)
            : Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? AppColors.accent : AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              me ? '${stat.displayName}  ·  나' : stat.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.soft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _formatPlayMinutes(stat.totalMinutes),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
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

class _RankingCard extends StatelessWidget {
  const _RankingCard({this.repository});

  final BackcourtRepository? repository;

  @override
  Widget build(BuildContext context) {
    if (repository != null) {
      return StreamBuilder<List<RankingEntry>>(
        stream: repository!.watchMonthlyRanking(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _RankingList(
            users: snapshot.data!,
            currentUid: repository!.currentUid,
          );
        },
      );
    }
    const users = [
      ('1', '민준킴', 'MJ', '18회'),
      ('2', '농구하는준', 'JH', '16회'),
      ('3', '수아', 'SO', '13회'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        children: [
          for (var i = 0; i < users.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      users[i].$1,
                      style: TextStyle(
                        color: i == 0 ? AppColors.accent : AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  UserAvatar(initials: users[i].$3, size: 34),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      users[i].$2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    users[i].$4,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (i != users.length - 1) const Divider(height: 1),
          ],
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Text(
                  '8',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: 18),
                UserAvatar(
                  initials: '나',
                  size: 30,
                  color: AppColors.accentSoft,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '나의 순위',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '7회',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({required this.users, required this.currentUid});

  final List<RankingEntry> users;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(21),
        ),
        child: const Text('출석 기록 없음', style: TextStyle(color: AppColors.muted)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        children: [
          for (var index = 0; index < users.length; index++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              color: users[index].uid == currentUid
                  ? Colors.white.withValues(alpha: .07)
                  : Colors.transparent,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: index == 0 ? AppColors.accent : AppColors.muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  UserAvatar(
                    initials: users[index].displayName.characters
                        .take(2)
                        .toString(),
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      users[index].uid == currentUid
                          ? '${users[index].displayName} (나)'
                          : users[index].displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${users[index].count}회',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress, required this.complete});

  final double progress;
  final bool complete;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1;
      final radius = 64 + phase * 68;
      final opacity = (1 - phase) * .24;
      final paint = Paint()
        ..color = (complete ? AppColors.success : Colors.white).withValues(
          alpha: opacity,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, paint);
    }

    final ticks = Paint()
      ..color = Colors.white.withValues(alpha: .15)
      ..strokeWidth = 2;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24;
      final a = Offset(
        center.dx + math.cos(angle) * 120,
        center.dy + math.sin(angle) * 120,
      );
      final b = Offset(
        center.dx + math.cos(angle) * 125,
        center.dy + math.sin(angle) * 125,
      );
      canvas.drawLine(a, b, ticks);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.complete != complete;
}
