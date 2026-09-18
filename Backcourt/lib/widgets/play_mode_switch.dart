import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PlayModeSwitch extends StatelessWidget {
  const PlayModeSwitch({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['LIVE', '약속'];
    const icons = [Icons.sensors_rounded, Icons.calendar_month_rounded];
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - 8) / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('play-mode-indicator'),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: 4 + segmentWidth * selectedIndex,
                top: 4,
                bottom: 4,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: List.generate(labels.length, (index) {
                    final selected = index == selectedIndex;
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('play-mode-$index'),
                          onTap: () => onSelected(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                child: Icon(
                                  icons[index],
                                  key: ValueKey(selected),
                                  size: 16,
                                  color: selected
                                      ? Colors.black
                                      : AppColors.muted,
                                ),
                              ),
                              const SizedBox(width: 7),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 160),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                                child: Text(labels[index]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
