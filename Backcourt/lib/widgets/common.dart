import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const defaultProfileAsset = 'assets/images/default_profile.png';

class DefaultProfileImage extends StatelessWidget {
  const DefaultProfileImage({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) => Image.asset(
    defaultProfileAsset,
    width: size,
    height: size,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
}

class NmLogo extends StatelessWidget {
  const NmLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 9 : 11),
          child: Image.asset(
            'icon.png',
            width: compact ? 32 : 38,
            height: compact ? 32 : 38,
            fit: BoxFit.cover,
          ),
        ),
        if (!compact) ...[
          SizedBox(width: 9),
          Text(
            '빽코트',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ],
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.action,
  });

  final String eyebrow;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              SizedBox(height: 7),
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.light = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: light ? AppColors.text : AppColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: light ? AppColors.inverseText : AppColors.text,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 34, this.color, this.photoUrl});

  final double size;
  final Color? color;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceHigh,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: photoUrl?.isNotEmpty == true
          ? Image.network(
              photoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => DefaultProfileImage(size: size),
            )
          : DefaultProfileImage(size: size),
    );
  }
}

class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, this.count = 4, this.size = 30});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + (count - 1) * (size * .62),
      height: size,
      child: Stack(
        children: List.generate(
          count,
          (index) => Positioned(
            left: index * (size * .62),
            child: UserAvatar(size: size),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class Stat extends StatelessWidget {
  const Stat({
    super.key,
    required this.value,
    required this.label,
    this.align = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
