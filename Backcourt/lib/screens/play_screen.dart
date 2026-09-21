import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/play_mode_switch.dart';
import 'live_court_screen.dart';
import 'meetups_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.repository,
    required this.activeCourt,
  });

  final BackcourtRepository? repository;
  final CourtSummary activeCourt;

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
                _ActiveCourtLine(court: widget.activeCourt),
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
}

class _ActiveCourtLine extends StatelessWidget {
  const _ActiveCourtLine({required this.court});

  final CourtSummary court;

  @override
  Widget build(BuildContext context) => Row(
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
    ],
  );
}
