import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';
import '../widgets/common.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.repository});

  final BackcourtRepository? repository;

  @override
  Widget build(BuildContext context) {
    final backend = repository;
    if (backend == null) {
      return RoundIconButton(
        icon: Icons.notifications_none_rounded,
        onTap: () {},
      );
    }
    return StreamBuilder<int>(
      stream: backend.watchUnreadNotificationCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            RoundIconButton(
              key: const ValueKey('notification-button'),
              icon: count > 0
                  ? Icons.notifications_rounded
                  : Icons.notifications_none_rounded,
              onTap: () => showNotificationsSheet(context, backend),
            ),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> showNotificationsSheet(
  BuildContext context,
  BackcourtRepository repository,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _NotificationsSheet(repository: repository),
);

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet({required this.repository});

  final BackcourtRepository repository;

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.repository.markAllNotificationsRead());
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .62,
    minChildSize: .48,
    maxChildSize: .94,
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
                eyebrow: 'ACTIVITY',
                title: '알림',
                onClose: () => Navigator.pop(context),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<AppNotificationRecord>>(
                stream: widget.repository.watchNotifications(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) return const _EmptyNotifications();
                  return ListView.separated(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      8,
                      22,
                      MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => SizedBox(height: 9),
                    itemBuilder: (context, index) =>
                        _NotificationTile(notification: items[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          color: AppColors.muted,
          size: 31,
        ),
        SizedBox(height: 11),
        Text(
          '알림 없음',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotificationRecord notification;

  IconData get _icon => switch (notification.type) {
    AppNotificationType.live => Icons.sensors_rounded,
    AppNotificationType.meetup => Icons.calendar_month_rounded,
    AppNotificationType.meetupJoin => Icons.person_add_alt_1_rounded,
    AppNotificationType.meetupCancelled => Icons.event_busy_rounded,
    AppNotificationType.comment => Icons.chat_bubble_rounded,
    AppNotificationType.courtReport => Icons.verified_rounded,
  };

  String get _time {
    final difference = DateTime.now().difference(notification.createdAt);
    if (difference.inMinutes < 1) return '방금';
    if (difference.inHours < 1) return '${difference.inMinutes}분';
    if (difference.inDays < 1) return '${difference.inHours}시간';
    if (difference.inDays < 7) return '${difference.inDays}일';
    return '${notification.createdAt.month}.${notification.createdAt.day}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: notification.isUnread
          ? AppColors.accent.withValues(alpha: .09)
          : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(
        color: notification.isUnread
            ? AppColors.accent.withValues(alpha: .2)
            : AppColors.text.withValues(alpha: .055),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_icon, color: AppColors.accent, size: 19),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    _time,
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ],
              ),
              SizedBox(height: 5),
              Text(
                notification.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.soft,
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
