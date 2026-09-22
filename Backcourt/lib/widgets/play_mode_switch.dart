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
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.text.withValues(alpha: .06)),
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
                    borderRadius: BorderRadius.circular(10),
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
                          borderRadius: BorderRadius.circular(10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 160),
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.onAccent
                                      : AppColors.muted,
                                  fontSize: 13,
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
