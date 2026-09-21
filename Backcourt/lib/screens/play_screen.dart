import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/play_mode_switch.dart';
import 'live_court_screen.dart';
import 'map_screen.dart';
import 'meetups_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.repository,
    required this.activeCourt,
    this.homeCourts = const [],
    this.onCourtSelected,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;
  final List<CourtSummary> homeCourts;
  final ValueChanged<CourtSummary>? onCourtSelected;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '플레이',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(begin: .9, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _selectedIndex == 0
                          ? RoundIconButton(
                              key: const ValueKey('live-info-button'),
                              icon: Icons.info_outline_rounded,
                              onTap: () => showLiveCourtInfo(context),
                            )
                          : RoundIconButton(
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
                  ],
                ),
                const SizedBox(height: 9),
                _ActiveCourtLine(
                  court: widget.activeCourt,
                  onTap: _openHomeCourts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: PlayModeSwitch(
              key: const ValueKey('play-mode-switch'),
              selectedIndex: _selectedIndex,
              onSelected: (index) {
                if (_selectedIndex != index) {
                  setState(() => _selectedIndex = index);
                }
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                LiveCourtScreen(
                  repository: widget.repository,
                  activeCourt: widget.activeCourt,
                  embedded: true,
                ),
                MeetupsScreen(
                  repository: widget.repository,
                  activeCourt: widget.activeCourt,
                  embedded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHomeCourts() async {
    final selected = await showModalBottomSheet<CourtSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _HomeCourtsSheet(
        repository: widget.repository,
        activeCourt: widget.activeCourt,
        initialCourts: widget.homeCourts,
      ),
    );
    if (selected == null || !mounted) return;
    widget.onCourtSelected?.call(selected);
  }
}

class _ActiveCourtLine extends StatelessWidget {
  const _ActiveCourtLine({required this.court, required this.onTap});

  final CourtSummary court;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('home-court-switcher'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.place_rounded,
              size: 14,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              court.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.soft,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.unfold_more_rounded,
            color: AppColors.muted,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _HomeCourtsSheet extends StatefulWidget {
  const _HomeCourtsSheet({
    required this.repository,
    required this.activeCourt,
    required this.initialCourts,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;
  final List<CourtSummary> initialCourts;

  @override
  State<_HomeCourtsSheet> createState() => _HomeCourtsSheetState();
}

class _HomeCourtsSheetState extends State<_HomeCourtsSheet> {
  late final List<CourtSummary> _courts = List.of(widget.initialCourts);
  late String _activeId = widget.activeCourt.id;
  bool _busy = false;

  void _showError(Object error) {
    final message = error is BackcourtException
        ? error.message
        : '잠시 후 다시 시도해주세요.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _select(CourtSummary court) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await widget.repository?.setActiveCourt(court);
      if (!mounted) return;
      Navigator.pop(context, court);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  Future<void> _add() async {
    if (_busy || _courts.length >= 3) return;
    final selected = await Navigator.of(context).push<CourtSummary>(
      MaterialPageRoute(
        builder: (pickerContext) => Scaffold(
          backgroundColor: AppColors.background,
          body: MapScreen(
            repository: widget.repository,
            initialCourt: widget.activeCourt,
            pickerMode: true,
            onPickerClose: () => Navigator.pop(pickerContext),
            onCourtSelected: (court) => Navigator.pop(pickerContext, court),
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (_courts.any((court) => court.id == selected.id)) {
      await _select(selected);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository?.addHomeCourt(selected);
      if (!mounted) return;
      setState(() {
        _courts.add(selected);
        _activeId = selected.id;
        _busy = false;
      });
      Navigator.pop(context, selected);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  Future<void> _remove(CourtSummary court) async {
    if (_busy || _courts.length <= 1) return;
    final wasActive = _activeId == court.id;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final next = await widget.repository?.removeHomeCourt(court.id);
      if (!mounted) return;
      setState(() {
        _courts.removeWhere((saved) => saved.id == court.id);
        if (_activeId == court.id && next != null) _activeId = next.id;
        _busy = false;
      });
      if (wasActive && next != null) {
        Navigator.pop(context, next);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '홈코트',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                Text(
                  '${_courts.length}/3',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              '자주 뛰는 코트를 저장하고 바로 바꿔보세요.',
              style: TextStyle(color: AppColors.soft, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ..._courts.map(
              (court) => _HomeCourtTile(
                court: court,
                selected: court.id == _activeId,
                removeEnabled: _courts.length > 1 && !_busy,
                onTap: () => _select(court),
                onRemove: () => _remove(court),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                key: const ValueKey('add-home-court'),
                onPressed: _courts.length >= 3 || _busy ? null : _add,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(_courts.length >= 3 ? '홈코트 3개 저장됨' : '홈코트 추가'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: .45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCourtTile extends StatelessWidget {
  const _HomeCourtTile({
    required this.court,
    required this.selected,
    required this.removeEnabled,
    required this.onTap,
    required this.onRemove,
  });

  final CourtSummary court;
  final bool selected;
  final bool removeEnabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: selected
          ? AppColors.accent.withValues(alpha: .1)
          : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? AppColors.accent.withValues(alpha: .55)
              : Colors.white.withValues(alpha: .07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(15, 5, 8, 5),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.white10,
            shape: BoxShape.circle,
          ),
          child: Icon(
            selected ? Icons.check_rounded : Icons.sports_basketball_rounded,
            color: selected ? Colors.black : Colors.white70,
            size: 20,
          ),
        ),
        title: Text(
          court.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          selected ? '현재 코트' : court.address ?? '홈코트',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: IconButton(
          tooltip: '홈코트 삭제',
          onPressed: removeEnabled ? onRemove : null,
          icon: const Icon(Icons.close_rounded, size: 19),
          color: AppColors.muted,
        ),
      ),
    ),
  );
}
