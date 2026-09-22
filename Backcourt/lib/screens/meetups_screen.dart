import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';

Future<void> showCreateMeetupSheet(
  BuildContext context, {
  required BackcourtRepository? repository,
  required CourtSummary court,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _CreateMeetupSheet(repository: repository, court: court),
  );
}

class MeetupsScreen extends StatefulWidget {
  const MeetupsScreen({
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
  State<MeetupsScreen> createState() => _MeetupsScreenState();
}

class _MeetupsScreenState extends State<MeetupsScreen> {
  int _filter = 0;

  static const _games = [
    _GameData('19:30', '한강 시민공원 농구장', '3 vs 3 · 반코트', 4, 6, '240m', '중급'),
    _GameData('21:00', '여의도공원 농구코트', '5 vs 5 · 풀코트', 7, 10, '680m', '누구나'),
    _GameData('내일 10:00', '서울숲 농구장', '3 vs 3 · 반코트', 5, 6, '5.2km', '초급'),
  ];

  Stream<List<MeetupRecord>> _meetupStream(BackcourtRepository repository) =>
      switch (_filter) {
        1 => repository.watchTodayMeetups(),
        2 => repository.watchCourtMeetups(widget.activeCourt.id),
        _ => repository.watchMeetups(),
      };

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository != null) {
      return StreamBuilder<List<MeetupRecord>>(
        stream: _meetupStream(repository),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildContent(const [], error: true);
          }
          if (!snapshot.hasData) {
            return SafeArea(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _buildContent([
            for (final meetup in snapshot.data!) _GameData.fromMeetup(meetup),
          ]);
        },
      );
    }
    return _buildContent(_games);
  }

