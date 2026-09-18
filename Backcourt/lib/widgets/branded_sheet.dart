import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BackcourtSheetHeader extends StatelessWidget {
  const BackcourtSheetHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 19),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.7,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.9,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              Material(
                color: AppColors.surfaceHigh,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onClose,
                  customBorder: const CircleBorder(),
                  child: const SizedBox.square(
                    dimension: 39,
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.soft,
                      size: 19,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class BackcourtContextCard extends StatelessWidget {
  const BackcourtContextCard({
    super.key,
    required this.title,
    required this.caption,
    this.icon = Icons.sports_basketball_rounded,
    this.badge,
  });

  final String title;
  final String caption;
  final IconData icon;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: .18),
              ),
            ),
            child: Icon(icon, color: AppColors.accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  caption,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BackcourtSectionLabel extends StatelessWidget {
  const BackcourtSectionLabel({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.soft,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class BackcourtMediaAction extends StatelessWidget {
  const BackcourtMediaAction({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: .1)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: .32)
                  : Colors.white.withValues(alpha: .06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent.withValues(alpha: .16)
                      : Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  active ? Icons.check_rounded : icon,
                  color: active ? AppColors.accent : AppColors.soft,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BackcourtPrimaryAction extends StatelessWidget {
  const BackcourtPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: .36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 18),
                ],
              ),
      ),
    );
  }
}

BoxDecoration backcourtSheetDecoration() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
  boxShadow: const [
    BoxShadow(color: Colors.black54, blurRadius: 34, offset: Offset(0, -10)),
  ],
);
