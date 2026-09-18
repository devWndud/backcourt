import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: PageHeader(
              eyebrow: 'PLAY',
              title: '플레이',
              action: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: .88, end: 1.0).animate(animation),
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
            ),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 2),
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