  Widget _buildContent(List<_GameData> games, {bool error = false}) {
    final now = DateTime.now();
    final visibleGames = games
        .where((game) {
          final record = game.record;
          if (record == null) return true;
          return switch (_filter) {
            0 => true,
            1 =>
              record.startsAt.year == now.year &&
                  record.startsAt.month == now.month &&
                  record.startsAt.day == now.day,
            _ => record.courtId == widget.activeCourt.id,
          };
        })
        .toList(growable: false);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, widget.embedded ? 10 : 20, 20, 0),
            sliver: SliverList.list(
              children: [
                if (!widget.embedded) ...[
                  PageHeader(
                    eyebrow: 'PLAY',
                    title: '플레이',
                    action: RoundIconButton(
                      key: const ValueKey('create-meetup-button'),
                      icon: Icons.add_rounded,
                      light: true,
                      onTap: () => showCreateMeetupSheet(
                        context,
                        repository: widget.repository,
                        court: widget.activeCourt,
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                ],
                if (!widget.embedded) ...[
                  _SelectedCourt(court: widget.activeCourt),
                  SizedBox(height: 12),
                ],
                _SegmentedFilter(
                  selected: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                SizedBox(height: 23),
                SectionTitle(
                  title: '다가오는 약속',
                  trailing: '${visibleGames.length}개',
                ),
                SizedBox(height: 11),
                if (visibleGames.isNotEmpty)
                  _NextGameCard(
                    game: visibleGames.first,
                    onTap: () => _showGame(context, visibleGames.first),
                  )
                else
                  _EmptyMeetups(error: error),
                if (visibleGames.length > 1) ...[SizedBox(height: 10)],
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: visibleGames.length <= 1
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverList.separated(
                    itemCount: visibleGames.length - 1,
                    separatorBuilder: (_, _) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final game = visibleGames[index + 1];
                      return _GameCard(
                        game: game,
                        onTap: () => _showGame(context, game),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showGame(BuildContext context, _GameData game) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) =>
          _GameDetail(game: game, repository: widget.repository),
    );
  }
}

class _EmptyMeetups extends StatelessWidget {
  const _EmptyMeetups({required this.error});

  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.text.withValues(alpha: .06)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sports_basketball_outlined,
            color: AppColors.muted,
            size: 21,
          ),
        ),
        SizedBox(width: 13),
        Text(
          error ? '약속을 불러오지 못했어요' : '아직 잡힌 약속이 없어요',
          style: TextStyle(
            color: AppColors.soft,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _SelectedCourt extends StatelessWidget {
  const _SelectedCourt({required this.court});

  final CourtSummary court;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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

class _CreateMeetupSheet extends StatefulWidget {
  const _CreateMeetupSheet({required this.repository, required this.court});

  final BackcourtRepository? repository;
  final CourtSummary court;

  @override
  State<_CreateMeetupSheet> createState() => _CreateMeetupSheetState();
}

class _CreateMeetupSheetState extends State<_CreateMeetupSheet> {
  late DateTime _startsAt = DateTime.now().add(const Duration(hours: 2));
  int _capacity = 6;
  String _gameType = '3 vs 3 · 반코트';
  String _level = '누구나';
  bool _saving = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final repository = widget.repository;
    if (repository == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await repository.createMeetup(
        court: widget.court,
        startsAt: _startsAt,
        capacity: _capacity,
        gameType: _gameType,
        level: _level,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '약속 생성 실패',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_startsAt.month}월 ${_startsAt.day}일 · '
        '${_startsAt.hour.toString().padLeft(2, '0')}:'
        '${_startsAt.minute.toString().padLeft(2, '0')}';
    return DraggableScrollableSheet(
      initialChildSize: .84,
      minChildSize: .64,
      maxChildSize: .95,
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
                  eyebrow: 'NEW GAME',
                  title: '약속 만들기',
                  onClose: () => Navigator.pop(context),
                ),
              ),
              SizedBox(height: 18),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  children: [
                    BackcourtContextCard(
                      title: widget.court.name,
                      caption: '선택 코트',
                      icon: Icons.place_rounded,
                      badge: 'COURT',
                    ),
                    SizedBox(height: 22),
                    const BackcourtSectionLabel(title: '날짜 · 시간'),
                    SizedBox(height: 9),
                    InkWell(
                      onTap: _pickDateTime,
                      borderRadius: BorderRadius.circular(17),
                      child: _FormRow(
                        icon: Icons.calendar_today_rounded,
                        title: dateLabel,
                        caption: '시작',
                      ),
                    ),
                    SizedBox(height: 12),
                    BackcourtSectionLabel(title: '정원', trailing: '$_capacity명'),
                    Slider(
                      value: _capacity.toDouble(),
                      min: 2,
                      max: 30,
                      divisions: 28,
                      activeColor: AppColors.accent,
                      onChanged: (value) =>
                          setState(() => _capacity = value.round()),
                    ),
                    SizedBox(height: 10),
                    const BackcourtSectionLabel(title: '게임'),
                    SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _gameType,
                            dropdownColor: AppColors.surfaceHigh,
                            decoration: InputDecoration(labelText: '방식'),
                            items: const [
                              DropdownMenuItem(
                                value: '3 vs 3 · 반코트',
                                child: Text('3 vs 3'),
                              ),
                              DropdownMenuItem(
                                value: '5 vs 5 · 풀코트',
                                child: Text('5 vs 5'),
                              ),
                              DropdownMenuItem(
                                value: '자유 슈팅',
                                child: Text('자유 슈팅'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _gameType = value!),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _level,
                            dropdownColor: AppColors.surfaceHigh,
                            decoration: InputDecoration(labelText: '레벨'),
                            items: const [
                              DropdownMenuItem(
                                value: '누구나',
                                child: Text('누구나'),
                              ),
                              DropdownMenuItem(value: '초급', child: Text('초급')),
                              DropdownMenuItem(value: '중급', child: Text('중급')),
                              DropdownMenuItem(value: '상급', child: Text('상급')),
                            ],
                            onChanged: (value) =>
                                setState(() => _level = value!),
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
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('submit-meetup'),
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? '저장 중' : '약속 만들기'),
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

class _SegmentedFilter extends StatelessWidget {
  const _SegmentedFilter({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['전체', '오늘', '이 코트'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = selected == index;
        return Padding(
          padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
          child: SizedBox(
            width: index == 2 ? 78 : 64,
            child: Material(
              color: active ? AppColors.text : AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: () => onChanged(index),
                borderRadius: BorderRadius.circular(99),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: active
                          ? AppColors.text
                          : AppColors.text.withValues(alpha: .06),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      color: active ? AppColors.inverseText : AppColors.soft,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _NextGameCard extends StatelessWidget {
  const _NextGameCard({required this.game, required this.onTap});

  final _GameData game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = game.capacity - game.current;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.accent.withValues(alpha: .25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 7),
                  Text(
                    '가장 빠른 약속',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: remaining <= 0
                          ? AppColors.surfaceHigh
                          : AppColors.accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      remaining <= 0 ? '마감' : '$remaining자리 남음',
                      style: TextStyle(
                        color: remaining <= 0
                            ? AppColors.muted
                            : AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Text(
                game.time,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 29,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              SizedBox(height: 9),
              Text(
                game.court,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                '${game.type} · ${game.level}',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    color: AppColors.muted,
                    size: 18,
                  ),
                  SizedBox(width: 7),
                  Text(
                    '${game.current}/${game.capacity}명 참가',
                    style: TextStyle(
                      color: AppColors.soft,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.text,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onTap});

  final _GameData game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = game.capacity - game.current;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      game.dayLabel,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      game.clockLabel,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.court,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '${game.type} · ${game.level}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '${game.current}/${game.capacity}명 참가',
                      style: TextStyle(
                        color: AppColors.soft,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Text(
                remaining <= 0 ? '마감' : '$remaining자리',
                style: TextStyle(
                  color: remaining <= 0 ? AppColors.muted : AppColors.accent,
                  fontSize: 12,
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

class _GameDetail extends StatefulWidget {
  const _GameDetail({required this.game, required this.repository});

  final _GameData game;
  final BackcourtRepository? repository;

  @override
  State<_GameDetail> createState() => _GameDetailState();
}

class _GameDetailState extends State<_GameDetail> {
  late bool _joined =
      widget.game.record?.participantUids.contains(
        widget.repository?.currentUid,
      ) ??
      false;
  bool _updating = false;

  bool get _createdByMe {
    final repository = widget.repository;
    final record = widget.game.record;
    return repository != null &&
        record != null &&
        record.createdBy == repository.currentUid;
  }

  Future<void> _toggleJoin() async {
    final repository = widget.repository;
    final record = widget.game.record;
    if (repository == null || record == null) {
      setState(() => _joined = !_joined);
      return;
    }
    setState(() => _updating = true);
    try {
      await repository.toggleMeetupParticipation(record);
      if (mounted) setState(() => _joined = !_joined);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '참가 처리 실패',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _cancelMeetup() async {
    final repository = widget.repository;
    final record = widget.game.record;
    if (repository == null || record == null || _updating) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('약속 취소'),
            content: Text('참가자에게 취소 알림이 가요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('닫기'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('약속 취소'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _updating = true);
    try {
      await repository.cancelMeetup(record);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '약속 취소 실패',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  game.time,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              Text(
                game.current >= game.capacity
                    ? '마감'
                    : '${game.capacity - game.current}자리',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          Text(game.court, style: Theme.of(context).textTheme.headlineMedium),
          SizedBox(height: 7),
          Text(
            game.distance.isEmpty
                ? '${game.type} · ${game.level}'
                : '${game.type} · ${game.level} · ${game.distance}',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          SizedBox(height: 24),
          Row(
            children: [
              AvatarStack(count: game.current.clamp(1, 4)),
              SizedBox(width: 12),
              Text(
                '${game.current}/${game.capacity}명 참가 중',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: 24),
          if (_createdByMe)
            OutlinedButton.icon(
              key: const ValueKey('cancel-meetup'),
              onPressed: _updating ? null : _cancelMeetup,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: .4)),
              ),
              icon: Icon(Icons.event_busy_rounded, size: 18),
              label: Center(child: Text(_updating ? '처리 중' : '약속 취소')),
            )
          else
            FilledButton(
              key: const ValueKey('join-game'),
              onPressed:
                  _updating || (!_joined && game.current >= game.capacity)
                  ? null
                  : _toggleJoin,
              style: FilledButton.styleFrom(
                backgroundColor: _joined
                    ? AppColors.surfaceHigh
                    : AppColors.text,
                foregroundColor: _joined
                    ? AppColors.text
                    : AppColors.inverseText,
              ),
              child: Center(
                child: Text(
                  _updating
                      ? '처리 중'
                      : _joined
                      ? '참가 취소'
                      : game.current >= game.capacity
                      ? '정원 마감'
                      : '참가',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: AppColors.text),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _GameData {
  const _GameData(
    this.time,
    this.court,
    this.type,
    this.current,
    this.capacity,
    this.distance,
    this.level,
  ) : record = null;

  factory _GameData.fromMeetup(MeetupRecord meetup) => _GameData._(
    _formatMeetupTime(meetup.startsAt),
    meetup.courtName,
    meetup.gameType,
    meetup.participantUids.length,
    meetup.capacity,
    '',
    meetup.level,
    meetup,
  );

  const _GameData._(
    this.time,
    this.court,
    this.type,
    this.current,
    this.capacity,
    this.distance,
    this.level,
    this.record,
  );

  final String time;
  final String court;
  final String type;
  final int current;
  final int capacity;
  final String distance;
  final String level;
  final MeetupRecord? record;

  String get dayLabel {
    final startsAt = record?.startsAt;
    if (startsAt == null) {
      return time.contains(' ') ? time.split(' ').first : '오늘';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final days = target.difference(today).inDays;
    if (days == 0) return '오늘';
    if (days == 1) return '내일';
    return '${startsAt.month}/${startsAt.day}';
  }

  String get clockLabel {
    final startsAt = record?.startsAt;
    if (startsAt != null) {
      return '${startsAt.hour.toString().padLeft(2, '0')}:'
          '${startsAt.minute.toString().padLeft(2, '0')}';
    }
    return time.contains(' ') ? time.split(' ').last : time;
  }

  static String _formatMeetupTime(DateTime value) {
    final now = DateTime.now();
    final prefix =
        value.year == now.year &&
            value.month == now.month &&
            value.day == now.day
        ? ''
        : '${value.month}/${value.day} ';
    return '$prefix${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
