import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_notification.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/cine_artwork.dart';
import '../../shared/widgets/tv_focus.dart';
import '../detail/movie_detail_screen.dart';

/// Bell button for the home app bar: shows the unread count as a badge and
/// opens the notification center.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select((NotificationService s) => s.unreadCount);
    void open() {
      HapticFeedback.lightImpact();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }

    // A bare GestureDetector is not a D-pad stop at all, so on a TV the bell was
    // simply skipped when walking the app bar across to the profile avatar.
    return TvFocusable(
      onSelect: open,
      semanticLabel: 'Notifications',
      scale: 1.1,
      borderRadius: 18,
      child: GestureDetector(
        onTap: open,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_none_rounded,
                    color: AppColors.white, size: 20),
              ),
              if (unread > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppColors.surfaceContainerLow, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: AppTheme.badge.copyWith(
                          fontSize: 8, color: Colors.white, height: 1.3),
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

/// In-app notification center.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final items = service.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.94),
        surfaceTintColor: AppColors.surfaceContainerHigh,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: AppTheme.sectionTitle.copyWith(fontSize: 18),
        ),
        actions: [
          if (items.any((n) => !n.isRead))
            IconButton(
              tooltip: 'Mark all read',
              icon: const Icon(Icons.done_all_rounded,
                  color: AppColors.onSurfaceMuted, size: 22),
              onPressed: service.markAllRead,
            ),
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: AppColors.onSurfaceMuted, size: 22),
              onPressed: () {
                HapticFeedback.lightImpact();
                service.clearAll();
              },
            ),
        ],
      ),
      body: items.isEmpty ? const _EmptyState() : _buildList(context, items),
    );
  }

  Widget _buildList(BuildContext context, List<AppNotification> items) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(
          height: 1, thickness: 1, color: AppColors.outlineVariant),
      itemBuilder: (context, i) => _NotificationTile(notification: items[i]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none_rounded,
              size: 56, color: AppColors.outlineVariant),
          const SizedBox(height: 14),
          Text(
            "You're all caught up",
            style: AppTheme.sectionTitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'New releases, premieres and download updates\nwill appear here.',
            textAlign: TextAlign.center,
            style: AppTheme.metadata
                .copyWith(color: AppColors.white.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  static const Map<AppNotificationType, IconData> _icons = {
    AppNotificationType.newMovie: Icons.movie_rounded,
    AppNotificationType.newEpisode: Icons.tv_rounded,
    AppNotificationType.premiere: Icons.new_releases_rounded,
    AppNotificationType.download: Icons.download_done_rounded,
    AppNotificationType.watchlist: Icons.bookmark_added_rounded,
    AppNotificationType.continueWatching: Icons.play_for_work_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    void open() {
      HapticFeedback.lightImpact();
      context.read<NotificationService>().markAsRead(n.id);
      final movie = n.movie;
      if (movie != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
        );
      }
    }

    return TvFocusable(
      onSelect: open,
      semanticLabel: n.title,
      borderRadius: 12,
      child: InkWell(
        canRequestFocus: false,
        onTap: open,
        onLongPress: () => context.read<NotificationService>().remove(n.id),
        child: Opacity(
          opacity: n.isRead ? 0.65 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CineArtwork(
                    imageUrl: n.imageUrl,
                    width: 46,
                    height: 66,
                    icon: _icons[n.type] ?? Icons.movie_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_icons[n.type],
                              size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.metadata.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.metadata.copyWith(
                            fontSize: 12,
                            color: AppColors.white.withValues(alpha: 0.65)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _relativeTime(n.createdAt),
                        style: AppTheme.badge.copyWith(
                            fontSize: 10.5,
                            color: AppColors.white.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}
