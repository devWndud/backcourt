import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

typedef CourtRankingStream =
    Stream<List<MonthlyPlayStat>> Function(CourtRankingPeriod period);

class CourtRankingCard extends StatefulWidget {
  const CourtRankingCard({
    super.key,
    this.repository,
    required this.court,
    this.previewStream,
    this.previewCurrentUid,
  }) : assert(repository != null || previewStream != null);

  final BackcourtRepository? repository;
  final CourtSummary court;
  final CourtRankingStream? previewStream;
  final String? previewCurrentUid;

  @override
  State<CourtRankingCard> createState() => _CourtRankingCardState();
}

class _CourtRankingCardState extends State<CourtRankingCard> {
  CourtRankingPeriod _period = CourtRankingPeriod.month;

  @override
  void didUpdateWidget(covariant CourtRankingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.court.id != widget.court.id) {
      _period = CourtRankingPeriod.month;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('court-ranking-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: AppColors.onAccent,
                    size: 21,
                  ),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COURT RANKING',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '코트 랭킹',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
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
                    color: AppColors.text.withValues(alpha: .065),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'PLAY TIME',
                    style: TextStyle(
                      color: AppColors.soft,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              height: 39,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.subtleFill,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: AppColors.text.withValues(alpha: .055),
                ),
              ),
              child: Row(
                children: [
                  _PeriodButton(
                    key: const ValueKey('court-ranking-period-all'),
                    label: '전체',
                    selected: _period == CourtRankingPeriod.all,
                    onTap: () => _select(CourtRankingPeriod.all),
                  ),
                  _PeriodButton(
                    key: const ValueKey('court-ranking-period-month'),
                    label: '달',
                    selected: _period == CourtRankingPeriod.month,
                    onTap: () => _select(CourtRankingPeriod.month),
                  ),
                  _PeriodButton(
                    key: const ValueKey('court-ranking-period-week'),
                    label: '주',
                    selected: _period == CourtRankingPeriod.week,
                    onTap: () => _select(CourtRankingPeriod.week),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _periodCaption,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 9),
            StreamBuilder<List<MonthlyPlayStat>>(
              stream:
                  widget.previewStream?.call(_period) ??
                  widget.repository!.watchCourtPlayRanking(
                    widget.court,
                    _period,
                  ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _RankingMessage(
                    icon: Icons.cloud_off_rounded,
                    title: '랭킹 불러오기 실패',
                    caption: '다시 시도',
                  );
                }
                if (!snapshot.hasData) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  );
                }
                final stats = snapshot.data!;
                if (stats.isEmpty) {
                  return const _RankingMessage(
                    icon: Icons.sports_basketball_outlined,
                    title: '기록 없음',
                    caption: 'GPS 체크인 · 플레이 기록',
                  );
                }
                return Column(
                  children: [
                    for (
                      var index = 0;
                      index < stats.length && index < 10;
                      index++
                    )
                      _RankingRow(
                        rank: index + 1,
                        stat: stats[index],
                        isMe:
                            stats[index].uid ==
                            (widget.previewCurrentUid ??
                                widget.repository?.currentUid),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _select(CourtRankingPeriod period) {
    if (_period != period) setState(() => _period = period);
  }

  String get _periodCaption => switch (_period) {
    CourtRankingPeriod.all => '이 코트 누적 랭킹',
    CourtRankingPeriod.month => '${DateTime.now().month}월 랭킹',
    CourtRankingPeriod.week => '이번 주 월요일부터 오늘까지',
  };
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.text : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.inverseText : AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.stat,
    required this.isMe,
  });

  final int rank;
  final MonthlyPlayStat stat;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final name = stat.displayName.trim().isEmpty ? '플레이어' : stat.displayName;
    final photoUrl = stat.photoUrl;
    const fallback = DefaultProfileImage();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.accent.withValues(alpha: .1)
            : AppColors.text.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? AppColors.accent.withValues(alpha: .2)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 27,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? AppColors.accent : AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ClipOval(
            child: SizedBox.square(
              dimension: 32,
              child: photoUrl?.isNotEmpty == true
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => fallback,
                    )
                  : fallback,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name · 나' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  stat.username?.isNotEmpty == true
                      ? '@${stat.username}'
                      : '${stat.sessionCount}번 플레이',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            _formatMinutes(stat.totalMinutes),
            style: TextStyle(
              color: rank == 1 ? AppColors.accent : AppColors.soft,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingMessage extends StatelessWidget {
  const _RankingMessage({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.muted, size: 23),
          SizedBox(height: 9),
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest분';
  if (rest == 0) return '$hours시간';
  return '$hours시간 $rest분';
}
